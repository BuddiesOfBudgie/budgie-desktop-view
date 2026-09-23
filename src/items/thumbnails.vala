/*
Copyright Buddies of Budgie

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

using Gdk;

// Thumbnails finds or makes a thumbnail for a file, following the freedesktop thumbnail spec:
// https://specifications.freedesktop.org/thumbnail-spec/latest/
namespace Thumbnails {
	private const int NORMAL_SIZE = 128; // The spec's "normal" cache flavor
	private const int LARGE_SIZE = 256; // The spec's "large" cache flavor
	private const uint THUMBNAILER_TIMEOUT_SECONDS = 30; // A thumbnailer stuck on a broken file shouldn't linger

	// Installed thumbnailers, loaded on first use: MIME type to Exec line
	private HashTable<string, string>? thumbnailers = null;

	// load returns a thumbnail that fits a size x size box, or null if the file can't have one. Anything it generates
	// goes in the shared cache, so the next start and other apps reuse it instead of generating their own.
	// max_decode_bytes caps images decoded in-process; cached thumbnails and external thumbnailers ignore it.
	public async Pixbuf? load(File file, string content_type, int64 file_size, int64 max_decode_bytes, int size, Cancellable cancellable) throws Error {
		FileInfo times = yield file.query_info_async(FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE, Priority.DEFAULT, cancellable);
		string mtime = times.get_attribute_uint64(FileAttribute.TIME_MODIFIED).to_string(); // Seconds, as the spec stores it
		string uri = file.get_uri();

		// The cache is keyed by the MD5 of the URI; icons up to 128px use the normal flavor, bigger ones the large one
		bool large = size > NORMAL_SIZE;
		string cache_path = Path.build_filename(
			Environment.get_user_cache_dir(),
			"thumbnails",
			large ? "large" : "normal",
			Checksum.compute_for_string(ChecksumType.MD5, uri) + ".png"
		);

		int flavor_size = large ? LARGE_SIZE : NORMAL_SIZE;

		// A cached thumbnail that still matches the file, from us or any other app, means there's nothing to generate
		Pixbuf? cached = yield load_cached(cache_path, uri, mtime, size, cancellable);
		if (cached != null) return cached;

		// An installed thumbnailer comes next: glycin-thumbnailer for images, ffmpegthumbnailer for videos, and so on.
		// They run sandboxed or out of process, and are what other apps use, so the result matches theirs.
		string? exec = find_thumbnailer(content_type);
		if (exec != null) {
			try {
				yield run_thumbnailer(exec, file, uri, mtime, cache_path, flavor_size, cancellable);
				return yield load_cached(cache_path, uri, mtime, size, cancellable);
			} catch (Error e) {
				if (e is IOError.CANCELLED) throw e;
				warning("Thumbnailer failed for %s: %s", uri, e.message); // Images can still fall back to decoding below
			}
		}

		// Last resort for images: decode them ourselves, e.g. when no image thumbnailer is installed
		if (!content_type.has_prefix("image/") || file_size > max_decode_bytes) return null;

		Pixbuf thumb = yield decode(file, flavor_size, cancellable);
		cancellable.set_error_if_cancelled();

		try {
			store(thumb, uri, mtime, cache_path);
		} catch (Error e) {
			warning("Failed to cache the thumbnail for %s: %s", uri, e.message); // Still show it; it just won't be shared
		}

		return fit(thumb, size);
	}

	// fit scales a pixbuf down to fit a size x size box, keeping its aspect ratio
	private Pixbuf fit(Pixbuf pixbuf, int size) {
		int width = pixbuf.get_width();
		int height = pixbuf.get_height();
		if (width <= size && height <= size) return pixbuf; // Never scale small images up

		double scale = double.min((double) size / width, (double) size / height);
		return pixbuf.scale_simple(int.max((int) (width * scale), 1), int.max((int) (height * scale), 1), InterpType.BILINEAR);
	}

	// store saves a thumbnail to the cache with the spec's validity fields, atomically and readable only by the user
	private void store(Pixbuf thumb, string uri, string mtime, string cache_path) throws Error {
		DirUtils.create_with_parents(Path.get_dirname(cache_path), 0700); // The spec requires the cache to be private

		// Write next to the target, then rename, so no app ever reads a half-written thumbnail
		string tmp_path = cache_path + ".tmp";

		try {
			thumb.savev(tmp_path, "png", { "tEXt::Thumb::URI", "tEXt::Thumb::MTime" }, { uri, mtime });
			FileUtils.chmod(tmp_path, 0600); // Thumbnails reveal file contents
			FileUtils.rename(tmp_path, cache_path);
		} finally {
			FileUtils.unlink(tmp_path); // Only still there if saving or renaming failed
		}
	}

	// load_cached loads a cached thumbnail if it exists and still describes the file
	private async Pixbuf? load_cached(string cache_path, string uri, string mtime, int size, Cancellable cancellable) throws Error {
		File cache_file = File.new_for_path(cache_path);

		InputStream stream;
		try {
			stream = yield cache_file.read_async(Priority.DEFAULT, cancellable);
		} catch (IOError.NOT_FOUND e) {
			return null; // Nothing cached yet
		}

		Pixbuf thumb = yield new Pixbuf.from_stream_at_scale_async(stream, size, size, true, cancellable);

		// The spec's validity check is Thumb::MTime and Thumb::URI. Some generators leave Thumb::URI out, which makes GIO
		// report the thumbnail as invalid, so only check it when present. The MTime still catches edited files.
		if (thumb.get_option("tEXt::Thumb::MTime") != mtime) return null;

		string? thumb_uri = thumb.get_option("tEXt::Thumb::URI");
		if (thumb_uri != null && thumb_uri != uri) return null; // An MD5 collision, in theory

		return thumb;
	}

	// decode reads an image file itself, in a worker thread, scaled to fit a size x size box
	private async Pixbuf decode(File file, int size, Cancellable cancellable) throws Error {
		InputStream stream = yield file.read_async(Priority.DEFAULT, cancellable);
		Pixbuf pixbuf = yield new Pixbuf.from_stream_at_scale_async(stream, size, size, true, cancellable);

		// Cameras store rotation in EXIF instead of rotating the pixels
		Pixbuf? oriented = pixbuf.apply_embedded_orientation();
		return oriented ?? pixbuf;
	}

	// find_thumbnailer returns the Exec line of an installed thumbnailer for this content type, or null
	private string? find_thumbnailer(string content_type) {
		if (thumbnailers == null) load_thumbnailers();

		string? exec = thumbnailers.get(content_type);
		if (exec != null) return exec;

		// Content types have aliases, e.g. video/x-matroska and video/matroska, so fall back to a subtype check
		string? match = null;
		thumbnailers.foreach((mime, line) => {
			if (match == null && ContentType.is_a(content_type, mime)) match = line;
		});

		return match;
	}

	// load_thumbnailers reads the .thumbnailer files from every data dir; the user's own dir takes precedence
	private void load_thumbnailers() {
		thumbnailers = new HashTable<string, string>(str_hash, str_equal);

		string[] data_dirs = { Environment.get_user_data_dir() };
		foreach (string dir in Environment.get_system_data_dirs()) {
			data_dirs += dir;
		}

		foreach (string data_dir in data_dirs) {
			string dir_path = Path.build_filename(data_dir, "thumbnailers");

			Dir dir;
			try {
				dir = Dir.open(dir_path);
			} catch (FileError e) {
				continue; // Most data dirs don't have one
			}

			string? name;
			while ((name = dir.read_name()) != null) {
				if (!name.has_suffix(".thumbnailer")) continue;

				try {
					var entry = new KeyFile();
					entry.load_from_file(Path.build_filename(dir_path, name), KeyFileFlags.NONE);

					// TryExec names the program; skip entries whose program isn't installed
					if (entry.has_key("Thumbnailer Entry", "TryExec") &&
						Environment.find_program_in_path(entry.get_string("Thumbnailer Entry", "TryExec")) == null) {
						continue;
					}

					string exec = entry.get_string("Thumbnailer Entry", "Exec");
					foreach (string mime in entry.get_string_list("Thumbnailer Entry", "MimeType")) {
						if (!thumbnailers.contains(mime)) thumbnailers.set(mime, exec); // Earlier dirs win
					}
				} catch (Error e) {
					warning("Ignoring thumbnailer %s: %s", name, e.message);
				}
			}
		}
	}

	// run_thumbnailer runs a thumbnailer and saves its output to the cache with the spec's validity fields
	private async void run_thumbnailer(string exec, File file, string uri, string mtime, string cache_path, int thumb_size, Cancellable cancellable) throws Error {
		DirUtils.create_with_parents(Path.get_dirname(cache_path), 0700); // The spec requires the cache to be private

		// The thumbnailer writes here; store() then adds the validity fields and moves it into place
		string raw_path = cache_path + ".raw.tmp";

		// Substitute per argument after splitting, so paths with spaces stay one argument
		string[] argv;
		Shell.parse_argv(exec, out argv);
		for (int i = 0; i < argv.length; i++) {
			argv[i] = argv[i]
				.replace("%%", "\x01") // Protect literal percents from the replacements below
				.replace("%u", uri)
				.replace("%i", file.get_path())
				.replace("%o", raw_path)
				.replace("%s", thumb_size.to_string())
				.replace("\x01", "%");
		}

		var proc = new Subprocess.newv(argv, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);

		// Kill the thumbnailer when the load is superseded or takes too long; wait_check_async alone would leave it running
		bool timed_out = false;
		uint timeout_id = Timeout.add_seconds(THUMBNAILER_TIMEOUT_SECONDS, () => {
			timed_out = true;
			proc.force_exit();
			return false; // One-shot; the source is gone after this
		});
		ulong cancel_id = cancellable.connect(() => proc.force_exit());

		try {
			yield proc.wait_check_async(null);
		} finally {
			if (!timed_out) Source.remove(timeout_id); // Removing a source that already fired is an error
			cancellable.disconnect(cancel_id);
		}

		cancellable.set_error_if_cancelled();

		try {
			// Thumbnailers don't reliably add Thumb::URI and Thumb::MTime, so re-save with them
			store(new Pixbuf.from_file(raw_path), uri, mtime, cache_path);
		} finally {
			FileUtils.unlink(raw_path);
		}
	}
}
