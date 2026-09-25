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

// Made-up content types, so no installed thumbnailer matches and only the cache or the test thumbnailer below can
// produce a result. System data dirs stay as they are; gdk-pixbuf may need them to find its image loaders.
const string CACHED_ONLY_TYPE = "application/x-bdv-test";
const string FAILING_TYPE = "application/x-bdv-fails";
const string SLOW_TYPE = "application/x-bdv-slow";
const uint64 MTIME = 1000;

string cache_dir;
string work_dir;
string counter_path; // The failing thumbnailer appends a line here each time it runs
string slow_log_path; // The slow thumbnailer writes "start" and "end" here around each run

// load_sync runs Thumbnails.load to completion
Pixbuf? load_sync(File file, FileInfo info) {
	var loop = new MainLoop();
	Pixbuf? result = null;

	Thumbnails.load.begin(file, info, 0, 48, new Cancellable(), (obj, res) => {
		try {
			result = Thumbnails.load.end(res);
		} catch (Error e) {
			Test.message("load failed: %s", e.message);
			Test.fail();
		}
		loop.quit();
	});

	loop.run();
	return result;
}

// test_info is what a FileItem would hold for a file of this type, modified at MTIME
FileInfo test_info(string content_type) {
	var info = new FileInfo();
	info.set_content_type(content_type);
	info.set_size(1);
	info.set_attribute_uint64(FileAttribute.TIME_MODIFIED, MTIME);
	return info;
}

// write_cached stores a thumbnail for file in the normal cache with the given text fields, as another app might
void write_cached(File file, string[] keys, string[] values) {
	string path = Path.build_filename(
		cache_dir, "thumbnails", "normal",
		Checksum.compute_for_string(ChecksumType.MD5, file.get_uri()) + ".png"
	);

	try {
		DirUtils.create_with_parents(Path.get_dirname(path), 0700);
		var thumb = new Pixbuf(Colorspace.RGB, true, 8, 4, 4);
		thumb.fill(0);
		thumb.savev(path, "png", keys, values);
	} catch (Error e) {
		error("Failed to write test thumbnail: %s", e.message);
	}
}

File test_file(string name) {
	return File.new_for_path(Path.build_filename(work_dir, name));
}

void test_cached_without_uri() {
	// Some generators leave Thumb::URI out; a matching MTime is still enough
	File file = test_file("no-uri.bin");
	write_cached(file, { "tEXt::Thumb::MTime" }, { MTIME.to_string() });
	assert_true(load_sync(file, test_info(CACHED_ONLY_TYPE)) != null);
}

void test_cached_stale_mtime() {
	File file = test_file("stale.bin");
	write_cached(file, { "tEXt::Thumb::URI", "tEXt::Thumb::MTime" }, { file.get_uri(), (MTIME - 1).to_string() });
	assert_true(load_sync(file, test_info(CACHED_ONLY_TYPE)) == null);
}

void test_cached_other_uri() {
	File file = test_file("collision.bin");
	write_cached(file, { "tEXt::Thumb::URI", "tEXt::Thumb::MTime" }, { "file:///somewhere/else", MTIME.to_string() });
	assert_true(load_sync(file, test_info(CACHED_ONLY_TYPE)) == null);
}

void test_failed_thumbnailer_not_retried() {
	File file = test_file("broken.bin");

	// The first load runs the thumbnailer, which fails and gets recorded
	Test.expect_message(null, LogLevelFlags.LEVEL_WARNING, "*Thumbnailer failed*");
	assert_true(load_sync(file, test_info(FAILING_TYPE)) == null);
	Test.assert_expected_messages();

	// The second load in the same session skips the thumbnailer, so nothing is logged either
	assert_true(load_sync(file, test_info(FAILING_TYPE)) == null);

	string runs;
	try {
		FileUtils.get_contents(counter_path, out runs);
	} catch (Error e) {
		error("Thumbnailer never ran: %s", e.message);
	}
	assert_true(runs.split("\n").length - 1 == 1);
}

