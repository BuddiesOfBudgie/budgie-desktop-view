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

public class MountItem : DesktopItem {
	public Mount mount;
	public File mount_file;
	public string? uuid;

	public signal void drive_disconnected(MountItem item);
	public signal void mount_name_changed(MountItem item);

	public MountItem(IconTheme icon_theme, int size, int scale_factor, Gdk.Cursor cursor, Mount provided_mount, string true_uuid) {
		pointer_cursor = cursor;
		mount = provided_mount;
		uuid = true_uuid;
		_type = "mount"; // Report internally as a mount

		try {
			set_icon_factors(icon_theme, size, scale_factor); // Set various icon scale factors
		} catch (Error e) {
			warning("Failed to set icon factors when generating a MountItem: %s", e.message);
		}

		update_item(); // Get the file, mount name, set icon

		// Note: If you use GNOME Disks, changing the label will unmount your drive. GParted does not do this.
		// As such, we'll fire off the update_item but it won't matter if you use Disks, the mount is gone. Remounting it doesn't work because Disks pulls the Drive out from under it.
		// So if you want to change the label, be sensible and just use gparted. Any other app, I'll consider it a WONTFIX. Thanks.
		mount.changed.connect(() => {
			update_item();
		});

		mount.unmounted.connect(() => {
			drive_disconnected(this); // Emit drive_disconnected with ourself
		});

		Drive? mount_drive = mount.get_drive();

		if (mount_drive != null) {
			mount_drive.disconnected.connect(() => { // When the drive disconnects
				drive_disconnected(this); // Emit drive_disconnected with ourself
			});
		}

		Volume? mount_volume = mount.get_volume();

		if (mount_volume != null) {
			mount_volume.removed.connect(() => {
				drive_disconnected(this); // Emit drive_disconnected with ourself
			});
		}
	}

	// update_mount_info will update the DesktopItem and internal info related to this Mount
	public void update_item() {
		string mount_name = mount.get_name(); // Get the name of the mount

		if (label_name == "") { // No label set yet
			label_name = mount_name; // Set to the mount name immediately
		} else { // Label already set
			if (label_name != mount_name) { // Mount name changed
				label_name = mount_name; // Update the label
				mount_name_changed(this); // Inform that the mount name changed so our parent flowbox can resort
			}
		}

		mount_file = mount.get_default_location(); // Get the file for this mount

		List<string> icons_list = new List<string>(); // Create our icons lsit
		string[] sym_icons = ((ThemedIcon) mount.get_symbolic_icon()).get_names(); // Get all the names from the ThemedIcon

		for (var i = 0; i < sym_icons.length; i++) { // For each of the icons in the symbolic ThemedIcon
			string icon = sym_icons[i]; // Get the icon
			icon = icon.replace("-symbolic", ""); // Remove symbolic

			if (icons_list.index(icon) == -1) { // Not already added
				icons_list.append(icon); // Add the icon
			}
		}

		string[] new_icon_set = {};
		icons_list.foreach((icon) => {
			new_icon_set += icon;
		});

		ThemedIcon icon = new ThemedIcon.from_names(new_icon_set);

		try {
			set_icon(icon); // Ensure our mount's symbolic icon is up-to-date
		} catch (Error e) {
			warning("Failed to set the icon for a MountItem: %s", e.message);
		}
	}
}