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

	private GLib.Settings settings;
	private HashTable<string, Gtk.RadioMenuItem> sort_items; // Keyed by arrange-order nick
	private Gtk.RadioMenuItem? first_sort_item = null; // Every Sort By entry joins this one's radio group
	private bool syncing_sort = false; // Set while the radio items follow the setting, so they don't re-run the action

	public DesktopMenu(DesktopView view, GLib.Settings settings) {
		Object();
		desktop_view = view;
		this.settings = settings;
		sort_items = new HashTable<string, Gtk.RadioMenuItem>(str_hash, str_equal);

		budgie_app = new DesktopAppInfo("org.buddiesofbudgie.BudgieDesktopSettings.desktop");
		bcc_app = new DesktopAppInfo("org.buddiesofbudgie.ControlCenter.desktop");

		Gtk.MenuItem budgie_item = new Gtk.MenuItem.with_label(_("Budgie Desktop Settings"));
		Gtk.MenuItem system_item = new Gtk.MenuItem.with_label(_("System Settings"));
		// Both toggles are bound straight to their settings; the arranger follows the settings
		var auto_arrange_item = new Gtk.CheckMenuItem.with_label(_("Auto-arrange"));
		settings.bind("auto-arrange", auto_arrange_item, "active", SettingsBindFlags.DEFAULT);
		var snap_to_grid_item = new Gtk.CheckMenuItem.with_label(_("Snap to Grid"));
		settings.bind("snap-to-grid", snap_to_grid_item, "active", SettingsBindFlags.DEFAULT);

		budgie_item.activate.connect(on_budgie_settings_activated); // Activate on_budgie_settings_activated when we press the Budgie item
		system_item.activate.connect(on_system_settings_activated); // Activate on_system_settings_activated when we press the System item

		// Align and Sort run the application actions, which act on the selection or the whole desktop
		Gtk.MenuItem align_item = new Gtk.MenuItem.with_label(_("Align to Grid"));
		align_item.activate.connect(() => activate_app_action("align-to-grid", null));

		Gtk.MenuItem sort_item = new Gtk.MenuItem.with_label(_("Sort By"));
		var sort_menu = new Gtk.Menu();
		sort_menu.append(create_sort_item(_("Name"), "name"));
		sort_menu.append(create_sort_item(_("Type"), "type"));
		sort_menu.append(create_sort_item(_("Date Modified"), "modified"));
		sort_item.set_submenu(sort_menu);

		// The radio items show the current order, including changes made outside the menu
		sync_sort_items();
		settings.changed["arrange-order"].connect(sync_sort_items);

		budgie_item.show_all();
		system_item.show_all();
		auto_arrange_item.show_all();
		snap_to_grid_item.show_all();
		align_item.show_all();
		sort_item.show_all();

		insert(budgie_item, 0);
		insert(system_item, 1);
		insert(new Gtk.SeparatorMenuItem() { visible = true }, 2); // Menu children start hidden, separators included
		insert(auto_arrange_item, 3);
		insert(snap_to_grid_item, 4);
		insert(new Gtk.SeparatorMenuItem() { visible = true }, 5);
		insert(align_item, 6);
		insert(sort_item, 7);
	}

	// create_sort_item makes a Sort By radio entry that runs the sort-by action with the given key
	private Gtk.RadioMenuItem create_sort_item(string label, string key) {
		var item = (first_sort_item == null)
			? new Gtk.RadioMenuItem.with_label(null, label)
			: new Gtk.RadioMenuItem.with_label_from_widget(first_sort_item, label);
		if (first_sort_item == null) first_sort_item = item;

		// Picking the current order again still runs it, which re-sorts a manual layout after things moved
		item.activate.connect(() => {
			if (syncing_sort || !item.active) return; // Setting a radio item active emits activate too
			activate_app_action("sort-by", new Variant.string(key));
		});

		item.show();
		sort_items.set(key, item);
		return item;
	}

	// sync_sort_items checks the Sort By entry matching the arrange-order setting
	private void sync_sort_items() {
		Gtk.RadioMenuItem? item = sort_items.get(settings.get_string("arrange-order")); // Enum keys read back as their nick
		if (item == null) return;

		syncing_sort = true;
		item.active = true;
		syncing_sort = false;
	}

	// activate_app_action runs one of the application's actions, then closes the menu
	private void activate_app_action(string name, Variant? parameter) {
		desktop_view.application.activate_action(name, parameter);
		popdown();
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
