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

public class FileItem : DesktopItem {
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

	public FileItem(UnifiedProps p, File f, FileInfo finfo, Icon? override_icon) {
		props = p;
		file = f;

		if (finfo == null) { // If no file_info was provided
			try {
				finfo = file.query_info("standard::*", 0); // Get the info for the old file
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

		button_press_event.connect(on_button_press);
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

	// get_mimetype_icon will attempt to get the icon for the content / mimetype of the file
	public ThemedIcon get_mimetype_icon() {
		ThemedIcon themed_icon = (ThemedIcon) info.get_icon(); // Get the icon from the file info
		string content_type_to_icon = _ftype.replace("/", "-"); // Replace / with -. Example video/x-theora+ogg -> video-x...
		content_type_to_icon = content_type_to_icon.replace("+", "-"); // Replace + with -. Example video-x-theory-ogg
		themed_icon.prepend_name(content_type_to_icon); // Try our content type one first

		return themed_icon;
	}

	// on_button_release handles when we've released our mouse button
	// This is only intended to be used for left single click and right click
	public bool on_button_release(EventButton ev) {
		if (props.is_single_click && ev.type == EventType.BUTTON_RELEASE && props.is_desired_primary_click_type(ev)) { // Single left click
			launch(false);
			return Gdk.EVENT_STOP;
		} else if (ev.button == 3) { // Right click
			if ((app_info == null) && (keyfile == null)) { // If this isn't an application or custom key file
				props.file_menu.set_item(this); // Set the FileItem on the FileMenu
				props.file_menu.show_menu(ev); // Call show_menu which handles popup at pointer and screen setting
			}

			return Gdk.EVENT_STOP;
		}

		return Gdk.EVENT_PROPAGATE;
	}

	// on_button_press handles when we've pressed our mouse button
	// This is only used for double left click
	public bool on_button_press(EventButton ev) {
		if (ev.button == 1 && (!props.is_single_click && props.is_desired_primary_click_type(ev))) { // Left double Click
			launch(false); // Launch normally
			return Gdk.EVENT_STOP;
		}

		return Gdk.EVENT_PROPAGATE;
	}

	// launch will attempt to launch the file.
	// This optionally takes in in_terminal indicating to open in the user's default terminal as well as the terminal process name
	public void launch(bool in_terminal) {
		Gdk.AppLaunchContext launch_context = (Display.get_default()).get_app_launch_context(); // Get the app launch context for the default display
		launch_context.set_screen(Screen.get_default()); // Set the screen
		launch_context.set_timestamp(CURRENT_TIME);

		if (app_info != null) { // If we got the app info for this
			try {
				app_info.launch(null, launch_context); // Launch the application
			} catch (Error e) {
				warning("Failed to launch %s: %s", name, e.message);
			}

			return;
		}

		if (keyfile != null) { // Have a custom key file
			try {
				string keyfile_url = keyfile.get_string("Desktop Entry", "URL");
				AppInfo.launch_default_for_uri(keyfile_url, launch_context);
			} catch (Error e) {
				warning("Failed to launch %s: %s", name, e.message);
			}

			return;
		}

		if (in_terminal && (props.desktop_settings != null)) { // If we're launching this via a Terminal and we have the required settings
			string preferred_terminal = props.desktop_settings.get_string("terminal");
			bool supported_terminal = (preferred_terminal in SUPPORTED_TERMINALS);

			if (!supported_terminal) { // Not a supported terminal
				warning("Unknown Terminal provided. Please use a supported Terminal or file an issue at https://github.com/getsolus/budgie-desktop-view");
				warning("Consult Budgie Desktop View documentation at https://github.com/getsolus/budgie-desktop-view/wiki on changing the default Terminal.");
				warning("Supported Terminals: %s", string.joinv(", ", SUPPORTED_TERMINALS));
				return;
			}

			string[] args = { preferred_terminal }; // Add our preferred terminal as first arg

			// alacritty supports -e, --working-directory WITHOUT equal
			// gnome-terminal supports -e, has special --tab, supports, --working-directory (no -w) WITH equal
			// mate-terminal supports --tab and -e, --working-directory (no -w) WITH equal
			// konsole supports --new-tab and -e, --workdir WITHOUT equal
			// terminator supports --new-tab and -e,  --working-directory (no -w) WITH equal
			// tilix uses just -e, supports both --working-directory and -w WITH equal
			if (
				((preferred_terminal == "alacritty") && (_type == "file")) && // Alacritty and type is file
				(preferred_terminal != "gnome-terminal") && // Not GNOME Terminal which uses --tab instead of --new-tab
				(preferred_terminal != "tilix") // No new tab CLI flag (that I saw anyways)
			) {
				args += "--new-tab"; // Add --new-tab
			} else if ((preferred_terminal == "gnome-terminal") && (_type == "file")) { // GNOME Terminal, self explanatory really
				args += "--tab"; // Create a new tab in an existing window or creates a new window
			}

			string path =  file.get_path();

			if (_type == "dir") { // If this is a directory
				switch (preferred_terminal) {
					case "alacritty": // Alacritty
						args += "--working-directory";
						args += path;
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
				args += "-e";
				args += path;
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
			} catch (Error e) {
				warning("Failed to get the default handler for this file: %s", e.message);
			}
		}

		if (appinfo == null) {
			warning("Failed to get app to handle this file.");
			return;
		}

		try {
			if ((file_type == "trash") && (appinfo.get_id() == "org.gnome.Nautilus.desktop")) { // Is trash and using Nautilus
				List<string> trash_uris = new List<string>();
				trash_uris.append("trash:///"); // Open as trash:/// so Nautilus can show us the empty banner
				appinfo.launch_uris(trash_uris, launch_context);
			} else {
				appinfo.launch(file_list, launch_context); // Launch the file
			}
		} catch (Error e) {
			warning("Failed to launch %s: %s", name, e.message);
		}
	}

	// load_image_for_file will asynchronously attempt to attempt to load any available pixbuf for this file and set it
	private async void load_image_for_file() {
		if (
			(!_ftype.has_prefix("image/")) || // Not an image
			(info.get_size() > 1000000) // Greater than 1MB
		) {
			return;
		}

		string file_path = file.get_path();

		try {
			Pixbuf? file_pixbuf = new Pixbuf.from_file_at_scale(file_path, props.icon_size, -1, true); // Load the file and scale it immediately. Set to 96 which is our max.
			set_image_pixbuf(file_pixbuf); // Set the image pixbuf
		} catch (Error e) {
			warning("Failed to create a PixBuf for the %s: %s\n", file_path, e.message);
		}

		return;
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