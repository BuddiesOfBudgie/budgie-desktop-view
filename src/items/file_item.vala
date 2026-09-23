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
using GLib;
using Gtk;

public class FileItem : DesktopItem {
	// INFO_ATTRIBUTES is what every FileInfo handed to a FileItem should be queried with; time::modified is for Sort By
	public const string INFO_ATTRIBUTES = "standard::*,time::modified";

	public File file;
	public FileInfo info;
	public DesktopAppInfo? app_info = null;
	public KeyFile? keyfile = null;

	public bool exclude_item = false;

	private List<File> _flist;
	private string _ftype;
	private Icon? _override_icon = null;
	private string? _override_icon_name = "";
	private bool use_override_icon = false;
	private Cancellable? thumbnail_cancellable = null; // The thumbnail load in progress, if any

	public FileItem(UnifiedProps p, File f, FileInfo finfo, Icon? override_icon) {
		props = p;
		file = f;

		if (finfo == null) { // If no file_info was provided
			try {
				finfo = file.query_info(INFO_ATTRIBUTES, 0); // Get the info for the old file
			} catch (Error e) { // Failed to get the info
				warning("Failed to get file info: %s", e.message);
			}
		}

		_flist = new List<File>();
		_flist.append(file); // Add the file

		info = finfo; // Set our file info
		_ftype = finfo.get_content_type(); // Set the file type to the file mimetype

		if (_ftype == "application/x-desktop") { // Desktop File
			string path = file.get_path();
			app_info = new DesktopAppInfo.from_filename(path); // Get the DesktopAppInfo for this file with its absolute path

			if (app_info != null) { // Successfully got the App Info
				string? app_name = app_info.get_locale_string("DisplayName"); // Get the locale string for the display name

				if (app_name == null) {
					app_name = app_info.get_display_name();
				}

				label_name = app_name;
			} else {
				keyfile = new KeyFile();

				try {
					string group = "Desktop Entry";
					keyfile.load_from_file(path, KeyFileFlags.NONE); // Attempt to load the file as a key file

					if (override_icon == null) { // No override_icon provided
						try {
							string icon_name = keyfile.get_string(group, "Icon");
							_override_icon_name = icon_name;
						} catch (Error e) { // Failed to load the icon or get the name
							warning("Failed to load any icon for this KeyFile. Using our fallback instead.");
							_override_icon_name = "application-x-executable";
						}
					}

					try {
						string keyfile_name = keyfile.get_string(group, "Name"); // Attempt to get the name
						label_name = keyfile_name; // Set our label name to the keyfile name
					} catch (Error e) { // Failed to load the name
						warning("Failed to get KeyFile Name for %s. Setting as %s", path, info.get_display_name());
						label_name = info.get_display_name();
					}
				} catch (Error e) {
					warning("Failed to parse the %s as a KeyFile. Excluding item.", path);
					keyfile = null; // Change back to null
					exclude_item = true;
				}
			}
		}

		if ((app_info == null) && (keyfile == null)) { // Not a desktop file or couldn't get as key file
			label_name = info.get_display_name(); // Default our name to being the display name of the file
		}

		_type = (_ftype == "inode/directory") ? "dir" : "file";
		if (override_icon != null) {
			icon = override_icon;
			_override_icon = override_icon;
			use_override_icon = true;
		} else if (_override_icon_name != "") { // Non-empty override icon name
			use_override_icon = true;
		}

		try {
			update_icon(); // Set the icon immediately
		} catch (Error e) {
			warning("Failed to set icon for FileItem %s: %s", _name, e.message);
		}

		button_release_event.connect(on_button_release);
	}

	public List<File> file_list {
		public get {
			return _flist;
		}
	}

	public string file_type {
		public get {
			return _ftype;
		}

		// Only allow setting when special
		public set {
			if (!is_special) { // Not special
				return;
			}

			_ftype = value;
		}
	}

	// is_launcher is true for .desktop files, which open an application instead of the file itself
	public bool is_launcher {
		get { return app_info != null || keyfile != null; }
	}

