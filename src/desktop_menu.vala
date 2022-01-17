/*
Copyright 2022 Buddies of Budgie
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

public class DesktopMenu : Gtk.Menu {
	private DesktopAppInfo budgie_app;
	private DesktopAppInfo bcc_app;

	public DesktopMenu() {
		Object();

		budgie_app = new DesktopAppInfo("budgie-desktop-settings.desktop");
		bcc_app = new DesktopAppInfo("budgie-control-center.desktop");

		Gtk.MenuItem budgie_item = new Gtk.MenuItem.with_label(_("Budgie Desktop Settings"));
		Gtk.MenuItem system_item = new Gtk.MenuItem.with_label(_("System Settings"));

		budgie_item.activate.connect(on_budgie_settings_activated); // Activate on_budgie_settings_activated when we press the Budgie item
		system_item.activate.connect(on_system_settings_activated); // Activate on_system_settings_activated when we press the System item

		budgie_item.show_all();
		system_item.show_all();

		insert(budgie_item, 0);
		insert(system_item, 1);
	}

	// on_budgie_settings_activated handles our launching of Budgie Desktop Settings
	private void on_budgie_settings_activated() {
		try {
			budgie_app.launch(null, (Display.get_default()).get_app_launch_context());
		} catch (Error e) {
			warning("Failed to launch Budgie Desktop settings: %s", e.message);
		}
		popdown(); // Hide the menu
	}

	// on_system_settings_activated handles our launching of GNOME Control Center
	private void on_system_settings_activated() {
		try {
			bcc_app.launch(null, (Display.get_default()).get_app_launch_context());
		} catch (Error e) {
			warning("Failed to launch GNOME Control Center: %s", e.message);
		}
		popdown(); // Hide the menu
	}
}