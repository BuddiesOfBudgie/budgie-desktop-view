/*
Copyright 2020 Solus Project

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
	private FileItem? file_item;

	public FileMenu() {
		Object();

		Gtk.MenuItem open_item = new Gtk.MenuItem.with_label(_("Open"));
		Gtk.MenuItem open_in_terminal_item = new Gtk.MenuItem.with_label(_("Open in Terminal"));

		open_item.activate.connect(on_open_activated);
		open_in_terminal_item.activate.connect(on_open_in_terminal_activated);

		open_item.show_all();
		open_in_terminal_item.show_all();

		insert(open_item, 0);
		insert(open_in_terminal_item, 1);
	}

	// on_open_activated will handle clicking the Open option
	private void on_open_activated() {
		if (file_item == null) {
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