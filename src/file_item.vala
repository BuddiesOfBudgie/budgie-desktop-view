/*
Licensed to the Apache Software Foundation (ASF) under one
or more contributor license agreements.  See the NOTICE file
distributed with this work for additional information
regarding copyright ownership.  The ASF licenses this file
to you under the Apache License, Version 2.0 (the
"License"); you may not use this file except in compliance
with the License.  You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing,
software distributed under the License is distributed on an
"AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
KIND, either express or implied.  See the License for the
specific language governing permissions and limitations
under the License.
*/

using Gdk;
using Gtk;

public class FileItem : DesktopItem {
	public File file;
	public FileInfo info;
	public DesktopAppInfo? app_info;

	private List<File> _flist;
	private string _ftype;
	private Icon? _override_icon = null;
	private bool use_override_icon = false;

	public FileItem(IconTheme icon_theme, int size, int scale_factor, Gdk.Cursor cursor, File f, FileInfo finfo, Icon? override_icon) {
		pointer_cursor = cursor;
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
			app_info = new DesktopAppInfo.from_filename(file.get_path()); // Get the DesktopAppInfo for this file with its absolute path

			if (app_info != null) { // Successfully got the App Info
				string? app_name = app_info.get_locale_string("DisplayName"); // Get the locale string for the display name

				if (app_name == null) {
					app_name = app_info.get_display_name();
				}

				label_name = app_name;
			}
		} else {
			app_info = null;
			label_name = info.get_display_name(); // Default our name to being the display name of the file
		}

		_type = (_ftype == "inode/directory") ? "dir" : "file";
		icon = override_icon;
		_override_icon = override_icon;

		use_override_icon = (override_icon != null);

		try {
			update_icon(icon_theme, size, scale_factor); // Set the icon immediately
		} catch (Error e) {
			warning("Failed to set icon for FileItem %s: %s", _name, e.message);
		}
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

	// get_image_for_file will attempt to get the Pixbuf for this file if it is an image
	// Returns null if not an image or failed to load.
	public Pixbuf? get_image_for_file() {
		if (
			(!_ftype.has_prefix("image/")) || // Not an image
			(info.get_size() > 1000000) // Greater than 1MB
		) {
			return null;
		}

		string file_path = file.get_path();

		try {
			Pixbuf file_pixbuf = new Pixbuf.from_file_at_scale(file_path, _icon_size, -1, true); // Load the file and scale it immediately. Set to 96 which is our max.
			return file_pixbuf;
		} catch (Error e) {
			warning("Failed to create a PixBuf for the %s: %s\n", file_path, e.message);
			return null;
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

	// update_icon updates our icon based on FileItem specific functionality
	public void update_icon(IconTheme theme, int size, int scale_factor) throws Error {
		set_icon_factors(theme, size, scale_factor); // Set various icon scale factors

		Icon? desired_icon = null;

		if (use_override_icon) { // If we provided an override icon to use
			desired_icon = _override_icon;
		} else {
			if (app_info != null) { // If this is a Desktop File
				desired_icon = app_info.get_icon(); // Get the icon for this desktop file
			} else { // Normal file
				Pixbuf? pixbuf = get_image_for_file(); // Get the Pixbuf for this image, if it's even an image

				if (pixbuf != null) { // Got the pixbuf
					set_image_pixbuf(pixbuf); // Set the image pixbuf
				} else { // Failed to get a pixbuf for this file
					desired_icon = get_mimetype_icon();
				}
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
	}
}