	// Home and Trash always exist, so a fixed name is enough; files use their path
	public override string layout_id {
		owned get {
			return is_special ? "special:" + _ftype : layout_id_for(file);
		}
	}

	// layout_id_for gives the layout id a file on the Desktop has or will have, e.g. before a drop finishes copying.
	// The path is used since multiple files can share a display name.
	public static string layout_id_for(File f) {
		return "file:" + f.get_path();
	}

	public override void reload_icon() throws Error {
		update_icon(); // Also reloads app icons and image thumbnails, which set_icon_factors alone wouldn't
	}

	// create_special will create a FileItem for a special directory, "home" or "trash"
	public static FileItem? create_special(UnifiedProps props, string item_type) {
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
		FileItem special_item = new FileItem(props, special_file, special_file_info, special_icon);
		special_item.is_special = true; // Say that it is special.
		special_item.file_type = item_type; // Override file_type

		if (item_type == "trash") {
			special_item.label_name = _("Trash");
		}

		return special_item;
	}

	// emit_launch will handle launching a file assuming it isn't in a copying state
	public bool emit_launch() {
		if (props.files_currently_copying.contains(info.get_display_name())) { // Currently copying this file
			return Gdk.EVENT_STOP;
		}

		launch(false);
		return Gdk.EVENT_STOP;
	}

	// get_mimetype_icon will attempt to get the icon for the content / mimetype of the file
	public ThemedIcon get_mimetype_icon() {
		ThemedIcon themed_icon = (ThemedIcon) info.get_icon(); // Get the icon from the file info
		string content_type_to_icon = _ftype.replace("/", "-"); // Replace / with -. Example video/x-theora+ogg -> video-x...
		content_type_to_icon = content_type_to_icon.replace("+", "-"); // Replace + with -. Example video-x-theory-ogg
		themed_icon.prepend_name(content_type_to_icon); // Try our content type one first

		return themed_icon;
	}

	public override void open() {
		emit_launch();
	}

	// on_button_release handles right click; left click is handled by DesktopCanvas
	public bool on_button_release(EventButton ev) {
		if (ev.button == 3) { // Right click
			DesktopCanvas? canvas = get_parent() as DesktopCanvas;
			if (canvas != null) {
				if (!is_selected) canvas.select_only(this); // Right-clicking outside the selection acts on this item alone

				List<FileItem> selected_items = new List<FileItem>();
				foreach (DesktopItem item in canvas.get_selected()) {
					if (item is FileItem) {
						selected_items.append((FileItem) item);
					}
				}

				props.file_menu.set_item(this, selected_items); // Set the FileItem and selection on the FileMenu
			} else {
				props.file_menu.set_item(this, null); // Set just this item
			}

			props.file_menu.is_copying = props.files_currently_copying.contains(info.get_display_name()); // Set the FileMenu is_copying to if files_currently_copying contains this item
			props.file_menu.show_open_in_terminal = ((app_info == null) && (keyfile == null));
			props.file_menu.show_menu(ev); // Call show_menu which handles popup at pointer and screen setting

			return Gdk.EVENT_STOP;
		}

		return Gdk.EVENT_PROPAGATE;
	}

