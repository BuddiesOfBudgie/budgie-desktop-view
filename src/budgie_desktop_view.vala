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

public const int MARGIN = 20; // pixel spacing for left/right

public const string POSITIONS_DIR = "budgie-desktop-view";
public const string LAYOUT_FILE = "layout.gvariant";
public const string LEGACY_POSITIONS_FILE = "icon-positions.conf";

public enum DesktopItemSize {
	SMALL = 0, // 32x32
	NORMAL = 1, // 48x48
	LARGE = 2, // 64x64
	MASSIVE = 3; // 96x96
}

public const int ITEM_MARGIN = 10;

public const string[] SUPPORTED_TERMINALS = {
	"alacritty",
	"gnome-terminal",
	"kgx",
	"kitty",
	"konsole",
	"mate-terminal",
	"terminator",
	"tilix",
	"xfce4-terminal"
};

// DesktopView is the desktop window. It sets up the layer surface, follows the monitor and settings, and wires the
// item sources (Desktop folder, mounts, drops) to the canvas and arranger.
public class DesktopView : Gtk.ApplicationWindow {
	libxfce4windowing.Screen default_screen;
	Gdk.Display default_display;
	libxfce4windowing.Monitor? primary_monitor;
	UnifiedProps shared_props;

	// The canvas's allocated size, which is what the grid has to fit. On Wayland the monitor workarea still includes
	// panels, so this comes from the compositor's sizing of our layer surface instead.
	int canvas_width = 0;
	int canvas_height = 0;

	double zoom_scroll = 0; // Touchpad scroll distance built up towards the next Ctrl+scroll icon size step

	DesktopItemSize? item_size; // Default our Item Size to NORMAL
	int? max_allocated_item_height;
	int? max_allocated_item_width;
	bool show_home;
	bool show_mounts;
	bool show_trash;
	bool visible_setting;

	DesktopMenu desktop_menu;
	DesktopCanvas canvas;
	DesktopArranger arranger;

	DesktopFolder desktop_folder;
	MountTracker mounts;
	DropImporter drop_importer;

	FileItem? home_item = null;
	FileItem? trash_item = null;

