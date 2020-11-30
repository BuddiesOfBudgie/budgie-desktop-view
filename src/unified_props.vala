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

// UnifiedProps contains a multitude of shared properties used for our various item types
public class UnifiedProps : Object {
	// Shared properties
	public FileMenu? file_menu;
	public Gdk.Cursor? hand_cursor;
	public GLib.Settings? desktop_settings;
	public IconTheme icon_theme;
	public int? icon_size;
	public int? s_factor;

	// Create a new UnifiedProps.
	// Doesn't require any initial constructor properties since we want the flexibility of setting these across various parts of the codebase
	public UnifiedProps() {}
}