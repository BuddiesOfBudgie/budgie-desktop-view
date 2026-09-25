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

// DesktopFolder watches the user's Desktop directory and keeps a FileItem for each file shown from it
public class DesktopFolder : Object {
	private unowned UnifiedProps props;
	private File directory;
	private FileMonitor? monitor = null;
	private HashTable<string, FileItem> items; // Keyed by FileItem.layout_id_for(file), i.e. the path

	public string path { get; private set; }

	// item_added and item_removed track individual items; changed follows a batch of them so the view can relayout once
	public signal void item_added(FileItem item);
	public signal void item_removed(FileItem item);
	public signal void changed();

	// file_renamed is emitted before the old item goes and the new one arrives, so its layout position can follow the rename
	public signal void file_renamed(File from, File to);
	// file_deleted means the file is gone for good, so its layout position can be dropped too
	public signal void file_deleted(File file);

	public DesktopFolder(UnifiedProps p) {
		props = p;
		items = new HashTable<string, FileItem>(str_hash, str_equal);
		path = Environment.get_user_special_dir(UserDirectory.DESKTOP);
		directory = File.new_for_path(path); // Get the Desktop folder "file"

		try {
			monitor = directory.monitor(FileMonitorFlags.WATCH_MOVES, null); // Create our file monitor
			monitor.changed.connect(on_file_changed); // Bind to our file changed event
		} catch (Error e) {
			warning("Failed to obtain a monitor for file changes to the Desktop folder. Will not be able to watch for changes: %s", e.message);
		}
	}

	// load will get all the files in our Desktop folder and generate items for them. It doesn't emit changed().
	public void load() {
		var c = new Cancellable(); // Create a new cancellable stack
		FileEnumerator? desktop_file_enumerator = null;

		try {
			desktop_file_enumerator = directory.enumerate_children(FileItem.INFO_ATTRIBUTES, FileQueryInfoFlags.NONE, c);
		} catch (Error e) {
			error("Failed to get requested information on our Desktop: %s", e.message);
		}

		if (desktop_file_enumerator == null) { // Failed to enumerate the file
			return;
		}

		try {
			FileInfo? file_info = null;
			while (!c.is_cancelled() && ((file_info = desktop_file_enumerator.next_file(c)) != null)) { // While we still haven't cancelled and have a file
				if (!file_info.get_is_hidden()) { // If the file is not hidden
					File f = desktop_file_enumerator.get_child(file_info);
					add_item(f, file_info); // Create our item
				}
			}
		} catch (Error e) {
			warning("Failed to iterate on files in Desktop folder: %s", e.message);
		}

		if (c.is_cancelled()) { // If our cancellable was cancelled
			warning("Desktop reading was cancelled");
		}
	}

	// add_item will create our FileItem and add it if necessary
	private void add_item(File f, FileInfo info) {
		if (info.get_is_hidden()) { // This is a hidden file
			return; // Don't do anything
		}

		string key = FileItem.layout_id_for(f);

		if (items.contains(key)) { // Already have this
			return;
		}

		FileType created_file_type = info.get_file_type(); // Get the type of the file

		bool supported_type = ((created_file_type == FileType.DIRECTORY) || (created_file_type == FileType.REGULAR));

		if (supported_type) { // If this is a supported type
			FileItem item = new FileItem(props, f, info, null); // Create our new Item
			if (item.exclude_item) { // Shouldn't actually include this item
				return;
			}

			items.set(key, item);
			item_added(item);
		}
	}

	// remove_file will delete any references to a file and its FileItem, then ask for a relayout
	public void remove_file(File f) {
		string key = FileItem.layout_id_for(f);
		FileItem? file_item = items.get(key);
		if (file_item == null) return; // Never had an item, e.g. a hidden file

		items.remove(key);
		item_removed(file_item);
		changed(); // Every caller wants the gap closed, including a failed copy from DropImporter
	}

	// update_saturation will update the saturation of a FileItem based on if it is being copied
	public void update_saturation(File f) {
		FileItem? file_item = items.get(FileItem.layout_id_for(f));

		if (file_item == null) { // Item doesn't exist
			return;
		}

		file_item.is_copying = props.is_copying(f.get_basename()); // Copies are tracked by basename, see DropImporter
	}

	// on_file_changed will handle when a file changes in the Desktop directory
	private void on_file_changed(File file, File? other_file, FileMonitorEvent type) {
		if (type == FileMonitorEvent.PRE_UNMOUNT || type == FileMonitorEvent.UNMOUNTED) {
			return; // Don't accept anything from these events
		}

		if (file.get_basename().has_prefix(".")) { // Ignore since we never would've added it
			return;
		}

		bool do_create = false;
		bool do_delete = false;
		File? create_file_ref = null;
		File? delete_file_ref = null;

		if (type == FileMonitorEvent.RENAMED) { // File renamed
			do_create = true; // Going to be creating a new FileItem for new file
			do_delete = true; // Going to be deleting old FileItem for old file
			create_file_ref = other_file; // Set to other_file since that is set for RENAMED
			delete_file_ref = file; // file list the old file

			if (other_file != null) {
				file_renamed(file, other_file); // Before the delete below, so the position is re-keyed rather than lost
			}
		} else if ((type == FileMonitorEvent.MOVED_IN) || (type == FileMonitorEvent.CREATED)) { // File was created in or moved to our Desktop folder
			do_create = true;
			create_file_ref = file;
		} else if ((type == FileMonitorEvent.MOVED_OUT) || (type == FileMonitorEvent.DELETED)) {  // File was deleted or moved out of our Desktop folder
			do_delete = true;
			delete_file_ref = file;
			file_deleted(file);
		}

		if ((do_delete) && (delete_file_ref != null)) { // Handle deletions first
			remove_file(delete_file_ref); // Only pass the file reference since we won't be able to get file info
		}

		if ((do_create) && (create_file_ref != null)) { // Do creations after any potential deletions
			if (create_file_ref.get_basename().has_prefix(".")) { // Hidden file
				return;
			}

			Timeout.add(100, () => { // Gives just enough time usually for the file to finish syncing and start reporting a correct mimetype
				try {
					FileInfo created_file_info = create_file_ref.query_info(FileItem.INFO_ATTRIBUTES, 0);

					if (items.contains(FileItem.layout_id_for(create_file_ref)) || // Already have this
						created_file_info.get_is_hidden() // Is hidden
					) {
						return false;
					}

					add_item(create_file_ref, created_file_info); // Create our item
					update_saturation(create_file_ref); // A dropped file may still be copying
					changed();
				} catch (Error e) { // Failed to get created file info
					warning("Failed to create file item: %s", e.message);
				}

				return false;
			});

			return; // Return for safety
		}

		if (file.query_exists() && !do_create && !do_delete && ( // File is changed since we're not creating or deleting it
			(type == FileMonitorEvent.ATTRIBUTE_CHANGED) || // Attributes changed
			(type == FileMonitorEvent.CHANGES_DONE_HINT)  // Changes probably done
		)) { // File changed
			Timeout.add(50, () => { // Delay for sync if necessary
				try {
					FileInfo existing_file_info = file.query_info(FileItem.INFO_ATTRIBUTES, 0); // Get the file's info
					FileItem? file_item = items.get(FileItem.layout_id_for(file));

					if (file_item != null) { // If we have this item
						file_item.info = existing_file_info; // Update the file info
						file_item.update_icon(); // Also reloads the thumbnail, e.g. for an edited or just-copied image
					}
				} catch (Error e) {
					warning("Failed to get updated attributes for file. %s", e.message);
				}

				return false;
			});
		}
	}
}