void test_thumbnailers_limited() {
	const int LOADS = 4;
	var loop = new MainLoop();
	int remaining = LOADS;

	// All four fail after a short sleep; each failure logs a warning
	for (int i = 0; i < LOADS; i++) {
		Test.expect_message(null, LogLevelFlags.LEVEL_WARNING, "*Thumbnailer failed*");
	}

	// Start every load at once, as items do on startup
	for (int i = 0; i < LOADS; i++) {
		File file = test_file("slow-%d.bin".printf(i));
		Thumbnails.load.begin(file, test_info(SLOW_TYPE), 0, 48, new Cancellable(), (obj, res) => {
			try {
				Thumbnails.load.end(res);
			} catch (Error e) {
				Test.message("load failed: %s", e.message);
				Test.fail();
			}
			if (--remaining == 0) loop.quit();
		});
	}

	loop.run();
	Test.assert_expected_messages();

	// Replay the log to find how many runs overlapped at most
	string log;
	try {
		FileUtils.get_contents(slow_log_path, out log);
	} catch (Error e) {
		error("Slow thumbnailer never ran: %s", e.message);
	}

	int running = 0;
	int peak = 0;
	int starts = 0;
	foreach (string line in log.split("\n")) {
		if (line == "start") {
			running++;
			starts++;
		} else if (line == "end") {
			running--;
		}
		peak = int.max(peak, running);
	}

	assert_true(starts == LOADS); // None were skipped
	assert_true(peak <= 2); // MAX_THUMBNAILERS in thumbnails.vala
}

public static int main(string[] args) {
	string root;
	try {
		root = DirUtils.make_tmp("bdv-thumbnails-XXXXXX");
	} catch (Error e) {
		error("Failed to create temp dir: %s", e.message);
	}

	cache_dir = Path.build_filename(root, "cache");
	work_dir = Path.build_filename(root, "files");
	string data_dir = Path.build_filename(root, "data");
	counter_path = Path.build_filename(root, "runs");
	slow_log_path = Path.build_filename(root, "slow-log");
	DirUtils.create_with_parents(work_dir, 0700);

	// A thumbnailer that always fails and counts its runs, as the only one installed
	string thumbnailers_dir = Path.build_filename(data_dir, "thumbnailers");
	DirUtils.create_with_parents(thumbnailers_dir, 0700);
	try {
		FileUtils.set_contents(
			Path.build_filename(thumbnailers_dir, "failing.thumbnailer"),
			"[Thumbnailer Entry]\nTryExec=sh\nExec=sh -c \"echo run >> '%s'; exit 1\"\nMimeType=%s;\n".printf(counter_path, FAILING_TYPE)
		);

		// Slow enough that loads started together would overlap if nothing limited them
		FileUtils.set_contents(
			Path.build_filename(thumbnailers_dir, "slow.thumbnailer"),
			"[Thumbnailer Entry]\nTryExec=sh\nExec=sh -c \"echo start >> '%s'; sleep 0.3; echo end >> '%s'; exit 1\"\nMimeType=%s;\n".printf(slow_log_path, slow_log_path, SLOW_TYPE)
		);
	} catch (Error e) {
		error("Failed to write test thumbnailer: %s", e.message);
	}

	// GLib reads these once, so they're set before anything asks for a cache or data dir
	Environment.set_variable("XDG_CACHE_HOME", cache_dir, true);
	Environment.set_variable("XDG_DATA_HOME", data_dir, true); // Thumbnailers here take precedence over system ones

	Test.init(ref args);

	Test.add_func("/items/thumbnails/cached-without-uri", test_cached_without_uri);
	Test.add_func("/items/thumbnails/cached-stale-mtime", test_cached_stale_mtime);
	Test.add_func("/items/thumbnails/cached-other-uri", test_cached_other_uri);
	Test.add_func("/items/thumbnails/failed-not-retried", test_failed_thumbnailer_not_retried);
	Test.add_func("/items/thumbnails/limited-concurrency", test_thumbnailers_limited);

	return Test.run();
}