	// launch will attempt to launch the file.
	// This optionally takes in in_terminal indicating to open in the user's default terminal as well as the terminal process name
	public void launch(bool in_terminal) {
		props.launch_context.set_timestamp(CURRENT_TIME);

		if (app_info != null) { // If we got the app info for this
			try {
				app_info.launch(null, props.launch_context); // Launch the application
			} catch (Error e) {
				warning("Failed to launch %s: %s", name, e.message);
			}

			return;
		}

		if (keyfile != null) { // Have a custom key file
			try {
				string keyfile_url = keyfile.get_string("Desktop Entry", "URL");
				AppInfo.launch_default_for_uri(keyfile_url, props.launch_context);
			} catch (Error e) {
				warning("Failed to launch %s: %s", name, e.message);
			}

			return;
		}

		if (in_terminal && (props.desktop_settings != null)) { // If we're launching this via a Terminal and we have the required settings
			string preferred_terminal = props.desktop_settings.get_string("terminal");
			bool supported_terminal = (preferred_terminal in SUPPORTED_TERMINALS);

			if (!supported_terminal) { // Not a supported terminal
				warning("Unknown Terminal provided. Please use a supported Terminal or file an issue at https://github.com/BuddiesOfBudgie/budgie-desktop-view");
				warning("Consult Budgie Desktop View documentation at https://github.com/BuddiesOfBudgie/budgie-desktop-view/wiki on changing the default Terminal.");
				warning("Supported Terminals: %s", string.joinv(", ", SUPPORTED_TERMINALS));
				return;
			}

			string[] args = { preferred_terminal }; // Add our preferred terminal as first arg

			// alacritty supports -e, --working-directory WITHOUT equal
			// gnome-terminal supports --tab and --working-directory (no -w) WITH equal, but not -e
			// mate-terminal supports --tab and -e, --working-directory (no -w) WITH equal
			// konsole supports --new-tab and -e, --workdir WITHOUT equal
			// kitty supports --directory WITH equal
			// terminator supports --new-tab and -e,  --working-directory (no -w) WITH equal
			// tilix uses just -e, supports both --working-directory and -w WITH equal
			// xfce4-terminal supports -e, --tab, --window, and --working-directory (no -w) WITH equal
			if (
				(preferred_terminal != "alacritty") && // Not Alacritty, no tab CLI flag
				(preferred_terminal != "gnome-terminal") && // Not GNOME Terminal which uses --tab instead of --new-tab
				(preferred_terminal != "kgx") && // Not GNOME Console which uses --tab instead of --new-tab
				(preferred_terminal != "mate-terminal") && // Not Mate Terminal which uses --tab instead of --new-tab
				(preferred_terminal != "tilix") && // No new tab CLI flag (that I saw anyways)
				(preferred_terminal != "kitty") && // No new tab CLI flag for Kitty, either
				(preferred_terminal != "xfce4-terminal") // Not Xfce4 Terminal which uses --tab instead of --new-tab
			) {
				args += "--new-tab"; // Add --new-tab
			} else if (
			    (preferred_terminal == "gnome-terminal" || preferred_terminal == "kgx" || preferred_terminal == "mate-terminal" || preferred_terminal == "xfce4-terminal") &&
			    (_type == "file")
			) {
				args += "--tab"; // Create a new tab in an existing window or creates a new window
			}

			string path =  file.get_path();

			if (_type == "dir") { // If this is a directory
				switch (preferred_terminal) {
					case "alacritty": // Alacritty
						args += "--working-directory";
						args += path;
						break;
					case "kitty": // Kitty
						args += "--directory=%s".printf(path);
						break;
					case "konsole": // Konsole
						args += "--workdir";
						args += path;
						break;
					default:
						args += "--working-directory=%s".printf(path);
						break;
				}
			} else { // Not a directory
				var editor = Environment.get_variable("EDITOR");
				if (editor == null) {
					editor = "nano";
				}

				if (preferred_terminal == "gnome-terminal") {
					// gnome-terminal will not work with -e
					args += "--";
					args += editor;
					args += path;
				} else if (preferred_terminal == "mate-terminal") {
					// mate-terminal does not pass params with -e
					args += "-x";
					args += editor;
					args += path;
				} else if (preferred_terminal == "xfce4-terminal") {
					// xfce-terminal needs quoted commands with -e
					string[] cmd = { editor, path };
					args += "-e";
					args += string.joinv(" ", cmd); // join command so that its one command
				} else  {
					args += "-e";
					args += editor;
					args += path;
				}
			}

			try {
				Process.spawn_async(null, args, Environ.get(), SpawnFlags.SEARCH_PATH, null, null);
			} catch (Error e) { // Failed to launch the process
				warning("Failed to launch this process: %s", e.message);
			}

			return;
		}

		AppInfo? appinfo = null;

		if (file_type == "trash") { // Unique case for file type
			appinfo = (DesktopAppInfo) AppInfo.get_default_for_type("inode/directory", true); // Ensure we using something which can handle inode/directory
		} else {
			try {
				appinfo = file.query_default_handler(); // Get the default handler for the file
			} catch (Error e) {}
		}

		if (appinfo == null) {
			try {
				Process.spawn_async(null, {file.get_path()}, Environ.get(), SpawnFlags.STDERR_TO_DEV_NULL | SpawnFlags.STDOUT_TO_DEV_NULL, null, null);
			} catch (Error e) { // Failed to launch the process
				warning("Failed to launch this process: %s", e.message);
			}

			return;
		}

		try {
			if (file_type == "trash") { // Is trash
				List<string> trash_uris = new List<string>();
				trash_uris.append("trash:///"); // Open as trash:/// so Nautilus can show us the empty banner
				appinfo.launch_uris(trash_uris, props.launch_context);
			} else {
				appinfo.launch(file_list, props.launch_context); // Launch the file
			}
		} catch (Error e) {
			warning("Failed to launch %s: %s", name, e.message);
		}
	}

