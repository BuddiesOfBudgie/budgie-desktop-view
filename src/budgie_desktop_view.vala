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

[DBus (name="org.budgie_desktop.Raven")]
public interface Raven : GLib.Object {
	public abstract async void Dismiss() throws Error;
}

public const string RAVEN_DBUS_NAME = "org.budgie_desktop.Raven";
public const string RAVEN_DBUS_OBJECT_PATH = "/org/budgie_desktop/Raven";
public const int MARGIN = 20; // pixel spacing for left/right

// Drag and drop constants
public const string POSITIONS_DIR = ".config/budgie-desktop-view";
public const string POSITIONS_FILE = "icon-positions.conf";
public const double DRAG_OPACITY = 0.5;

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

// Drag and drop state
HashTable<string, int>? custom_positions; // Maps item identifiers to custom positions
List<DesktopItem>? drag_source_items = null; // All items being dragged
DesktopItem? drag_primary_item = null; // The item where drag started
int drag_insert_index = -1;
bool using_custom_positions = false;

public class DesktopView : Gtk.ApplicationWindow {
	libxfce4windowing.Screen default_screen;
	Gdk.Display default_display;
	libxfce4windowing.Monitor? primary_monitor;
	Rectangle? primary_monitor_geo = null;
	UnifiedProps shared_props;
	Raven? raven = null;

	DesktopItemSize? item_size; // Default our Item Size to NORMAL
	int? max_allocated_item_height;
	int? max_allocated_item_width;
	bool show_home;
	bool show_mounts;
	bool show_trash;
	bool visible_setting;

	DesktopMenu desktop_menu;
	FlowBox flow;

	File? desktop_file;
	string? desktop_file_uri;
	FileMonitor? desktop_monitor;
	VolumeMonitor? volume_monitor;

	FileItem? home_item = null;
	FileItem? trash_item = null;

	HashTable<string, MountItem?>? mount_items; // All active mounts in our flowbox
	HashTable<string, FileItem?>? file_items; // All file-related items in our flowbox
	CompareFunc<FileItem>? file_cmp;

	GLib.Settings? desktop_settings = null;

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
		GtkLayerShell.set_layer(this, GtkLayerShell.Layer.BACKGROUND);
		GtkLayerShell.set_anchor(
			this,
			GtkLayerShell.Edge.TOP | GtkLayerShell.Edge.LEFT,
			true
		);
		GtkLayerShell.set_keyboard_mode(this, GtkLayerShell.KeyboardMode.ON_DEMAND);
		GtkLayerShell.try_force_commit(this);

		shared_props = new UnifiedProps(); // Create shared props
		shared_props.cursor_changed.connect((cursor) => {
			get_window().set_cursor(cursor);
		});
		shared_props.thumbnail_size_changed.connect(refresh_icon_sizes); // When our thumbnail size changed, refresh our icons

		Gtk.Settings? default_settings = Gtk.Settings.get_default(); // Get the default settings
		default_settings.gtk_application_prefer_dark_theme = true;

		file_items = new HashTable<string, FileItem>(str_hash, str_equal);
		mount_items =  new HashTable<string, MountItem>(str_hash, str_equal);

		shared_props.desktop_settings = new GLib.Settings("org.buddiesofbudgie.budgie-desktop-view"); // Get our desktop-view settings

		if (shared_props.desktop_settings == null) {
			warning("Required gschema not installed.");
			close(); // Close the window
		}

		create_fileitem_sorter();

		shared_props.desktop_settings.changed["icon-size"].connect(on_icon_size_changed);
		shared_props.desktop_settings.changed["show"].connect(on_show_changed);
		shared_props.desktop_settings.changed["show-active-mounts"].connect(on_show_active_mounts_changed);
		shared_props.desktop_settings.changed["show-home-folder"].connect(on_show_home_folder_changed);
		shared_props.desktop_settings.changed["show-trash-folder"].connect(on_show_trash_folder_changed);

		update_auto_arrange_menu(); // Update menu state based on loaded positions

		show_home = shared_props.desktop_settings.get_boolean("show-home-folder");
		show_mounts = shared_props.desktop_settings.get_boolean("show-active-mounts");
		show_trash = shared_props.desktop_settings.get_boolean("show-trash-folder");

		visible_setting = shared_props.desktop_settings.get_boolean("show");
		desktop_file_uri = Environment.get_user_special_dir(UserDirectory.DESKTOP);
		desktop_file = File.new_for_path(desktop_file_uri); // Get the Desktop folder "file"

		try {
			desktop_monitor = desktop_file.monitor(FileMonitorFlags.WATCH_MOVES, null); // Create our file monitor
			desktop_monitor.changed.connect(on_file_changed); // Bind to our file changed event
		} catch (Error e) {
			warning("Failed to obtain a monitor for file changes to the Desktop folder. Will not be able to watch for changes: %s", e.message);
		}

		volume_monitor = VolumeMonitor.get(); // Get our volume monitor
		volume_monitor.mount_added.connect(on_mount_added);

		var css = new CssProvider();
		css.load_from_resource ("org/buddiesofbudgie/budgie-desktop-view/view.css");
		StyleContext.add_provider_for_screen(Screen.get_default(), css, STYLE_PROVIDER_PRIORITY_APPLICATION);

		if (!app_paintable) { // If the app isn't paintable, used in debugging
			get_style_context().add_class("debug");
		}

		// Window settings
		show_menubar = false;

		desktop_menu = new DesktopMenu(this); // Create our new desktop menu
		desktop_menu.toggle_auto_arrange.connect(on_toggle_auto_arrange);
		shared_props.file_menu = new FileMenu(shared_props); // Create our new file menu and set it in our shared props

		load_custom_positions(); // Load saved icon positions (after menu is created)
		update_auto_arrange_menu(); // Update menu state based on loaded positions

		flow = new FlowBox();
		flow.get_style_context().add_class("flow");
		flow.halign = Align.START; // Start at the beginning
		flow.expand = false;
		flow.set_selection_mode(Gtk.SelectionMode.MULTIPLE); // Enable multi-selection
		flow.set_orientation(Gtk.Orientation.VERTICAL);
		flow.set_sort_func(sorter); // Set our sorting function
		flow.valign = Align.START; // Don't let it fill
		flow.margin_start = MARGIN;
		flow.margin_end = MARGIN;

		get_display_geo(); // Set our geo

		default_screen.monitors_changed.connect(on_resolution_change);

		add(flow);

		shared_props.icon_theme = Gtk.IconTheme.get_default(); // Get the current icon theme
		shared_props.icon_theme.changed.connect(on_icon_theme_changed); // Trigger on_icon_theme_changed when changed signal emitted

		get_item_size(); // Get our initial icon size

		this.create_special_folders(); // Create our special folders
		this.get_all_active_mounts(); // Get all our active mounts
		this.get_all_desktop_files(); // Get all our desktop files

		flow.invalidate_sort(); // Invalidate our sort all at once since we mass added items
		this.enforce_content_limit(); // Immediately flowbox content resizing

		flow.can_focus = false;
		key_press_event.connect(on_key_pressed);
		button_release_event.connect(on_button_release); // Bind on_button_release to our button_release_event

		// Enable drag and drop for icon repositioning
		setup_flowbox_drag_dest();