	public DesktopView(Gtk.Application app) {
		Object(
			application: app,
			app_paintable: true,
			decorated: false,
			expand: false,
			icon_name: "user-desktop",
			resizable: false,
			skip_pager_hint: true,
			skip_taskbar_hint: true,
			startup_id: "org.buddiesofbudgie.budgie-desktop-view",
			type_hint: Gdk.WindowTypeHint.DESKTOP
		);

		GtkLayerShell.init_for_window(this);
		GtkLayerShell.set_layer(this, GtkLayerShell.Layer.BOTTOM);

		// Anchored to every edge, the compositor sizes us to the output minus other surfaces' exclusive zones, i.e. the
		// space panels leave free. Edge is an enum, not flags, so each edge is set separately.
		GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.TOP, true);
		GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, true);
		GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT, true);
		GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT, true);
		GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.ON_DEMAND);
		GtkLayerShell.try_force_commit(this);

		shared_props = new UnifiedProps(); // Create shared props
		shared_props.cursor_changed.connect((cursor) => {
			get_window().set_cursor(cursor);
		});
		shared_props.thumbnail_size_changed.connect(refresh_icon_sizes); // When our thumbnail size changed, refresh our icons

		Gtk.Settings? default_settings = Gtk.Settings.get_default(); // Get the default settings
		default_settings.gtk_application_prefer_dark_theme = true;

		shared_props.desktop_settings = new GLib.Settings("org.buddiesofbudgie.budgie-desktop-view"); // Get our desktop-view settings

		if (shared_props.desktop_settings == null) {
			warning("Required gschema not installed.");
			close(); // Close the window
		}

		shared_props.desktop_settings.changed["icon-size"].connect(on_icon_size_changed);
		shared_props.desktop_settings.changed["show"].connect(on_show_changed);
		shared_props.desktop_settings.changed["show-active-mounts"].connect(on_show_active_mounts_changed);
		shared_props.desktop_settings.changed["show-home-folder"].connect(on_show_home_folder_changed);
		shared_props.desktop_settings.changed["show-trash-folder"].connect(on_show_trash_folder_changed);

		show_home = shared_props.desktop_settings.get_boolean("show-home-folder");
		show_mounts = shared_props.desktop_settings.get_boolean("show-active-mounts");
		show_trash = shared_props.desktop_settings.get_boolean("show-trash-folder");
		visible_setting = shared_props.desktop_settings.get_boolean("show");

		var css = new CssProvider();
		css.load_from_resource ("org/buddiesofbudgie/budgie-desktop-view/view.css");
		StyleContext.add_provider_for_screen(Screen.get_default(), css, STYLE_PROVIDER_PRIORITY_APPLICATION);

		if (!app_paintable) { // If the app isn't paintable, used in debugging
			get_style_context().add_class("debug");
		}

		// Window settings
		show_menubar = false;

		canvas = new DesktopCanvas(shared_props);
		canvas.get_style_context().add_class("canvas");
		canvas.halign = Align.FILL; // Fill the window, so the canvas allocation is the usable desktop area
		canvas.valign = Align.FILL;
		canvas.can_focus = false; // Keys go to the window, which handles them in on_key_pressed
		canvas.size_allocate.connect(on_canvas_allocated);
		canvas.scroll_event.connect(on_canvas_scroll);
		shared_props.desktop_settings.bind("snap-to-grid", canvas, "snap-to-grid", SettingsBindFlags.GET);

		arranger = new DesktopArranger(canvas, Path.build_filename(get_config_directory_path(), LAYOUT_FILE), shared_props.desktop_settings, shown_items);

		desktop_menu = new DesktopMenu(this, shared_props.desktop_settings); // Create our new desktop menu
		shared_props.file_menu = new FileMenu(shared_props); // Create our new file menu and set it in our shared props

		// Application actions, so the desktop menu and anything on D-Bus (e.g. gapplication action) share one path.
		// Both act on the selection, or on the whole desktop when nothing is selected.
		var align_action = new SimpleAction("align-to-grid", null);
		align_action.activate.connect(() => arranger.align_to_grid(canvas.get_selected()));
		app.add_action(align_action);

		var sort_action = new SimpleAction("sort-by", VariantType.STRING); // "name", "type" or "modified"
		sort_action.activate.connect((param) => {
			ItemSortKey? key = ItemSortKey.from_string(param.get_string());
			if (key == null) {
				warning("Unknown sort key: %s", param.get_string());
				return;
			}

			arranger.sort(canvas.get_selected(), key);
		});
		app.add_action(sort_action);

		// Item sources add and remove widgets; the arranger decides where they go
		desktop_folder = new DesktopFolder(shared_props);
		desktop_folder.item_added.connect((item) => canvas.put(item, 0, 0));
		desktop_folder.item_removed.connect((item) => canvas.remove(item));
		desktop_folder.changed.connect(arranger.relayout);
		desktop_folder.file_renamed.connect(arranger.file_renamed);
		desktop_folder.file_deleted.connect(arranger.file_deleted);

		mounts = new MountTracker(shared_props);
		mounts.mount_added.connect((item) => canvas.put(item, 0, 0));
		mounts.mount_removed.connect((item) => canvas.remove(item));
		mounts.changed.connect(arranger.relayout);

		drop_importer = new DropImporter(shared_props, desktop_folder);

		get_display_geo(); // Set our geo
		setup_launch_context(); // Needs default_screen from get_display_geo

		default_screen.monitors_changed.connect(on_resolution_change);

		add(canvas);

		shared_props.icon_theme = Gtk.IconTheme.get_default(); // Get the current icon theme
		shared_props.icon_theme.changed.connect(reload_icons); // Items look their icons up in the theme, so reload them all

		get_item_size(); // Get our initial icon size

		create_special_folders(); // Create our special folders
		mounts.load(); // Get all our active mounts
		desktop_folder.load(); // Get all our desktop files

		// The first layout pass happens once the compositor has sized us, in on_canvas_allocated
		arranger.import_legacy(Path.build_filename(get_config_directory_path(), LEGACY_POSITIONS_FILE));

		key_press_event.connect(on_key_pressed);
		button_release_event.connect(on_button_release); // Bind on_button_release to our button_release_event

		Gtk.TargetEntry[] targets = { { "application/x-icon-tasklist-launcher-id", 0, 0 }, { "text/uri-list", 0, 0 }, { "application/x-desktop", 0, 0 }};
		Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, targets, Gdk.DragAction.COPY);
		drag_data_received.connect(on_drag_data_received);

		set_window_transparent();

		if (visible_setting) {
			show(); // The compositor then sizes us, and on_canvas_allocated does the first layout pass
		}
	}

	public void clear_selection() {
		canvas.clear_selection();
		set_focus(null);
	}

	// create_special_folders will create our special Home and Trash folders
	private void create_special_folders() {
		home_item = FileItem.create_special(shared_props, "home"); // Create our special item for the Home directory

		if (home_item != null) { // Successfully created the home directory item
			canvas.put(home_item, 0, 0);
		}

		trash_item = FileItem.create_special(shared_props, "trash"); // Create our special item for the Trash directory

		if (trash_item != null) { // Successfully created the trash directory item
			canvas.put(trash_item, 0, 0);
		}
	}

	// shown_items returns the items the show settings allow. The arranger orders them and hides the rest.
	private GenericArray<DesktopItem> shown_items() {
		var shown = new GenericArray<DesktopItem>();
		if (!visible_setting) return shown; // Desktop icons are turned off entirely

		foreach (DesktopItem item in canvas.get_items()) {
			if (item == home_item && !show_home) continue;
			if (item == trash_item && !show_trash) continue;
			if (item.is_mount && !show_mounts) continue;
			shown.add(item);
		}

		return shown;
	}

	// get_display_geo refreshes the primary monitor, which the desktop menu is placed on.
	// Sizing isn't done here; the compositor sizes the layer surface and on_canvas_allocated follows it.
	private void get_display_geo() {
		default_screen = libxfce4windowing.Screen.get_default(); // Get our current default Screen
		primary_monitor = default_screen.get_primary_monitor();
	}

	// setup_launch_context creates the cursors and the launch context items use. The display never changes, so once is enough.
	private void setup_launch_context() {
		default_display = default_screen.gdk_screen.get_display(); // Get the display related to it
		shared_props.blocked_cursor = new Cursor.from_name(default_display, "not-allowed");
		shared_props.hand_cursor = new Cursor.for_display(default_display, CursorType.ARROW);
		shared_props.loading_cursor = new Cursor.from_name(default_display, "progress");

		shared_props.launch_context = default_display.get_app_launch_context(); // Get the app launch context for the default display
		shared_props.launch_context.set_screen(default_screen.gdk_screen); // Set the screen

		shared_props.launch_context.launch_started.connect(() => {
			shared_props.is_launching = true;
			shared_props.current_cursor = shared_props.loading_cursor;
		});

		shared_props.launch_context.launch_failed.connect(() => {
			shared_props.is_launching = false;
			shared_props.current_cursor = shared_props.hand_cursor;
		});

		shared_props.launch_context.launched.connect(() => {
			shared_props.is_launching = false;
			shared_props.current_cursor = shared_props.hand_cursor;
		});
	}

	// get_icon_size will get the current icon size from our settings and apply it to our private uint
	private void get_item_size() {
		item_size = (DesktopItemSize) shared_props.desktop_settings.get_enum("icon-size");

		if (item_size == DesktopItemSize.SMALL) { // Small Icons
			shared_props.icon_size = 32;
			max_allocated_item_width = 90;
		} else if (item_size == DesktopItemSize.NORMAL) { // Normal Icons
			shared_props.icon_size = 48;
			max_allocated_item_width = 90;
		} else if (item_size == DesktopItemSize.LARGE) { // Large icons
			shared_props.icon_size = 64;
			max_allocated_item_width = 150;
		} else if (item_size == DesktopItemSize.MASSIVE) { // Massive icons
			shared_props.icon_size = 96;
			max_allocated_item_width = 160;
		}

		max_allocated_item_width+=ITEM_MARGIN * 2;
		max_allocated_item_height = shared_props.icon_size + ITEM_MARGIN*7; // Icon size + our item margin*8 (to hopefully account for label height and the like)

		push_geometry(); // Cells follow the item size
	}

	// push_geometry gives the arranger the canvas size and cell size. One grid cell is one item, so it needs every
	// change to either.
	private void push_geometry() {
		if (canvas_width == 0 || max_allocated_item_width == null) return; // Not allocated or sized yet

		arranger.set_geometry(canvas_width, canvas_height, max_allocated_item_width, max_allocated_item_height);
	}

	// on_canvas_allocated follows the space the compositor gives us, e.g. when a panel is added, moved or resized
	private void on_canvas_allocated(Gtk.Allocation alloc) {
		if (alloc.width == canvas_width && alloc.height == canvas_height) return; // Placing items reallocates too

		canvas_width = alloc.width;
		canvas_height = alloc.height;

		// Relayout moves children, which queues another allocation; doing it from inside size_allocate would nest them
		Idle.add(() => {
			push_geometry();
			arranger.relayout();
			return false;
		});
	}

	// on_button_release handles the releasing of a mouse button on empty desktop space
	private bool on_button_release(EventButton event) {
		bool ctrl_down = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
		bool shift_down = (event.state & Gdk.ModifierType.SHIFT_MASK) != 0;

		if (event.button == 1 && (ctrl_down == false && shift_down == false )) { // Left click only
			desktop_menu.popdown(); // Hide the menu
			clear_selection(); // Clear any selection

			return Gdk.EVENT_PROPAGATE;
		} else if (event.button == 1 && (ctrl_down == true || shift_down == true)) {
			desktop_menu.popdown(); // Hide the menu

			return Gdk.EVENT_PROPAGATE;
		}
		else if (event.button == 3) { // Right click
			desktop_menu.place_on_monitor(primary_monitor.gdk_monitor); // Ensure menu is on primary monitor
			desktop_menu.set_screen(default_screen.gdk_screen); // Ensure menu is on our screen
			desktop_menu.popup_at_pointer(event); // Popup where our mouse is

			return Gdk.EVENT_STOP;
		} else {
			return Gdk.EVENT_PROPAGATE;
		}
	}

	// on_drag_data_received handles files dropped onto the desktop from other apps
	private void on_drag_data_received(Gtk.Widget widget, Gdk.DragContext c, int x, int y, Gtk.SelectionData d, uint info, uint time) {
		// x and y are relative to the drop target widget; convert to canvas space to find the drop cell
		int canvas_x, canvas_y;
		widget.translate_coordinates(canvas, x, y, out canvas_x, out canvas_y);
		GridPos drop_pos = canvas.grid_pos_at(canvas_x, canvas_y);

		GenericArray<File> targets = drop_importer.import((string) d.get_data());

		// Every file shares the drop point; the arranger spreads them out when the Desktop folder picks them up
		for (int i = 0; i < targets.length; i++) {
			arranger.expect_drop(targets[i], drop_pos);
		}
	}

	// on_canvas_scroll steps the icon size with Ctrl+scroll: up for bigger, down for smaller.
	// It only writes the icon-size setting, so the size persists and on_icon_size_changed does the resize.
	private bool on_canvas_scroll(EventScroll ev) {
		if ((ev.state & Gdk.ModifierType.CONTROL_MASK) == 0) return Gdk.EVENT_PROPAGATE;

		int step = 0;
		switch (ev.direction) {
			case ScrollDirection.UP:
				step = 1;
				break;
			case ScrollDirection.DOWN:
				step = -1;
				break;
			case ScrollDirection.SMOOTH:
				// A wheel notch is a delta of 1; touchpads send many small deltas, so add them up to one notch per step.
				// Positive delta_y is scrolling down.
				zoom_scroll += ev.delta_y;
				if (zoom_scroll <= -1) {
					step = 1;
					zoom_scroll = 0;
				} else if (zoom_scroll >= 1) {
					step = -1;
					zoom_scroll = 0;
				}
				break;
			default: // Horizontal scrolling doesn't zoom
				return Gdk.EVENT_STOP;
		}

		if (step == 0) return Gdk.EVENT_STOP;

		int current = shared_props.desktop_settings.get_enum("icon-size");
		int next = (current + step).clamp(DesktopItemSize.SMALL, DesktopItemSize.MASSIVE); // No wrap-around past either end

		if (next != current) {
			shared_props.desktop_settings.set_enum("icon-size", next);
		}

		return Gdk.EVENT_STOP;
	}

	// on_icon_size_changed handles changing the item-size (like from normal to large)
	private void on_icon_size_changed() {
		get_item_size(); // Get the latest item size value
		refresh_icon_sizes(); // Refresh our icon sizes
	}

	// on_key_pressed will handle when a key is pressed
	public bool on_key_pressed(EventKey key) {
		List<DesktopItem> selected = canvas.get_selected();
		bool ctrl_down = (key.state & Gdk.ModifierType.CONTROL_MASK) != 0;
		bool shift_down = (key.state & Gdk.ModifierType.SHIFT_MASK) != 0;

		switch (key.keyval) {
			case Gdk.Key.Left:
			case Gdk.Key.Right:
			case Gdk.Key.Up:
			case Gdk.Key.Down:
				canvas.navigate(key.keyval, shift_down);
				return Gdk.EVENT_STOP;
			case Gdk.Key.Return:
			case Gdk.Key.KP_Enter:
				if (selected.length() == 0) break;

				foreach (DesktopItem item in selected) {
					item.open();
				}

				clear_selection();
				break;
			case Gdk.Key.Delete:
				if (selected.length() == 0) break;

				foreach (DesktopItem item in selected) {
					if (item.is_special || item.is_mount) continue; // Don't move special items (e.g. Trash, Home, etc) or mounts to the trash
					((FileItem) item).move_to_trash();
				}

				clear_selection();
				break;
			case Gdk.Key.Escape:
				if (canvas.cancel_interaction()) return Gdk.EVENT_STOP; // First Escape cancels a drag, the next clears the selection
				clear_selection();
				break;
			case Gdk.Key.a:
				if (!ctrl_down) break;

				canvas.select_all();
				return Gdk.EVENT_STOP;
		}

		return Gdk.EVENT_PROPAGATE;
	}

	// on_resolution_change will handle signal events for when the resolution of our primary monitor has changed
	private void on_resolution_change() {
		Timeout.add(250, () => {
			get_display_geo(); // Update our display geo

			return false;
		});
	}

	// on_show_changed will handle signal events for when the show setting for our DesktopView has changed
	private void on_show_changed() {
		set_window_transparent();
		visible_setting = shared_props.desktop_settings.get_boolean("show"); // Set our visiblity based on if we should show the DesktopView or not

		arranger.relayout(); // Shows or hides the items

		if (visible_setting) {
			show();
		} else {
			hide();
		}
	}

	// on_show_active_mounts_changed will handle when our show-active-mounts setting changes
	public void on_show_active_mounts_changed() {
		show_mounts = shared_props.desktop_settings.get_boolean("show-active-mounts");
		arranger.relayout(); // Handles the visibility control
	}

	// on_show_home_folder_changed will handle when our show-home-folder setting changes
	public void on_show_home_folder_changed() {
		show_home = shared_props.desktop_settings.get_boolean("show-home-folder");
		arranger.relayout(); // Handles the visibility control
	}

	// on_show_trash_folder_changed will handle when our show-trash-folder setting changes
	public void on_show_trash_folder_changed() {
		show_trash = shared_props.desktop_settings.get_boolean("show-trash-folder");
		arranger.relayout(); // Handles the visibility control
	}

	// reload_icons re-fetches every item's icon from the current theme at the current size
	private void reload_icons() {
		foreach (DesktopItem item in canvas.get_items()) { // Includes hidden items, so they're current when shown again
			try {
				item.reload_icon();
			} catch (Error e) {
				warning("Failed to reload the icon for %s: %s", item.label_name, e.message);
			}
		}
	}

	// refresh_icon_sizes reloads icons after an icon or thumbnail size change, then relayouts since cells follow icon size
	public void refresh_icon_sizes() {
		reload_icons();
		arranger.relayout();
	}

	// set_window_transparent will attempt to set the window to the screen's rgba visual
	public void set_window_transparent() {
		var vis = this.screen.get_rgba_visual();

		if (vis == null) {
			warning("Compositing is not supported. Please file a bug.");
		} else {
			set_visual(vis);
		}
	}

	// get_config_directory_path returns the config directory path
	private string get_config_directory_path() {
		return Path.build_filename(Environment.get_user_config_dir(), POSITIONS_DIR);
	}
}