	// load_image_for_file shows a thumbnail in place of the icon when the file can have one, without blocking the desktop
	private async void load_image_for_file() {
		if (_type == "dir" || is_launcher) return; // Folders and launchers keep their icons

		// A newer load, e.g. after an icon size change, replaces any that is still running
		if (thumbnail_cancellable != null) thumbnail_cancellable.cancel();
		var cancellable = new Cancellable();
		thumbnail_cancellable = cancellable;

		try {
			int64 max_decode_bytes = (int64) props.max_thumbnail_size * 1000000; // max-thumbnail-size is in MB
			Pixbuf? thumb = yield Thumbnails.load(file, _ftype, info.get_size(), max_decode_bytes, props.icon_size, cancellable);

			if (thumb == null || cancellable.is_cancelled()) return; // No thumbnail possible, or superseded meanwhile
			set_image_pixbuf(thumb);
		} catch (Error e) {
			if (e is IOError.CANCELLED) return;
			warning("Failed to load a thumbnail for %s: %s", file.get_path(), e.message);
		}
	}

	// move_to_strash will move the file to the trash
	public void move_to_trash() {
		Cancellable? c = props.files_currently_copying.get(info.get_display_name()); // Get the cancellable

		if (c != null) { // If we got the cancellable, meaning this file is currently copying
			c.cancel(); // Cancel the copy operation
		}

		file.trash_async.begin(Priority.DEFAULT, null, (obj, res) => {
			try {
				file.trash_async.end(res);
			} catch (Error e) {
				warning("Failed to move %s to trash: %s", file.get_path(), e.message);
			}
		});
	}

	// update_icon updates our icon based on FileItem specific functionality
	public void update_icon() throws Error {
		set_icon_factors(); // Set various icon scale factors

		Icon? desired_icon = null;

		if (_override_icon_name != "") { // Have a override icon name
			try {
				set_icon_from_name(_override_icon_name);
			} catch (Error e) {
				throw e;
			}

			return;
		}

		if (use_override_icon) { // If we provided an override icon to use
			desired_icon = _override_icon;
		} else {
			if (app_info != null) { // If this is a Desktop File
				desired_icon = app_info.get_icon(); // Get the icon for this desktop file
			} else { // Normal file
				desired_icon = get_mimetype_icon(); // Immediately set the icon to the mimetype icon
			}
		}

		if (desired_icon != null) {
			icon = desired_icon;

			try {
				set_icon(desired_icon); // Set the icon
			} catch (Error e) {
				warning("Failed to set icon for FileItem %s: %s", _name, e.message);
				throw e;
			}
		}

		if (!use_override_icon) {
			load_image_for_file.begin((obj, res) => {; // Begin to asynchronously load any available pixbuf for this file
				load_image_for_file.end(res);
			});
		}
	}
}