		Gtk.TargetEntry[] targets = { { "application/x-icon-tasklist-launcher-id", 0, 0 }, { "text/uri-list", 0, 0 }, { "application/x-desktop", 0, 0 }};
		Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, targets, Gdk.DragAction.COPY);
		drag_data_received.connect(on_drag_data_received);

		set_window_transparent();

		if (visible_setting) {
			show();
			get_display_geo();
		}

		desktop_settings = new GLib.Settings("org.gnome.desktop.background");
		desktop_settings.changed.connect((key) => {
			if (key == "picture-uri") {
				/* the background picture has changed.  We need to refresh
				   the icons - we do this by hiding everything, allow the
				   wallpaper to show and then redisplaying.
				*/
				hide();
				GLib.Timeout.add(200, () => {
					on_show_changed();
					return false;
				});
			}
		});

		Bus.watch_name(BusType.SESSION, RAVEN_DBUS_NAME, BusNameWatcherFlags.NONE, has_raven, on_raven_lost);
	}

	// clear_selection will clear the selection and focus of all flowbox children that are selected
	public void clear_selection() {
		flow.unselect_all();
		set_focus(null);
	}

	// create_file_item will create our FileItem and add it if necessary
	public void create_file_item(File f, FileInfo info, bool skip_resort) {
		if (info.get_is_hidden()) { // This is a hidden file
			return; // Don't do anything
		}

		string created_file_name = info.get_display_name(); // Get the name of the file

		if (file_items.contains(created_file_name)) { // Already have this
			return;
		}

		FileType created_file_type = info.get_file_type(); // Get the type of the file

		bool supported_type = ((created_file_type == FileType.DIRECTORY) || (created_file_type == FileType.REGULAR));

		if (supported_type) { // If this is a supported type
			FileItem item = new FileItem(shared_props, f, info, null); // Create our new Item
			if (item.exclude_item) { // Shouldn't actually include this item
				return;
			}

			file_items.set(created_file_name, item); // Add our item with our file name and the prepended type
			flow.add(item); //  Add our FileItem

			// Setup drag source for this item
			setup_item_drag_source(item);
			setup_item_drag_dest(item);

			if (visible_setting) { // Showing icons currently
				item.request_show();
			}

			if (!skip_resort) {
				flow.invalidate_sort(); // Invalidate sort to force re-sorting
			}
		}
	}

	// create_mount_item will create our MountItem and add it if necessary
	public void create_mount_item(Mount mount, string uuid, bool skip_resort) {
		if (mount_items.contains(uuid)) { // Already have a mount with this UUID
			return;
		}

		MountItem mount_item = new MountItem(shared_props, mount, uuid); // Create a new Mount Item
		mount_item.drive_disconnected.connect(on_mount_removed); // When we report our mount's related drive disconnected, call on_mount_removed
		mount_item.mount_name_changed.connect(() => { // When the name changes
			flow.invalidate_sort(); // Invalidate sort to force re-sorting
		});

		mount_items.set(uuid, mount_item);
		flow.add(mount_item); // Add the Mount Item

		// Setup drag source for this item
		setup_item_drag_source(mount_item);
		setup_item_drag_dest(mount_item);

		if (visible_setting && show_mounts) { // Showing icons currently and should show mounts
			mount_item.request_show(); // Request showing this item
		}

		if (!skip_resort) {
			flow.invalidate_sort(); // Invalidate sort to force re-sorting
		}
	}

	// create_special_folders will create our special Home and Trash folders
	public void create_special_folders() {
		home_item = create_special_file_item("home"); // Create our special item for the Home directory

		if (home_item != null) { // Successfully created the home directory item
			flow.add(home_item); // Add the home item
		}

		trash_item = create_special_file_item("trash"); // Create our special item for the Trash directory

		if (trash_item != null) { // Successfully created the trash directory item
			flow.add(trash_item);
		}

		// Setup drag sources for special items
		if (home_item != null) setup_item_drag_source(home_item);
		if (trash_item != null) setup_item_drag_source(trash_item);
	}

	// create_special_file_item will create a FileItem for a special directory like Home
	public FileItem? create_special_file_item(string item_type) {
		string path = Environment.get_home_dir(); // Default to the home directory

		if (item_type == "trash") {
			path = Path.build_path(Path.DIR_SEPARATOR_S, path, ".local", "share", "Trash", "files"); // Build a path to the trash files
		} else if (item_type != "home") { // Not home or trash
			return null;
		}

		File special_file = File.new_for_path(path);

		if (item_type == "trash") { // Might not exist, better be safe than sorry
			if (!special_file.query_exists(null)) { // If the trash files directory doesn't exist
				warning("Trash folder does not exist. Creating the necessary directories.");

				try {
					special_file.make_directory_with_parents(); // Attempt to make the directory
				} catch (Error e) {
					warning("Failed to create %s: %s", path, e.message);
					return null;
				}
			}
		}

		var c = new Cancellable(); // Create a new cancellable stack
		FileInfo? special_file_info = null;

		try {
			special_file_info = special_file.query_info("standard::*", FileQueryInfoFlags.NONE, c);
		} catch (Error e) {
			warning("Failed to get requested information on this directory: %s", e.message);
			return null;
		}

		if (c.is_cancelled() || (special_file_info == null)) { // Cancelled or failed to get info
			warning("Failed to get information on this directory.");
			return null;
		}

		ThemedIcon special_icon = new ThemedIcon("user-"+item_type); // Get the user-home or user-trash icon for this
		FileItem special_item = new FileItem(shared_props, special_file, special_file_info, special_icon);
		special_item.is_special = true; // Say that it is special.
		special_item.file_type = item_type; // Override file_type

		if (item_type == "trash") {
			special_item.label_name = _("Trash");
		}

		return special_item;
	}

	// delete_item will delete any references to a file and its FileItem
	public void delete_item(File f) {
		string deleted_file_name = f.get_basename(); // Get the basename of this

		try {
			FileInfo delete_file_info = f.query_info("standard::*", 0);
			deleted_file_name = delete_file_info.get_display_name();
		} catch (Error e) {}

		FileItem? file_item = file_items.get(deleted_file_name); // Get our potential FileItem

		if (file_item != null) { // FileItem exists
			flow.remove(file_item); // Remove from the flowbox
			file_items.remove(deleted_file_name); // Remove from items
		}
	}

	// dismiss_raven will request to dismiss Raven
	public void dismiss_raven() {
		if (raven != null) { // If we got Raven's DBus Proxy
			raven.Dismiss.begin();
		}
	}

	// enforce_content_limit will enforce a maximum amount of items to be shown based on maximum DesktopItem size and width of the primary monitor
	private void enforce_content_limit() {
		List<weak Widget> flow_children = flow.get_children(); // Get the children

		if (flow_children.length() == 0) { // If there is children in the flowbox
			return;
		}

		if (!visible_setting) { // Items should not be visible
			flow_children.foreach((item) => {
				item.hide();
			});

			return;
		}

		int height = primary_monitor_geo.height;
		int width = primary_monitor_geo.width;

		int row_count = (int) (height / max_allocated_item_height); // Divide our monitor height by our DesktopItem height
		int column_count = (int) (width / max_allocated_item_width - 1); // Divide our monitor width by our DesktopItem width

		int max_files_allowed = row_count * column_count; // Multiply our row count by our column count to get the total amount of items we're willing to show

		if (row_count != 1) { // Not valid yet
			flow.set_max_children_per_line((uint) row_count);
		}

		List<weak MountItem> mount_vals = mount_items.get_values(); // Get our Mount Items as a list
		List<weak FileItem> file_vals = file_items.get_values(); // Get our File Items as a list
		file_vals.reverse(); // HashTable does a weird thing where it adds the items in reverse order
		file_vals.sort(file_cmp);

		if (show_mounts) { // Show mounts
			max_files_allowed -= (int) mount_vals.length(); // Reduce our max item count by our mount_vals length
		}

		if (show_home) { // Showing our home dir
			max_files_allowed--;
			home_item.request_show(); // Show the home item
		} else {
			home_item.hide(); // Hide the item
		}

		if (trash_item != null) { // Trash Item exists
			if (show_trash) { // Showing our trash
				max_files_allowed--;
				trash_item.request_show(); // Show the trash item
			} else {
				trash_item.hide(); // Hide the item
			}
		}

		uint file_vals_len = file_vals.length();
		uint show_count = 0;

		for (var i = 0; i < mount_vals.length(); i++) { // For each mount
			MountItem item = mount_vals.nth_data(i);

			if (show_mounts) {
				item.request_show(); // Show the item
			} else {
				item.hide();
			}
		}

		for (var i = 0; i < max_files_allowed; i++) { // Iterate over our max count of files allowed
			FileItem? item = file_vals.nth_data(i);
			if (item == null) { // Don't have this many files
				break;
			}

			item.request_show(); // Show the item
			show_count++;
		}

		if (file_vals_len > max_files_allowed) { // Have more files than allowed
			for (var i = max_files_allowed; i < file_vals_len; i++) {
				FileItem? item = file_vals.nth_data(i);
				if (item == null) { // Don't have this many files
					break;
				}

				item.hide(); // Hide the item
			}
		}
	}

	// get_all_active_mounts will get all the mounts of active volumes / drives
	public void get_all_active_mounts() {
		List<Drive> connected_drives = volume_monitor.get_connected_drives(); // Get all connected drives

		connected_drives.foreach((drive) => { // For each of the drives
			if (!drive.has_volumes()) { // If the drive has no volumes
				return;
			}

			List<Volume> drive_volumes = drive.get_volumes(); // Get all volumes
			drive_volumes.foreach((volume) => { // For each volume on this drive
				Mount? volume_mount = volume.get_mount();

				if (volume_mount == null) { // Has no Mount
					return;
				}

				string mount_uuid = this.get_mount_uuid(volume_mount); // Get the UUID for this mount

				if (mount_uuid == "FAILED_TO_GET_UUID") { // Failed to get the mount
					return;
				}

				File? mount_file = volume_mount.get_default_location(); // Get the File for the default location of this mount

				if (mount_file == null) { // Has no location
					return;
				}

				create_mount_item(volume_mount, mount_uuid, true); // Create the mount
			});
		});
	}


	// get_all_desktop_files will get all the files in our Desktop folder and generate items for them
	private void get_all_desktop_files() {
		var c = new Cancellable(); // Create a new cancellable stack
		FileEnumerator? desktop_file_enumerator = null;

		try {
			desktop_file_enumerator = desktop_file.enumerate_children("standard::*,standard::display-name", FileQueryInfoFlags.NONE, c);
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
					create_file_item(f, file_info, true); // Create our item
				}
			}
		} catch (Error e) {
			warning("Failed to iterate on files in Desktop folder: %s", e.message);
		}

		if (c.is_cancelled()) { // If our cancellable was cancelled
			warning("Desktop reading was cancelled");
		}
	}

	// get_display_geo will get or update our primary monitor workarea
	private void get_display_geo() {
		default_screen = libxfce4windowing.Screen.get_default(); // Get our current default Screen
		primary_monitor = default_screen.get_primary_monitor();

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

		primary_monitor_geo = primary_monitor.get_workarea(); // Get the working area of this monitor
		shared_props.s_factor = primary_monitor.get_scale(); // Get the current scaling factor
		update_window_sizing();
	}

	// get_mount_uuid will get a mount UUID and return it
	public string get_mount_uuid(Mount mount) {
		Volume? volume = mount.get_volume(); // Get the volume associated with this Mount

		if (volume == null) { // Failed to get the volume
			return ""; // Return an empty string
		}

		string? mount_uuid = mount.get_uuid(); // Get any mount UUID

		if (mount_uuid != null) { // Got the UUID for the mount
			return mount_uuid;
		}

		string? volume_uuid = volume.get_uuid(); // Get the volume UUID

		if (volume_uuid != null) { // Got the UUID for the volume
			return volume_uuid;
		}

		Drive? drive = mount.get_drive();

		if (drive != null) { // Got the drive
			string? drive_identifier = drive.get_identifier(DRIVE_IDENTIFIER_KIND_UNIX_DEVICE);

			if (drive_identifier != null) {
				return drive_identifier;
			}
		}

		return "FAILED_TO_GET_UUID";
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
	}

	// has_raven handles our request to begin getting Raven if we don't have it already
	private void has_raven() {
		if (raven == null) {
			Bus.get_proxy.begin<Raven>(BusType.SESSION, RAVEN_DBUS_NAME, RAVEN_DBUS_OBJECT_PATH, 0, null, on_raven_get);
		}
	}

	// on_button_release handles the releasing of a mouse button
	private bool on_button_release(EventButton event) {
		bool ctrl_down = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
		bool shift_down = (event.state & Gdk.ModifierType.SHIFT_MASK) != 0;

		if (event.button == 1 && (ctrl_down == false && shift_down == false )) { // Left click only
			desktop_menu.popdown(); // Hide the menu
			clear_selection(); // Clear any selection
			dismiss_raven(); // Dismiss raven

			return Gdk.EVENT_PROPAGATE;
		} else if (event.button == 1 && (ctrl_down == true || shift_down == true)) {
			desktop_menu.popdown(); // Hide the menu
			dismiss_raven(); // Dismiss raven

			return Gdk.EVENT_PROPAGATE;
		}
		else if (event.button == 3) { // Right click
			dismiss_raven(); // Dismiss raven

			desktop_menu.place_on_monitor(primary_monitor.gdk_monitor); // Ensure menu is on primary monitor
			desktop_menu.set_screen(default_screen.gdk_screen); // Ensure menu is on our screen
			desktop_menu.popup_at_pointer(event); // Popup where our mouse is

			return Gdk.EVENT_STOP;
		} else {
			return Gdk.EVENT_PROPAGATE;
		}
	}

	// on_drag_data_received handles our drag_data_received
	private void on_drag_data_received(Gtk.Widget widget, Gdk.DragContext c, int x, int y, Gtk.SelectionData d, uint info, uint time) {
		debug("on_drag_data_received - processing URIs.\n");
		string uri = (string) d.get_data(); // Get our data as a string
		string[] uris = uri.chomp().split("\n"); // Split on newlines in case we pass multiple items

		foreach (string file_uri in uris) { // For each file URI
			file_uri = file_uri.chomp();

			File this_file = File.new_for_uri(file_uri); // Load this file
			string file_base = this_file.get_basename();
			string file_dir = file_uri.replace(file_base, ""); // Get the directory
			file_dir = file_dir.replace("file://", "");

			if (file_base == desktop_file_uri) { // Copying from the Desktop to Desktop
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
			string copy_file_name = proposed_file_name;

			if (file_items.contains(file_base)) { // Already have a file called this
				bool have_file_as_copy = true;

				while (have_file_as_copy) {
					string primitive_name = copy_file_name;
					string ext = "";

					if (primitive_name.contains(".")) { // Has a . so maybe an extension
						int last_dot_pos = primitive_name.last_index_of("."); // Get the last .
						primitive_name = copy_file_name.substring(0, last_dot_pos);
						warning("Super primitive Name: %s", primitive_name);
						ext = copy_file_name.substring(last_dot_pos);
						warning("Extension: %s", ext);
					}

					primitive_name += " (Copy)"+ext; // Add (Copy)

					File? copy_file = File.new_for_path(Path.build_filename(desktop_file_uri, primitive_name)); // Create a file for this primitive copy

					if (!copy_file.query_exists()) { // File does not exist
						proposed_file_name = primitive_name;
						have_file_as_copy = false;
						break;
					} else {
						copy_file_name = primitive_name;
					}
				}
			}

			FileType type = finfo.get_file_type();

			string target_path = Path.build_filename(desktop_file_uri, proposed_file_name);
			File target_file = File.new_for_path(target_path); // "Create" our target file

			if (type == FileType.DIRECTORY) { // If the file is a directory
				try {
					target_file.make_symbolic_link(this_file.get_path());
				} catch (Error e) {
					warning("Failed to symlink to %s: %s", target_path, e.message);
				}
			} else { // Is a file
				Cancellable file_cancellable = new Cancellable(); // Create a new cancellable so we can cancel the file
				shared_props.files_currently_copying.set(proposed_file_name, file_cancellable); // Add the originating file

				this_file.copy_async.begin(target_file, FileCopyFlags.NOFOLLOW_SYMLINKS, 0, file_cancellable, null, (obj, res) => {
					shared_props.files_currently_copying.remove(proposed_file_name); // Remove the file we were copying from our list
					update_item_saturation(proposed_file_name); // Update our item saturation

					try {
						this_file.copy_async.end(res);
					} catch (Error e) {
						if (!file_cancellable.is_cancelled()) { // Did not fail due to a cancelled copy
							warning("Failed to copy %s: %s", proposed_file_name, e.message);
							delete_item(target_file); // Delete the item
						}
					}
				});
			}
		}

		Gtk.drag_finish(c, true, true, time);
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
		} else if ((type == FileMonitorEvent.MOVED_IN) || (type == FileMonitorEvent.CREATED)) { // File was created in or moved to our Desktop folder
			do_create = true;
			create_file_ref = file;
		} else if ((type == FileMonitorEvent.MOVED_OUT) || (type == FileMonitorEvent.DELETED)) {  // File was deleted or moved out of our Desktop folder
			do_delete = true;
			delete_file_ref = file;
		}

		if ((do_delete) && (delete_file_ref != null)) { // Handle deletions first
			delete_item(delete_file_ref); // Only pass the file reference since we won't be able to get file info
			enforce_content_limit();
		}

		if ((do_create) && (create_file_ref != null)) { // Do creations after any potential deletions
			if (create_file_ref.get_basename().has_prefix(".")) { // Hidden file
				return;
			}

			Timeout.add(100, () => { // Gives just enough time usually for the file to finish syncing and start reporting a correct mimetype
				try {
					FileInfo created_file_info = create_file_ref.query_info("standard::*", 0);
					string file_name = created_file_info.get_display_name();

					if (file_items.contains(file_name) || // Already have this
						created_file_info.get_is_hidden() // Is hidden
					) {
						return false;
					}

					create_file_item(create_file_ref, created_file_info, false); // Create our item
					update_item_saturation(file_name);
					enforce_content_limit();
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
			if (file.get_basename().has_prefix(".")) { // Hidden file, we can know this without querying the info
				return; // Ignore since we do elsewhere
			}

			Timeout.add(50, () => { // Delay for sync if necessary
				try {
					FileInfo existing_file_info = file.query_info("standard::*", 0); // Get the file's info
					string file_name = existing_file_info.get_display_name(); // Get the name of the file

					if (file_items.contains(file_name)) { // If we have this item
						FileItem file_item = file_items.get(file_name); // Get the file item
						file_item.info = existing_file_info; // Update the file info
						file_item.set_icon(file_item.get_mimetype_icon()); // Update the icon
					}
				} catch (Error e) {
					warning("Failed to get updated attributes for file. %s", e.message);
				}

				return false;
			});
		}
	}

	// on_icon_theme_changed handles changes to the icon theme
	private void on_icon_theme_changed() {
		try {
			home_item.update_icon(); // Update the home icon
		} catch (Error e) {
			warning("Failed to update the icon for the Home item: %s", e.message);
		}

		if (trash_item != null) {
			try {
				trash_item.update_icon(); // Update the trash icon
			} catch (Error e) {
				warning("Failed to update the icon for the Trash item: %s", e.message);
			}
		}

		mount_items.foreach((key, mount_item) => { // For each mount
			try {
				mount_item.set_icon(mount_item.icon); // Re-call our set_icon to re-fetch from current icon theme
			} catch (Error e) {
				warning("Failed to set icon factors for a MountItem when refreshing icon sizes: %s", e.message);
			}
		});

		file_items.foreach((key, file_item) => { // For each file (special or otherwise)
			try {
				file_item.update_icon(); // Re-call our update_icon to re-fetch from current icon theme
			} catch (Error e) {
				warning("Failed to set icon factors for a FileItem when refreshing icon sizes: %s", e.message);
			}
		});
	}

	// on_icon_size_changed handles changing the item-size (like from normal to large)
	private void on_icon_size_changed() {
		get_item_size(); // Get the latest item size value
		refresh_icon_sizes(); // Refresh our icon sizes
	}

	// on_key_pressed will handle when a key is pressed
	public bool on_key_pressed(EventKey key) {
		List<weak FlowBoxChild> selected_children = flow.get_selected_children(); // Get our selected children
		bool have_selected_children = (selected_children.length() != 0);

		bool is_arrow_key = key.keyval >= 65361 && key.keyval <= 65364; // Left arrow starts at 65361, down at 65364
		bool is_enter_key = key.keyval == 65293;
		bool is_delete_key = key.keyval == 65535;
		bool is_esc_key = key.keyval == 65307;

		if (is_arrow_key && !have_selected_children) { // No child selected and not the escape key
			foreach (Gtk.Widget item in flow.get_children()) {
				if (item.is_visible()) {
					flow.select_child((Gtk.FlowBoxChild) item);
					set_focus((Gtk.FlowBoxChild) item);
					break;
				}
			}

			return Gdk.EVENT_STOP;
		} else if ((is_delete_key || is_enter_key) && have_selected_children) { // Pressed the delete or enter key while having a child selected
			DesktopItem generic_item = (DesktopItem) selected_children.nth_data(0); // Get the child as a DesktopItem

			if (is_delete_key) { // Pressed the delete key
				if (generic_item.is_special || generic_item.is_mount) { // Don't move special items (e.g. Trash, Home, etc) or mounts to the trash
					return Gdk.EVENT_STOP;
				}

				FileItem item_as_file = (FileItem) generic_item; // Cast as a FileItem
				item_as_file.move_to_trash(); // Move the item to trash
			} else { // Pressed enter key
				if (generic_item.is_mount) { // If this is a mount
					MountItem item_as_mount = (MountItem) generic_item; // Cast as a MountItem
					item_as_mount.launch(); // Launch the item
				} else { // This is a file, directory, or launcher
					FileItem item_as_file = (FileItem) generic_item; // Cast as a FileItem
					item_as_file.launch(false); // Launch item normally
				}
			}

			clear_selection(); // Clear the selection
		} else if (is_esc_key) { // Escaping
			clear_selection(); // Clear the selection
		}

		return Gdk.EVENT_PROPAGATE;
	}

	// on_mount_added will handle signal events for when we add a mount
	public void on_mount_added(Mount mount) {
		string mount_uuid = this.get_mount_uuid(mount); // Get the UUID for this mount

		if (mount_uuid == "FAILED_TO_GET_UUID") { // Failed to get the mount
			return;
		}

		if (mount_items.contains(mount_uuid)) { // Already have this
			return;
		}

		create_mount_item(mount, mount_uuid, false); // Create a new Mount item with this UUID and ensure we resort
		enforce_content_limit();
	}

	// on_mount_removed will handle signal events for when a MountItem reports a disconnect
	public void on_mount_removed(MountItem mount_item) {
		flow.remove(mount_item); // Remove the mount item from the flow box
		mount_items.remove(mount_item.uuid); // Remove the item from mount_items
		enforce_content_limit();
	}

	// on_raven_get handles when our get_proxy request to get Raven completed
	private void on_raven_get(Object? obj, AsyncResult? res) {
		try {
			raven = Bus.get_proxy.end(res);
		} catch (Error e) {
			warning("Failed to gain Raven: %s", e.message);
		}
	}

	// on_raven_lost handles when we just the proxy for Raven
	private void on_raven_lost() {
		raven = null; // Reset back to null
	}

	// on_resolution_change will handle signal events for when the resolution of our primary monitor has changed
	private void on_resolution_change() {
		Timeout.add(250, () => {
			get_display_geo(); // Update our display geo
			get_item_size(); // Update desired item spacing
			enforce_content_limit();

			return false;
		});
	}

	// on_show_changed will handle signal events for when the show setting for our DesktopView has changed
	private void on_show_changed() {
		set_window_transparent();
		visible_setting = shared_props.desktop_settings.get_boolean("show"); // Set our visiblity based on if we should show the DesktopView or not

		enforce_content_limit();

		if (visible_setting) {
			show();
			update_window_sizing();
		} else {
			hide();
		}
	}

	// on_show_active_mounts_changed will handle when our show-active-mounts setting changes
	public void on_show_active_mounts_changed() {
		show_mounts = shared_props.desktop_settings.get_boolean("show-active-mounts");
		enforce_content_limit(); // Just call enforce_content_limit again which will handle the visibility control
	}

	// on_show_home_folder_changed will handle when our show-home-folder setting changes
	public void on_show_home_folder_changed() {
		show_home = shared_props.desktop_settings.get_boolean("show-home-folder");
		enforce_content_limit(); // Just call enforce_content_limit again which will handle the visibility control
	}

	// on_show_trash_folder_changed will handle when our show-trash-folder setting changes
	public void on_show_trash_folder_changed() {
		show_trash = shared_props.desktop_settings.get_boolean("show-trash-folder");
		enforce_content_limit(); // Just call enforce_content_limit again which will handle the visibility control
	}

	public void refresh_icon_sizes() {
		try {
			home_item.update_icon(); // Update the home icon
		} catch (Error e) {
			warning("Failed to update the icon for the Home item: %s", e.message);
		}

		if (trash_item != null) {
			try {
				trash_item.update_icon(); // Update the trash icon
			} catch (Error e) {
				warning("Failed to update the icon for the Trash item: %s", e.message);
			}
		}

		mount_items.foreach((key, mount_item) => { // For each mount
			try {
				mount_item.set_icon_factors();
			} catch (Error e) {
				warning("Failed to set icon factors for a MountItem when refreshing icon sizes: %s", e.message);
			}
		});

		file_items.foreach((key, file_item) => { // For each file (special or otherwise)
			try {
				file_item.update_icon(); // Call update_icon instead of set_icon_factors so we can reload any appinfo icons and pixbufs too
			} catch (Error e) {
				warning("Failed to set icon factors for a FileItem when refreshing icon sizes: %s", e.message);
			}
		});

		enforce_content_limit(); // Update our flowbox content limit based on icon / item sizing
	}

	// create_fileitem_sorter will create our fileitem sorter
	// Folders should go before files, with the values of each being collated
	private void create_fileitem_sorter() {
		file_cmp = (c1, c2) => {
			bool c1_is_dir = (c1.item_type == "dir"); // Determine if child_one is a directory
			bool c2_is_dir = (c2.item_type == "dir"); // Determine if child_two is a directory

			if (c1_is_dir && !c2_is_dir) { // Child one is a directory, two is a normal file
				return -1; // Directories come before folders
			} else if (!c1_is_dir && c2_is_dir) { // child_two is a directory
				return 1;
			}

			string c1_ck = c1.label_name.collate_key_for_filename();
			string c2_ck = c2.label_name.collate_key_for_filename();

			return strcmp(c1_ck, c2_ck); // Return the value from collate if both are directories or both are files
		};
	}

	// update_item_saturation will update the saturation of a FileItem based on if it is being copied
	private void update_item_saturation(string item_name) {
		FileItem file_item = file_items.get(item_name); // Get the file item

		if (file_item == null) { // Item doesn't exist
			return;
		}

		file_item.is_copying = shared_props.is_copying(item_name);
	}

	// sorter handles our FlowBox sorting
	// this will use the filename collation keys instead of the direct names as it handles ints, -, and . in a predictable manner
	// e.g. cc.svg should be before cc-amex.svg as well as handle locales
	// This also has the by-product of being faster. So yay.
	private int sorter(FlowBoxChild child_one, FlowBoxChild child_two) {
		// If using custom positions, sort by those first
		if (using_custom_positions) {
			DesktopItem item1 = (DesktopItem) child_one;
			DesktopItem item2 = (DesktopItem) child_two;

			int pos1 = get_item_custom_position(item1);
			int pos2 = get_item_custom_position(item2);

			if (pos1 != -1 && pos2 != -1) {
				return pos1 - pos2;
			}
		}

		DesktopItem c1 = (DesktopItem) child_one;
		DesktopItem c2 = (DesktopItem) child_two;

		if (c1.is_special && !c2.is_special) { // First is special
			return -1;
		} else if (!c1.is_special && c2.is_special) { // Second is special
			return 1;
		} else if (c1.is_special && c2.is_special) { // Both are special
			string c1_ck = c1.name.collate_key_for_filename(c1.name.length);
			string c2_ck = c2.name.collate_key_for_filename(c2.name.length);
			return strcmp(c1_ck, c2_ck);
		}

		bool c1_is_mount = (c1.item_type == "mount");
		bool c2_is_mount = (c2.item_type == "mount");

		if (c1_is_mount && !c2_is_mount) { // First is a mount
			return -1;
		} else if (!c1_is_mount && c2_is_mount) { // Second is a mount
			return 1;
		} else if (c1_is_mount && c2_is_mount) { // Both are mounts
			string c1_ck = c1.label_name.collate_key_for_filename(c1.label_name.length);
			string c2_ck = c2.label_name.collate_key_for_filename(c2.label_name.length);
			return strcmp(c1_ck, c2_ck);
		}

		return file_cmp((FileItem) child_one, (FileItem) child_two); // At this point, compare the dir / file names
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

	private void update_window_sizing() {
		set_default_size(primary_monitor_geo.width, primary_monitor_geo.height);
		flow.set_size_request(primary_monitor_geo.width - (MARGIN * 2), primary_monitor_geo.height);
		// N.B. MARGIN * 2 takes into account flow start & end spacing
		get_item_size(); // Update desired item spacing
		enforce_content_limit();
	}

	// =================================================================
	// Drag and Drop Icon Repositioning Functions
	// =================================================================

	// get_positions_file_path returns the full path to the positions file
	private string get_positions_file_path() {
		string config_dir = Path.build_filename(Environment.get_home_dir(), POSITIONS_DIR);
		return Path.build_filename(config_dir, POSITIONS_FILE);
	}

	// is_auto_arranged returns true if we're using default alphabetical sorting
	private bool is_auto_arranged() {
		return !using_custom_positions;
	}

	// ensure_positions_directory creates the config directory if it doesn't exist
	private bool ensure_positions_directory() {
		string config_dir = Path.build_filename(Environment.get_home_dir(), POSITIONS_DIR);
		File dir = File.new_for_path(config_dir);

		if (!dir.query_exists()) {
			try {
				dir.make_directory_with_parents();
				debug("Created positions directory: %s", config_dir);
				return true;
			} catch (Error e) {
				warning("Failed to create positions directory: %s", e.message);
				return false;
			}
		}
		return true;
	}

	// get_item_identifier returns a unique identifier for an item
	private string get_item_identifier(DesktopItem item) {
		if (item.is_mount) {
			MountItem mount_item = (MountItem) item;
			return "mount:" + mount_item.uuid;
		} else if (item.is_special) {
			FileItem file_item = (FileItem) item;
			return "special:" + file_item.file_type;
		} else {
			// Use file path instead of label_name to ensure uniqueness
			// (multiple files can have the same display name)
			FileItem file_item = (FileItem) item;
			string file_path = file_item.file.get_path();
			return "file:" + file_path;
		}
	}

	// load_custom_positions loads saved icon positions from file
	private void load_custom_positions() {
		custom_positions = new HashTable<string, int>(str_hash, str_equal);

		string positions_file = get_positions_file_path();
		File file = File.new_for_path(positions_file);

		if (!file.query_exists()) {
			debug("No custom positions file found at: %s", positions_file);
			using_custom_positions = false;
			return;
		}

		try {
			string contents;
			uint8[] contents_data;
			file.load_contents(null, out contents_data, null);
			contents = (string) contents_data;

			string[] lines = contents.split("\n");
			int valid_entries = 0;

			foreach (string line in lines) {
				string trimmed = line.strip();
				if (trimmed.length == 0 || trimmed.has_prefix("#")) {
					continue;
				}

				string[] parts = trimmed.split("=");
				if (parts.length != 2) {
					warning("Invalid position entry format: %s", line);
					continue;
				}

				string identifier = parts[0].strip();
				string position_str = parts[1].strip();

				int64 position;
				if (!int64.try_parse(position_str, out position)) {
					warning("Invalid position value for %s: %s", identifier, position_str);
					continue;
				}

				if (position < 0) {
					warning("Negative position value for %s: %lld", identifier, position);
					continue;
				}

				custom_positions.set(identifier, (int) position);
				valid_entries++;
			}

			if (valid_entries > 0) {
				using_custom_positions = true;
				debug("Loaded %d custom icon positions from: %s", valid_entries, positions_file);
			} else {
				warning("No valid position entries found in: %s", positions_file);
				using_custom_positions = false;
			}
		} catch (Error e) {
			warning("Failed to load custom positions from %s: %s", positions_file, e.message);
			using_custom_positions = false;
		}
	}

	// save_custom_positions_to_file saves the current custom_positions hash table to file
	private void save_custom_positions_to_file() {
		if (!ensure_positions_directory()) {
			return;
		}

		string positions_file = get_positions_file_path();
		File file = File.new_for_path(positions_file);

		StringBuilder content = new StringBuilder();
		content.append("# Budgie Desktop View Icon Positions\n");
		content.append("# Format: identifier=position\n");
		content.append("# Do not edit manually unless you know what you're doing\n\n");

		// Save directly from the custom_positions hash table
		// Do NOT rebuild from children - that would overwrite manual changes
		int count = 0;
		List<unowned string> keys = custom_positions.get_keys();

		// Sort entries by position value for cleaner file output
		keys.sort((a, b) => {
			int pos_a = custom_positions.get(a);
			int pos_b = custom_positions.get(b);
			return pos_a - pos_b;
		});

		foreach (unowned string identifier in keys) {
			int position = custom_positions.get(identifier);
			content.append_printf("%s=%d\n", identifier, position);
			count++;
		}

		try {
			file.replace_contents(content.str.data, null, false, FileCreateFlags.NONE, null);
			debug("Saved %d icon positions to file: %s", count, positions_file);
		} catch (Error e) {
			warning("Failed to save custom positions to %s: %s", positions_file, e.message);
		}
	}

	// on_toggle_auto_arrange handles the user toggling the auto-arrange menu item
	private void on_toggle_auto_arrange() {
		bool current_state = is_auto_arranged();

		if (current_state) {
			// Currently auto-arranged, user wants manual control
			// Initialize positions based on current order so they can start rearranging
			initialize_all_positions();
			save_custom_positions_to_file();
			desktop_menu.set_auto_arrange_state(false);
		} else {
			// Currently manual, user wants auto-arrange
			// Delete positions file and revert to alphabetical
			disable_custom_positions();
			desktop_menu.set_auto_arrange_state(true);
		}
	}

	// disable_custom_positions removes the positions file and reverts to default sorting
	private void disable_custom_positions() {
		string positions_file = get_positions_file_path();
		File file = File.new_for_path(positions_file);

		if (file.query_exists()) {
			try {
				file.delete();
				debug("Deleted custom positions file: %s", positions_file);
			} catch (Error e) {
				warning("Failed to delete positions file %s: %s", positions_file, e.message);
			}
		}

		custom_positions.remove_all();
		using_custom_positions = false;
		flow.invalidate_sort();
	}

	// update_auto_arrange_menu updates the menu check state
	private void update_auto_arrange_menu() {
		if (desktop_menu == null) {
			return;
		}

		desktop_menu.set_auto_arrange_state(is_auto_arranged());
	}

	// get_item_custom_position returns the custom position for an item, or -1 if none
	private int get_item_custom_position(DesktopItem item) {
		if (!using_custom_positions) {
			return -1;
		}

		string identifier = get_item_identifier(item);
		if (custom_positions.contains(identifier)) {
			return custom_positions.get(identifier);
		}
		return -1;
	}

	// setup_flowbox_drag_dest sets up the flowbox as a drag destination
	private void setup_flowbox_drag_dest() {
		Gtk.TargetEntry[] targets = {
			{ "BUDGIE_DESKTOP_ITEM", Gtk.TargetFlags.SAME_APP, 0 },
			{ "text/uri-list", 0, 1 },
			{ "application/x-desktop", 0, 2 }
		};

		Gtk.drag_dest_set(flow, Gtk.DestDefaults.MOTION, targets, Gdk.DragAction.MOVE | Gdk.DragAction.COPY);
		flow.drag_motion.connect(on_flowbox_drag_motion);
		flow.drag_leave.connect(on_flowbox_drag_leave);
		flow.drag_drop.connect(on_flowbox_drag_drop);
		flow.drag_data_received.connect(on_drag_data_received);
	}

	// setup_item_drag_source sets up an item as a drag source
	private void setup_item_drag_source(DesktopItem item) {
		Gtk.TargetEntry[] targets = {
			{ "BUDGIE_DESKTOP_ITEM", Gtk.TargetFlags.SAME_APP, 0 }
		};

		Gtk.drag_source_set(item, Gdk.ModifierType.BUTTON1_MASK, targets, Gdk.DragAction.MOVE);
		item.drag_begin.connect(on_item_drag_begin);
		item.drag_end.connect(on_item_drag_end);
		item.drag_data_get.connect(on_item_drag_data_get);
	}

	// setup_item_drag_dest sets up an item as a drag destination
	private void setup_item_drag_dest(DesktopItem item) {
		Gtk.TargetEntry[] targets = {
			{ "BUDGIE_DESKTOP_ITEM", Gtk.TargetFlags.SAME_APP, 0 },
			{ "text/uri-list", 0, 1 },
			{ "application/x-desktop", 0, 2 }
		};

		Gtk.drag_dest_set(item, Gtk.DestDefaults.MOTION, targets, Gdk.DragAction.MOVE | Gdk.DragAction.COPY);
		item.drag_motion.connect(on_item_drag_motion);
		item.drag_leave.connect(on_item_drag_leave);
		item.drag_drop.connect(on_item_drag_drop);
		item.drag_data_received.connect(on_item_drag_data_received);
	}

	// on_item_drag_begin handles the start of a drag operation
	private void on_item_drag_begin(Widget widget, Gdk.DragContext context) {
		DesktopItem item = (DesktopItem) widget;
		drag_primary_item = item;
		drag_source_items = new List<DesktopItem>();

		// Get all selected items
		List<weak FlowBoxChild> selected = flow.get_selected_children();

		if (selected.length() == 0) {
			// Nothing selected, just drag this item
			drag_source_items.append(item);
			debug("Drag begin for single item: %s", item.label_name);
		} else {
			// Drag all selected items
			foreach (weak FlowBoxChild child in selected) {
				DesktopItem selected_item = (DesktopItem) child;
				drag_source_items.append(selected_item);
				selected_item.set_opacity(DRAG_OPACITY);
			}
			debug("Drag begin for %u selected items", drag_source_items.length());
		}

		 // Set opacity to indicate dragging
		if (selected.length() == 0) {
			item.set_opacity(DRAG_OPACITY);
		}

		 List<weak Widget> children = flow.get_children();

		foreach (DesktopItem drag_item in drag_source_items) {
			int item_index = children.index(drag_item);
			debug("  Dragging: %s (index %d)", drag_item.label_name, item_index);
		}
	}

	// on_item_drag_end handles the end of a drag operation
	private void on_item_drag_end(Widget widget, Gdk.DragContext context) {
		// Restore opacity for all dragged items
		if (drag_source_items != null) {
			foreach (DesktopItem item in drag_source_items) {
				item.set_opacity(1.0);
			}
		}

		drag_source_items = null;
		drag_primary_item = null;
		drag_insert_index = -1;

		// Remove any visual indicators
		List<weak Widget> children = flow.get_children();
		foreach (weak Widget child in children) {
			DesktopItem desktop_item = (DesktopItem) child;
			desktop_item.get_style_context().remove_class("drag-insert-before");
			desktop_item.get_style_context().remove_class("drag-insert-after");
			desktop_item.get_style_context().remove_class("drag-swap-target");
		}

		debug("Drag end");
	}

	// on_item_drag_data_get provides data for the drag operation
	private void on_item_drag_data_get(Widget widget, Gdk.DragContext context,
										Gtk.SelectionData data, uint info, uint time) {
		// Send count of items being dragged
		if (drag_source_items != null) {
			string drag_data = "%u".printf(drag_source_items.length());
			data.set_text(drag_data, -1);
			debug("Drag data get: %u items", drag_source_items.length());
		}
	}

	// on_item_drag_motion handles drag motion over an item
	private bool on_item_drag_motion(Widget widget, Gdk.DragContext context,
									  int x, int y, uint time) {
		DesktopItem target_item = (DesktopItem) widget;

		if (drag_source_items == null || drag_source_items.length() == 0) {
			 Gdk.drag_status(context, 0, time);
			 return false;
		 }

		// Don't allow dropping on any of the items being dragged
		foreach (DesktopItem source_item in drag_source_items) {
			if (source_item == target_item) {
				Gdk.drag_status(context, 0, time);
				return false;
			}
		}

		// Get target item dimensions
		Gtk.Allocation alloc;
		target_item.get_allocation(out alloc);

		// Determine if we're hovering over the item (for swap) or between items (for insert)
		int edge_threshold = alloc.height / 4;

		// For multiple items, only allow insert mode (not swap)
		bool multi_drag = (drag_source_items.length() > 1);

		// Clear previous indicators
		List<weak Widget> children = flow.get_children();
		foreach (weak Widget child in children) {
			DesktopItem item = (DesktopItem) child;
			item.get_style_context().remove_class("drag-insert-before");
			item.get_style_context().remove_class("drag-insert-after");
			item.get_style_context().remove_class("drag-swap-target");
		}

		if (y < edge_threshold) {
			// Insert before this item
			target_item.get_style_context().add_class("drag-insert-before");
			Gdk.drag_status(context, Gdk.DragAction.MOVE, time);
			string mode = multi_drag ? "insert group before" : "insert before";
			debug("Drag motion: %s %s", mode, target_item.label_name);
			return true;
		} else if (y > alloc.height - edge_threshold) {
			// Insert after this item (visual indicator on next item)
			int target_index = children.index(target_item);
			if (target_index + 1 < (int)children.length()) {
				DesktopItem next_item = (DesktopItem) children.nth_data(target_index + 1);
				next_item.get_style_context().add_class("drag-insert-before");
			}
			Gdk.drag_status(context, Gdk.DragAction.MOVE, time);
			string mode = multi_drag ? "insert group after" : "insert after";
			debug("Drag motion: %s %s", mode, target_item.label_name);
			return true;
		} else if (!multi_drag) {
			// Swap with this item
			target_item.get_style_context().add_class("drag-swap-target");
			Gdk.drag_status(context, Gdk.DragAction.MOVE, time);
			debug("Drag motion: swap with %s", target_item.label_name);
			return true;
		} else {
			// Multi-select in middle area - treat as insert before
			target_item.get_style_context().add_class("drag-insert-before");
			Gdk.drag_status(context, Gdk.DragAction.MOVE, time);
			debug("Drag motion: insert group before %s", target_item.label_name);
			return true;
		}
	}

	// on_item_drag_leave handles drag leaving an item
	private void on_item_drag_leave(Widget widget, Gdk.DragContext context, uint time) {
		DesktopItem item = (DesktopItem) widget;
		item.get_style_context().remove_class("drag-insert-before");
		item.get_style_context().remove_class("drag-swap-target");
	}

	// on_item_drag_drop handles dropping on an item
	private bool on_item_drag_drop(Widget widget, Gdk.DragContext context,
									int x, int y, uint time) {
		DesktopItem target_item = (DesktopItem) widget;

		if (drag_source_items == null || drag_source_items.length() == 0) {
			warning("Drag drop on %s but drag_source_items is null/empty", target_item.label_name);
			return false;
		}

		// Check if target is one of the dragged items
		foreach (DesktopItem source_item in drag_source_items) {
			if (source_item == target_item) {
				debug("Drag drop on dragged item (%s), ignoring", target_item.label_name);
				return false;
			}
		}

		debug("Drag drop on %s, requesting data", target_item.label_name);
		Gtk.drag_get_data(widget, context, Gdk.Atom.intern_static_string("BUDGIE_DESKTOP_ITEM"), time);
		clear_selection(); // Clear any selection
		return true;
	}

	// on_item_drag_data_received handles the dropped data on an item
	private void on_item_drag_data_received(Widget widget, Gdk.DragContext context,
											 int x, int y, Gtk.SelectionData data,
											 uint info, uint time) {
		// Check if this is an external drop (from file manager) or internal repositioning
		string data_type = data.get_data_type().name();
		debug("Drag data received on item: type=%s, info=%u", data_type, info);

		if (info == 1 || info == 2) {
			// This is an external drop (text/uri-list or application/x-desktop)
			// Forward to the main window's drag handler
			debug("External drop detected, forwarding to window handler");
			on_drag_data_received(this, context, x, y, data, info, time);
			return;
		}

		// Otherwise, this is internal repositioning (info == 0, BUDGIE_DESKTOP_ITEM)
		handle_internal_reposition_drop(widget, context, x, y, data, info, time);
	}

	// handle_internal_reposition_drop handles dropping for icon repositioning
	private void handle_internal_reposition_drop(Widget widget, Gdk.DragContext context,
												  int x, int y, Gtk.SelectionData data,
												  uint info, uint time) {
		debug("Internal reposition drop");
		if (drag_source_items == null || drag_source_items.length() == 0) {
			warning("Drag data received but drag_source_items is null/empty");
			Gtk.drag_finish(context, false, false, time);
			return;
		}

		DesktopItem target_item = (DesktopItem) widget;

		// Check if target is one of the dragged items
		foreach (DesktopItem source_item in drag_source_items) {
			if (source_item == target_item) {
				Gtk.drag_finish(context, false, false, time);
				warning("Drag data received: target is one of the dragged items");
			 	return;
			}
		}

		List<weak Widget> children = flow.get_children();
		int target_index = children.index(target_item);

		if (target_index == -1) {
			Gtk.drag_finish(context, false, false, time);
			warning("Drag data received: could not find target in flowbox");
			return;
		}

		// Get target item dimensions to determine operation
		Gtk.Allocation alloc;
		target_item.get_allocation(out alloc);
		int edge_threshold = alloc.height / 4;

		bool multi_drag = (drag_source_items.length() > 1);

		if (y < edge_threshold || (multi_drag && y >= edge_threshold && y <= alloc.height - edge_threshold)) {
			// Insert before target
			perform_multi_insert_operation(target_index, true);
			debug("Dropping: insert %u item(s) before %s", drag_source_items.length(), target_item.label_name);
		 } else if (y > alloc.height - edge_threshold) {
			// Insert after target
			perform_multi_insert_operation(target_index, false);
			debug("Dropping: insert %u item(s) after %s", drag_source_items.length(), target_item.label_name);
		} else if (!multi_drag) {
			 // Swap positions
			int source_index = children.index(drag_source_items.nth_data(0));
			perform_swap_operation(source_index, target_index);
			debug("Dropping: swap with %s", target_item.label_name);
		} else {
			// Should not reach here
			warning("Unexpected drop location for multi-drag");
			Gtk.drag_finish(context, false, false, time);
			return;
		}

		Gtk.drag_finish(context, true, false, time);
	}

	// on_flowbox_drag_motion handles drag motion over empty flowbox areas
	private bool on_flowbox_drag_motion(Widget widget, Gdk.DragContext context,
										 int x, int y, uint time) {
		// Allow dropping in empty areas
		if (drag_source_items == null || drag_source_items.length() == 0) {
			return false;
		}

		// Check what type of drag this is
		Gdk.Atom target = Gtk.drag_dest_find_target(widget, context, null);
		if (target.name() == "text/uri-list" || target.name() == "application/x-desktop") {
			// This is an external drop
			debug("Flowbox drag motion: external drop detected");
			Gdk.drag_status(context, Gdk.DragAction.COPY, time);
			return true;
		}

		// Indicate we can drop in empty areas (to append to end)
		Gdk.drag_status(context, Gdk.DragAction.MOVE, time);

		// Clear any item-specific visual indicators since we're over empty space
		List<weak Widget> children = flow.get_children();
		foreach (weak Widget child in children) {
			DesktopItem item = (DesktopItem) child;
			item.get_style_context().remove_class("drag-insert-before");
			item.get_style_context().remove_class("drag-swap-target");
		}

		// Add visual indicator to the last item to show we'll append after it
		if (children.length() > 0) {
			DesktopItem last_item = (DesktopItem) children.nth_data(children.length() - 1);
			// Don't highlight if it's one of the dragged items
			bool is_dragged = false;
			foreach (DesktopItem source_item in drag_source_items) {
				if (last_item == source_item) is_dragged = true;
			}
			if (!is_dragged) {
				last_item.get_style_context().add_class("drag-insert-after");
			}
		}

		debug("Drag motion over empty flowbox area at (%d, %d) - will append %u item(s) to end", x, y, drag_source_items.length());
		return true;
	}

	// on_flowbox_drag_leave handles drag leaving the flowbox
	private void on_flowbox_drag_leave(Widget widget, Gdk.DragContext context, uint time) {
		drag_insert_index = -1;

		// Clear the append indicator
		List<weak Widget> children = flow.get_children();
		foreach (weak Widget child in children) {
			DesktopItem item = (DesktopItem) child;
			item.get_style_context().remove_class("drag-insert-after");
		}

		debug("Drag left flowbox");
	}

	// on_flowbox_drag_drop handles dropping on empty flowbox areas
	private bool on_flowbox_drag_drop(Widget widget, Gdk.DragContext context,
									   int x, int y, uint time) {
		// Check what type of drag this is
		Gdk.Atom target = Gtk.drag_dest_find_target(widget, context, null);
		debug("Flowbox drag drop: target=%s", target.name());

		if (target.name() == "text/uri-list" || target.name() == "application/x-desktop") {
			// This is an external drop, get the data and forward to main handler
			debug("External drop on flowbox, requesting data");
			Gtk.drag_get_data(widget, context, target, time);
			// The data will be received by the window's drag_data_received handler
			// since flowbox doesn't have its own handler connected
			return true;
		}

		if (drag_source_items == null || drag_source_items.length() == 0) {
			warning("Drag drop on flowbox but drag_source_items is null/empty");
			return false;
		}

		debug("Drag drop on empty flowbox area at (%d, %d) - appending %u item(s) to end", x, y, drag_source_items.length());
		perform_multi_append_operation();

		Gtk.drag_finish(context, true, false, time);
		clear_selection(); // Clear any selection
		return true;
	}

	// perform_multi_append_operation appends multiple items to the end
	private void perform_multi_append_operation() {
		initialize_all_positions();

		List<weak Widget> children = flow.get_children();

		// Get indices of all dragged items
		List<int> source_indices = new List<int>();
		foreach (DesktopItem source_item in drag_source_items) {
			int idx = children.index(source_item);
			if (idx != -1) {
				source_indices.append(idx);
			}
		}

		// Sort indices to maintain relative order
		source_indices.sort((a, b) => a - b);

		debug("Appending %u items to end", source_indices.length());
		// Rebuild positions, skipping dragged items, then adding them at the end
		custom_positions.remove_all();

		int new_position = 0;

		// First, add all non-dragged items
		for (int i = 0; i < (int)children.length(); i++) {
			if (source_indices.index(i) != -1) {
				// This is a dragged item, skip it for now
				DesktopItem skipped = (DesktopItem) children.nth_data(i);
				debug("Skipping dragged item at position %d: %s", i, skipped.label_name);
				continue;
			}

			DesktopItem current_item = (DesktopItem) children.nth_data(i);
			string current_id = get_item_identifier(current_item);
			custom_positions.set(current_id, new_position);
			debug("Positioned %s at %d", current_item.label_name, new_position);
			new_position++;
		}

		// Now add all dragged items at the end (in their original relative order)
		foreach (int source_idx in source_indices) {
			DesktopItem source_item = (DesktopItem) children.nth_data(source_idx);
			string source_id = get_item_identifier(source_item);
			custom_positions.set(source_id, new_position);
			debug("Positioned %s at %d (appended)", source_item.label_name, new_position);
			new_position++;
		}

		debug("Total positions set: %d, Hash table size: %u", new_position, custom_positions.size());

		save_custom_positions_to_file();
		flow.invalidate_sort();
		flow.queue_draw();

		debug("Append complete: %u items moved to end", source_indices.length());
	}

	// perform_multi_insert_operation inserts multiple items before or after target
	private void perform_multi_insert_operation(int target_index, bool before) {
		initialize_all_positions();

		List<weak Widget> children = flow.get_children();

		// Get indices of all dragged items
		List<int> source_indices = new List<int>();
		foreach (DesktopItem source_item in drag_source_items) {
			int idx = children.index(source_item);
			if (idx != -1) {
				source_indices.append(idx);
			}
		}

		// Sort indices to maintain relative order
		source_indices.sort((a, b) => a - b);

		int insert_index = before ? target_index : target_index + 1;

		// Adjust insert index based on how many dragged items are before the target
		int items_before_target = 0;
		 for (int i = 0; i < (int)children.length(); i++) {
			if (i < target_index && source_indices.index(i) != -1) {
				items_before_target++;
			}
		}

		// Adjust insert index
		if (before) {
			insert_index -= items_before_target;
		} else {
			insert_index -= items_before_target;
		}

		debug("Performing multi-insert: %u items at position %d (before=%s)",
				source_indices.length(), insert_index, before ? "true" : "false");

		// Rebuild all positions
		custom_positions.remove_all();

		int new_position = 0;
		bool inserted = false;

		for (int i = 0; i < (int)children.length(); i++) {
			// Skip dragged items
			if (source_indices.index(i) != -1) {
				 continue;
			 }

			// Check if we need to insert the dragged items here
			if (new_position == insert_index && !inserted) {
				foreach (int source_idx in source_indices) {
					DesktopItem source_item = (DesktopItem) children.nth_data(source_idx);
					string source_id = get_item_identifier(source_item);
					custom_positions.set(source_id, new_position);
					debug("Positioned %s at %d (inserted)", source_item.label_name, new_position);
					new_position++;
				}
				inserted = true;
			}

			 DesktopItem current_item = (DesktopItem) children.nth_data(i);
			 string current_id = get_item_identifier(current_item);
			 custom_positions.set(current_id, new_position);
			 debug("Positioned %s at %d", current_item.label_name, new_position);
			 new_position++;
		 }

		// If we haven't inserted yet (insert_index was at or past end), add them now
		if (!inserted) {
			foreach (int source_idx in source_indices) {
				DesktopItem source_item = (DesktopItem) children.nth_data(source_idx);
				string source_id = get_item_identifier(source_item);
				custom_positions.set(source_id, new_position);
				debug("Positioned %s at %d (appended)", source_item.label_name, new_position);
				new_position++;
			}
		}

		debug("Total positions set: %d, Hash table size: %u", new_position, custom_positions.size());

		save_custom_positions_to_file();
		flow.invalidate_sort();
		flow.queue_draw();

		debug("Multi-insert complete: %u items inserted at position %d", source_indices.length(), insert_index);
	}

	// initialize_all_positions creates custom positions for all current items based on current order
	private void initialize_all_positions() {
		if (using_custom_positions && custom_positions.size() > 0) {
			// Already initialized
			return;
		}

		debug("Initializing custom positions for all items");
		custom_positions.remove_all();

		List<weak Widget> children = flow.get_children();
		int position = 0;

		foreach (weak Widget child in children) {
			DesktopItem item = (DesktopItem) child;
			string identifier = get_item_identifier(item);

			if (custom_positions.contains(identifier)) {
				warning("Duplicate identifier detected during initialization: %s (already at position %d, trying to set to %d)",
						identifier, custom_positions.get(identifier), position);
			}

			custom_positions.set(identifier, position);
			debug("Initialized position %d for: %s", position, item.label_name);
			position++;
		}

		using_custom_positions = true;
		debug("Hash table contains %u entries", custom_positions.size());

		// Update menu to show we're now in manual mode
		update_auto_arrange_menu();
	}

	// perform_swap_operation swaps two items in the flowbox
	private void perform_swap_operation(int source_index, int target_index) {
		debug("Performing swap: source=%d, target=%d", source_index, target_index);

		// Initialize all positions if this is the first drag operation
		initialize_all_positions();

		List<weak Widget> children = flow.get_children();
		DesktopItem source_item = (DesktopItem) children.nth_data(source_index);
		DesktopItem target_item = (DesktopItem) children.nth_data(target_index);

		string source_id = get_item_identifier(source_item);
		string target_id = get_item_identifier(target_item);

		debug("Swapping positions: %s (pos %d) <-> %s (pos %d)",
				source_item.label_name, source_index, target_item.label_name, target_index);

		// Update positions in hash table by swapping them
		custom_positions.set(source_id, target_index);
		custom_positions.set(target_id, source_index);

		debug("Updated positions in memory: %s->%d, %s->%d",
				source_id, target_index, target_id, source_index);

		// Force the flowbox to re-sort with new positions
		// This ensures the visual order matches our saved positions
		flow.invalidate_sort();

		// Save the swapped positions to file
		save_custom_positions_to_file();

		debug("Swap complete: %s <-> %s", source_item.label_name, target_item.label_name);
	}
}
