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
	"kitty",
	"konsole",
	"mate-terminal",
	"terminator",
	"tilix"
};

public class DesktopView : Gtk.ApplicationWindow {
	Screen default_screen;
	Display default_display;
	Monitor primary_monitor;
	Rectangle primary_monitor_geo;
	UnifiedProps shared_props;

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
			startup_id: "us.getsol.budgie-desktop-view",
			type_hint: Gdk.WindowTypeHint.DESKTOP
		);

		shared_props = new UnifiedProps(); // Create shared props
		shared_props.thumbnail_size_changed.connect(refresh_icon_sizes); // When our thumbnail size changed, refresh our icons

		Gtk.Settings? default_settings = Gtk.Settings.get_default(); // Get the default settings
		default_settings.gtk_application_prefer_dark_theme = true;

		file_items = new HashTable<string, FileItem>(str_hash, str_equal);
		mount_items =  new HashTable<string, MountItem>(str_hash, str_equal);

		shared_props.desktop_settings = new GLib.Settings("us.getsol.budgie-desktop-view"); // Get our desktop-view settings

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
		css.load_from_resource ("us/getsol/budgie-desktop-view/view.css");
		StyleContext.add_provider_for_screen(Screen.get_default(), css, STYLE_PROVIDER_PRIORITY_APPLICATION);

		if (!app_paintable) { // If the app isn't paintable, used in debugging
			get_style_context().add_class("debug");
		}

		// Window settings
		set_keep_below(true); // Stay below other windows
		set_position(WindowPosition.CENTER); // Don't account for anything like current pouse position
		show_menubar = false;

		desktop_menu = new DesktopMenu(); // Create our new desktop menu
		shared_props.file_menu = new FileMenu(shared_props); // Create our new file menu and set it in our shared props

		flow = new FlowBox();
		flow.get_style_context().add_class("flow");
		flow.halign = Align.START; // Start at the beginning
		flow.expand = false;
		flow.set_orientation(Gtk.Orientation.VERTICAL);
		flow.set_sort_func(sorter); // Set our sorting function
		flow.valign = Align.START; // Don't let it fill

		get_display_geo(); // Set our geo

		default_screen.composited_changed.connect(set_window_transparent);
		default_screen.monitors_changed.connect(on_resolution_change);
		default_screen.size_changed.connect(on_resolution_change);

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

		Gtk.TargetEntry[] targets = { { "application/x-icon-tasklist-launcher-id", 0, 0 }, { "text/uri-list", 0, 0 }, { "application/x-desktop", 0, 0 }};
		Gtk.drag_dest_set(this, Gtk.DestDefaults.ALL, targets, Gdk.DragAction.COPY);
		drag_data_received.connect(on_drag_data_received);

		set_window_transparent();

		if (visible_setting) {
			show();
		}
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
			special_item.label_name = "Trash";
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

				if (mount_uuid == "") { // Failed to get the mount
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
		default_screen = Screen.get_default(); // Get our current default Screen
		screen = default_screen;

		default_display = Display.get_default(); // Get the display related to it
		shared_props.blocked_cursor = new Cursor.from_name(default_display, "not-allowed");
		shared_props.hand_cursor = new Cursor.for_display(default_display, CursorType.HAND1);

		primary_monitor = default_display.get_primary_monitor(); // Get the actual primary monitor for this display

		primary_monitor_geo = primary_monitor.get_workarea(); // Get the working area of this monitor
		shared_props.s_factor = primary_monitor.get_scale_factor(); // Get the current scaling factor
		flow.set_size_request(primary_monitor_geo.width, primary_monitor_geo.height);
		update_window_position();
	}

	// get_mount_uuid will get a mount UUID and return it
	public string get_mount_uuid(Mount mount) {
		Volume? volume = mount.get_volume(); // Get the volume associated with this Mount

		if (volume == null) { // Failed to get the volume
			return ""; // Return an empty string
		}

		string volume_uuid = volume.get_uuid();
		string? mount_uuid = mount.get_uuid(); // Get any mount UUID

		if (mount_uuid == null) { // No mount UUID
			mount_uuid = volume_uuid; // Use volume UUID
		}

		return mount_uuid;
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

	// on_button_release handles the releasing of a mouse button
	private bool on_button_release(EventButton event) {
		if (event.button == 1) { // Left click
			desktop_menu.popdown(); // Hide the menu
			clear_selection(); // Clear any selection
			return Gdk.EVENT_PROPAGATE;
		} else if (event.button == 3) { // Right click
			desktop_menu.place_on_monitor(primary_monitor); // Ensure menu is on primary monitor
			desktop_menu.set_screen(default_screen); // Ensure menu is on our screen
			desktop_menu.popup_at_pointer(event); // Popup where our mouse is
			return Gdk.EVENT_STOP;
		} else {
			return Gdk.EVENT_PROPAGATE;
		}
	}

	// on_drag_data_received handles our drag_data_received
	private void on_drag_data_received(Gtk.Widget widget, Gdk.DragContext c, int x, int y, Gtk.SelectionData d, uint info, uint time) {
		string uri = (string) d.get_data(); // Get our data as a string
		string[] uris = uri.chomp().split("\n"); // Split on newlines in case we pass multiple items

		foreach (string file_uri in uris) { // For each file URI
			file_uri = file_uri.chomp();

			try {
				File this_file = File.new_for_uri(file_uri); // Load this file
				string file_base = this_file.get_basename();
				string file_dir = file_uri.replace(file_base, ""); // Get the directory
				file_dir = file_dir.replace("file://", "");

				if (file_base == desktop_file_uri) { // Copying from the Desktop to Desktop
					continue; // How about...no?
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
			} catch (Error e) {
				warning("Failed to load %s: %s", file_uri, e.message);
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
			delete_file_ref = file; // file ist he old file
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
			FlowBoxChild? first_item = flow.get_child_at_index(0);

			if (first_item != null) { // First item exists
				flow.select_child(first_item); // Select it
				set_focus(first_item); // Need this so the window knows what is selected and arrow nav works on second press
			}

			return Gdk.EVENT_STOP;
		} else if ((is_delete_key || is_enter_key) && have_selected_children) { // Pressed the delete or enter key while having a child selected
			DesktopItem generic_item = (DesktopItem) selected_children.nth_data(0); // Get the child as a DesktopItem

			if (generic_item.is_mount) { // If this is a mount
				if (is_delete_key) { // Can't delete mount
					return Gdk.EVENT_STOP;
				}

				MountItem item_as_mount = (MountItem) generic_item; // Cast as a MountItem
				item_as_mount.launch(); // Launch the item
			} else { // File Item
				FileItem item_as_file = (FileItem) generic_item; // Cast as a FileItem

				if (is_delete_key) { // Pressed the delete key
					item_as_file.move_to_trash(); // Move the item to trash
				} else { // Pressed enter key
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

		if (mount_uuid == "") { // Failed to get the mount
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
			update_window_position();
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

	private void update_window_position() {
		set_default_size(primary_monitor_geo.width, primary_monitor_geo.height);
		set_size_request(primary_monitor_geo.width, primary_monitor_geo.height);
		move(primary_monitor_geo.x, primary_monitor_geo.y); // Move the window to the x/y of our primary monitor
	}
}
