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
using Gtk;

public class FileMenu : Gtk.Menu {
	protected unowned UnifiedProps props;

	private FileItem? file_item; // The item that was right-clicked
	private List<FileItem>? selected_items; // All currently selected items
	private Gtk.MenuItem cancel_copy_item;
	private Gtk.MenuItem open_item;
	private Gtk.MenuItem open_in_terminal_item;
	private Gtk.MenuItem trash_item;

	private bool _is_copying;
	private bool _show_open_in_terminal;

	//public signal void remove_item_for_file(File? file);

	public FileMenu(UnifiedProps p) {
		Object();
		props = p;

		cancel_copy_item = new Gtk.MenuItem.with_label(_("Cancel Copy"));
		open_item = new Gtk.MenuItem.with_label(_("Open"));
		open_in_terminal_item = new Gtk.MenuItem.with_label(_("Open in Terminal"));

		trash_item = new Gtk.MenuItem.with_label(_("Move to Trash"));

		cancel_copy_item.activate.connect(move_to_trash);
		open_item.activate.connect(on_open_activated);
		open_in_terminal_item.activate.connect(on_open_in_terminal_activated);
		trash_item.activate.connect(move_to_trash);

		open_item.show_all();
		open_in_terminal_item.show_all();

		insert(cancel_copy_item, 0);
		insert(open_item, 1);
		insert(open_in_terminal_item, 2);
		insert(trash_item, 4);

		is_copying = false;
		show_open_in_terminal = true;
	}

	public bool is_copying {
		public get {
			return _is_copying;
		}

		public set {
			_is_copying = value;

			if (_is_copying) {
				cancel_copy_item.show();
				open_item.hide();
				open_in_terminal_item.hide();
				trash_item.hide();
			} else {
				cancel_copy_item.hide();
				open_item.show();
				open_in_terminal_item.show();

				if (file_item != null) {
					if(file_item.is_special) { // Is a special directory
						trash_item.hide();
					} else {
						trash_item.show();
					}
				}
			}
		}
	}

	public bool show_open_in_terminal {
		public get {
			return _show_open_in_terminal;
		}

		public set {
			_show_open_in_terminal = value;

			if (_show_open_in_terminal) {
				open_in_terminal_item.show();
			} else {
				open_in_terminal_item.hide();
			}
		}
	}

	// move_to_trash will move the current file associated with the file item to trash
	// If the file is copying, it will be cancelled
	public void move_to_trash() {
		if (selected_items == null || selected_items.length() == 0) {
			warning("Move to trash activated but no items selected");
 			return;
 		}

		// Move all selected items to trash
		debug("Moving %u selected item(s) to trash", selected_items.length());

		foreach (FileItem item in selected_items) {
			// Don't move special items (Home, Trash) or mounts
			if (item.is_special) {
				debug("Skipping special item: %s", item.label_name);
				continue;
			}

			debug("Moving to trash: %s", item.label_name);
			item.move_to_trash();
		}

		popdown();
}

	// on_open_activated will handle clicking the Open option
	private void on_open_activated() {
		if (selected_items == null || selected_items.length() == 0) {
			warning("Open activated but no items selected");
			return;
		}

		if (is_copying) return; // This file is currently copying so we shouldn't open it

		// Launch all selected items
		debug("Launching %u selected item(s)", selected_items.length());
		foreach (FileItem item in selected_items) {
			if (!props.is_copying(item.info.get_display_name())) {
				item.launch(false); // Launch normally
			} else {
				debug("Skipping %s - currently copying", item.label_name);
			}
		}

		popdown();
	}

	// on_open_in_terminal_activated will handle clicking the Open in Terminal option
	private void on_open_in_terminal_activated() {
		if (selected_items == null || selected_items.length() == 0) {
			warning("Open in terminal activated but no items selected");
			return;
		}

		if (is_copying) return; // This file is currently copying so we shouldn't open it

		// For terminal, only open the first selected item
		// (opening multiple terminals isn't a great idea)
		if (selected_items.length() > 1) {
			debug("Multiple items selected, opening first item in terminal: %s", selected_items.nth_data(0).label_name);
		}

		FileItem first_item = selected_items.nth_data(0);
		if (!props.is_copying(first_item.info.get_display_name())) {
			first_item.launch(true); // Launch with terminal
		}

		popdown();
	}

	// set_item will set the File Item
	public void set_item(FileItem item, List<FileItem>? selected = null) {
		file_item = item;

		// Update selected items list
		selected_items = new List<FileItem>();
		if (selected != null && selected.length() > 0) {
			// Use the provided selection
			foreach (FileItem selected_item in selected) {
				selected_items.append(selected_item);
			}
		} else {
			// Just the single item
			selected_items.append(item);
		}

		// Update menu item labels based on selection count
		if (selected_items.length() > 1) {
			open_item.set_label(_("Open %u Items").printf(selected_items.length()));
			trash_item.set_label(_("Move %u Items to Trash").printf(selected_items.length()));
			// Keep "Open in Terminal" singular - it only opens the first item
		} else {
			open_item.set_label(_("Open"));
			trash_item.set_label(_("Move to Trash"));
		}
	}

	// show_menu will handle showing the menu
	public void show_menu(EventButton event) {
		set_screen(Screen.get_default());
		popup_at_pointer(event);
	}
}
