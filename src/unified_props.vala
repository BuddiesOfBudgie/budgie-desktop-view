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

public enum ClickPolicyType {
	SINGLE = 1,
	DOUBLE = 2,
}

// UnifiedProps contains a multitude of shared properties used for our various item types
public class UnifiedProps : Object {
	public HashTable<string, Cancellable?> files_currently_copying; // All files currently being copied
	public bool is_launching;

	// Shared properties
	private GLib.Settings? _settings;
	private bool _is_single_click;
	private int _max_thumbnail_size;

	private Gdk.Cursor? _previous_cursor;
	private Gdk.Cursor? _current_cursor;
	public Gdk.Cursor? blocked_cursor;
	public Gdk.Cursor? hand_cursor;
	public Gdk.Cursor? loading_cursor;

	public Gdk.AppLaunchContext? launch_context;
	public FileMenu? file_menu;
	public IconTheme icon_theme;
	public int? icon_size;
	public int? s_factor;

	public signal void cursor_changed(Gdk.Cursor cursor);
	public signal void thumbnail_size_changed();

	// Create a new UnifiedProps.
	// Doesn't require any initial constructor properties since we want the flexibility of setting these across various parts of the codebase
	public UnifiedProps() {
		files_currently_copying = new HashTable<string, Cancellable>(str_hash, str_equal); // Create our empty list
		is_launching = false;
		_is_single_click = true;
		_max_thumbnail_size = 10;
	}

	public GLib.Settings desktop_settings {
		public get {
			return _settings;
		}

		public set {
			_settings = value;
			update_max_thumbnail_size();
			update_click_policy();
			_settings.changed["click-policy"].connect(update_click_policy);
			_settings.changed["max-thumbnail-size"].connect(() => {
				update_max_thumbnail_size();
				thumbnail_size_changed();
			});
		}
	}

	public bool is_single_click {
		public get {
			return _is_single_click;
		}
	}

	public int max_thumbnail_size {
		public get {
			return _max_thumbnail_size;
		}
	}

	public Gdk.Cursor? current_cursor {
		public get {
			return _current_cursor;
		}

		public set {
			_previous_cursor = _current_cursor;
			_current_cursor = value;
			if (_current_cursor != null) cursor_changed(_current_cursor);
		}
	}

	public Gdk.Cursor? previous_cursor {
		public get {
			return _previous_cursor;
		}
	}

	// is_copying returns if this file is currently copying
	public bool is_copying(string file_name) {
		return files_currently_copying.contains(file_name);
	}

	// is_desired_primary_click_type will return if the provided event matches our desired primary click type
	public bool is_desired_primary_click_type(EventButton ev) {
		if (ev.button != 1) { // Not left click
			return false;
		}

		return (_is_single_click) ? true : (ev.type == Gdk.EventType.DOUBLE_BUTTON_PRESS); // Return true if single click otherwise check if it was a double button press
	}

	// update_click_policy will update our single click value
	private void update_click_policy() {
		ClickPolicyType policy = (ClickPolicyType) _settings.get_enum("click-policy");
		_is_single_click = (policy == ClickPolicyType.SINGLE);
	}

	// update_max_thumbnail_size will update our max thumbnail size
	private void update_max_thumbnail_size() {
		_max_thumbnail_size = _settings.get_int("max-thumbnail-size");
	}
}