/*
Copyright 2021 Solus Project

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

	private FileItem? file_item;
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
		if (file_item == null) {
			return;
		}

		file_item.move_to_trash();
	}

	// on_open_activated will handle clicking the Open option
	private void on_open_activated() {
		if (file_item == null) {
			return;
		}

		if (is_copying) { // This file is currently copying so we shouldn't open it
			return;
		}

		file_item.launch(false); // Launch normally
		popdown();
	}

	// on_open_in_terminal_activated will handle clicking the Open in Terminal option
	private void on_open_in_terminal_activated() {
		if (file_item == null) {
			return;
		}

		if (is_copying) { // This file is currently copying so we shouldn't open it
			return;
		}

		file_item.launch(true); // Launch with terminal
		popdown();
	}

	// set_item will set the File Item
	public void set_item(FileItem item) {
		file_item = item;
	}

	// show_menu will handle showing the menu
	public void show_menu(EventButton event) {
		set_screen(Screen.get_default());
		popup_at_pointer(event);
	}
}