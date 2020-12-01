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

public enum ClickPolicyType {
	SINGLE = 1,
	DOUBLE = 2,
}

// UnifiedProps contains a multitude of shared properties used for our various item types
public class UnifiedProps : Object {
	// Shared properties
	private GLib.Settings? _settings;
	private bool _is_single_click;
	public FileMenu? file_menu;
	public Gdk.Cursor? hand_cursor;
	public IconTheme icon_theme;
	public int? icon_size;
	public int? s_factor;

	// Create a new UnifiedProps.
	// Doesn't require any initial constructor properties since we want the flexibility of setting these across various parts of the codebase
	public UnifiedProps() {}

	public GLib.Settings desktop_settings {
		public get {
			return _settings;
		}

		public set {
			_settings = value;
			update_click_policy();
			_settings.changed["click-policy"].connect(update_click_policy);
		}
	}

	public bool is_single_click {
		public get {
			return _is_single_click;
		}
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
		try {
			ClickPolicyType policy = (ClickPolicyType) _settings.get_enum("click-policy");
			_is_single_click = (policy == ClickPolicyType.SINGLE);
		} catch (Error e) {
			warning("Failed to get click-policy enum: %s", e.message);
			_is_single_click = true; // Default to true
		}
	}
}