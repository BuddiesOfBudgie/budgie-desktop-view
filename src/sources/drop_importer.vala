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

// DropImporter puts files dropped in from other apps onto the Desktop: directories are symlinked, files are copied
public class DropImporter : Object {
	private unowned UnifiedProps props;
	private DesktopFolder folder;

	public DropImporter(UnifiedProps p, DesktopFolder desktop_folder) {
		props = p;
		folder = desktop_folder;
	}

	// import handles a text/uri-list drop and returns the Desktop files it is creating. Copies finish asynchronously,
	// so the returned files may not exist yet.
	public GenericArray<File> import(string uri_list) {
		var targets = new GenericArray<File>();
		string[] uris = uri_list.chomp().split("\n"); // Split on newlines in case we pass multiple items

		foreach (string file_uri in uris) { // For each file URI
			file_uri = file_uri.chomp(); // uri-lists use \r\n line endings

			File this_file = File.new_for_uri(file_uri); // Load this file
			string file_base = this_file.get_basename();

			File? source_dir = this_file.get_parent();
			if (source_dir != null && source_dir.get_path() == folder.path) { // Copying from the Desktop to Desktop
				continue; // basically nothing to-do since they are the same
			}

			var can = new Cancellable(); // Create a new cancellable stack
			FileInfo? finfo = null;

			try {
				finfo = this_file.query_info("standard::*", FileQueryInfoFlags.NONE, can);
			} catch (Error e) {
				warning("Failed to get requested information on this file: %s", e.message);
				continue; // Skip
			}

			if (can.is_cancelled() || (finfo == null)) { // Cancelled or failed to get info
				warning("Failed to get information on this file.");
				continue; // Skip
			}

			string proposed_file_name = file_base;

			if (folder.contains(file_base)) { // Already have a file called this
				proposed_file_name = CopyName.next_free(file_base, (name) => {
					return File.new_for_path(Path.build_filename(folder.path, name)).query_exists();
				});
			}

			string target_path = Path.build_filename(folder.path, proposed_file_name);
			File target_file = File.new_for_path(target_path); // "Create" our target file
			targets.add(target_file);

			if (finfo.get_file_type() == FileType.DIRECTORY) { // If the file is a directory
				try {
					target_file.make_symbolic_link(this_file.get_path());
				} catch (Error e) {
					warning("Failed to symlink to %s: %s", target_path, e.message);
				}
			} else { // Is a file
				copy_file(this_file, target_file, proposed_file_name);
			}
		}

		return targets;
	}

	// copy_file copies in the background, marking the item as copying until it finishes
	private void copy_file(File source, File target, string target_name) {
		Cancellable file_cancellable = new Cancellable(); // Create a new cancellable so we can cancel the file
		props.files_currently_copying.set(target_name, file_cancellable); // Lets Move to Trash cancel the copy

		// Follow symlinks so exported desktop files, like flatpak's relative
		// links into /var/lib/flatpak, copy as the file they point at
		source.copy_async.begin(target, FileCopyFlags.NONE, 0, file_cancellable, null, (obj, res) => {
			props.files_currently_copying.remove(target_name); // Remove the file we were copying from our list
			folder.update_saturation(target_name); // Update our item saturation

			try {
				source.copy_async.end(res);
			} catch (Error e) {
				if (!file_cancellable.is_cancelled()) { // Did not fail due to a cancelled copy
					warning("Failed to copy %s: %s", target_name, e.message);
					folder.remove_file(target); // Delete the item
				}
			}
		});
	}
}
