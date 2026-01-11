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

public class DesktopMenu : Gtk.Menu {
	private DesktopAppInfo budgie_app;
	private DesktopAppInfo bcc_app;
	private DesktopView? desktop_view;
	private Gtk.CheckMenuItem auto_arrange_item;

	public signal void toggle_auto_arrange();

	public DesktopMenu(DesktopView view) {
		Object();
		desktop_view = view;

		budgie_app = new DesktopAppInfo("org.buddiesofbudgie.BudgieDesktopSettings.desktop");
		bcc_app = new DesktopAppInfo("org.buddiesofbudgie.ControlCenter.desktop");

		Gtk.MenuItem budgie_item = new Gtk.MenuItem.with_label(_("Budgie Desktop Settings"));
		Gtk.MenuItem system_item = new Gtk.MenuItem.with_label(_("System Settings"));
		auto_arrange_item = new Gtk.CheckMenuItem.with_label(_("Auto-arrange"));

		budgie_item.activate.connect(on_budgie_settings_activated); // Activate on_budgie_settings_activated when we press the Budgie item
		system_item.activate.connect(on_system_settings_activated); // Activate on_system_settings_activated when we press the System item
		auto_arrange_item.activate.connect(on_auto_arrange_activated); // Activate on_auto_arrange when we click the auto-arrange item

		budgie_item.show_all();
		system_item.show_all();
		auto_arrange_item.show_all();

		insert(budgie_item, 0);
		insert(system_item, 1);
		insert(new Gtk.SeparatorMenuItem(), 2);
		insert(auto_arrange_item, 3);

		// Start with auto-arrange checked (default state)
		auto_arrange_item.set_active(true);
	}

	// on_auto_arrange_activated handles toggling auto-arrange
	private void on_auto_arrange_activated() {
		toggle_auto_arrange();
		popdown();
	}

	// set_auto_arrange_state updates the check state of the menu item
	public void set_auto_arrange_state(bool is_auto_arranged) {
		// Temporarily block the signal to avoid recursion
		auto_arrange_item.activate.disconnect(on_auto_arrange_activated);
		auto_arrange_item.set_active(is_auto_arranged);
		auto_arrange_item.activate.connect(on_auto_arrange_activated);

		if (is_auto_arranged) {
			debug("Auto-arrange menu: checked (alphabetical sorting)");
		} else {
			debug("Auto-arrange menu: unchecked (manual positioning)");
		}
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

	// on_system_settings_activated handles our launching of Budgie Control Center
	private void on_system_settings_activated() {
		try {
			bcc_app.launch(null, (Display.get_default()).get_app_launch_context());
		} catch (Error e) {
			warning("Failed to launch Budgie Control Center: %s", e.message);
		}
		popdown(); // Hide the menu
	}
}
