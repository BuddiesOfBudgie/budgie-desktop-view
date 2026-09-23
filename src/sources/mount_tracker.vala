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

// MountTracker keeps a MountItem for every mounted volume, keyed by UUID
public class MountTracker : Object {
	private const string NO_UUID = "FAILED_TO_GET_UUID";

	private unowned UnifiedProps props;
	private VolumeMonitor volume_monitor;
	private HashTable<string, MountItem> items; // All active mounts, by UUID

	// mount_added and mount_removed track individual mounts; changed follows them so the view can relayout
	public signal void mount_added(MountItem item);
	public signal void mount_removed(MountItem item);
	public signal void changed();

	public MountTracker(UnifiedProps p) {
		props = p;
		items = new HashTable<string, MountItem>(str_hash, str_equal);

		volume_monitor = VolumeMonitor.get(); // Get our volume monitor
		volume_monitor.mount_added.connect(on_mount_added);
	}

	// load will get all the mounts of active volumes / drives. It doesn't emit changed().
	public void load() {
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

				string mount_uuid = get_mount_uuid(volume_mount); // Get the UUID for this mount

				if (mount_uuid == NO_UUID) { // Failed to get the mount
					return;
				}

				File? mount_file = volume_mount.get_default_location(); // Get the File for the default location of this mount

				if (mount_file == null) { // Has no location
					return;
				}

				add_item(volume_mount, mount_uuid); // Create the mount
			});
		});
	}

	// add_item will create our MountItem and add it if necessary
	private void add_item(Mount mount, string uuid) {
		if (items.contains(uuid)) { // Already have a mount with this UUID
			return;
		}

		MountItem mount_item = new MountItem(props, mount, uuid); // Create a new Mount Item
		mount_item.drive_disconnected.connect(on_mount_removed); // When we report our mount's related drive disconnected, call on_mount_removed
		mount_item.mount_name_changed.connect(() => { // When the name changes
			changed(); // Auto-arrange order is by name
		});

		items.set(uuid, mount_item);
		mount_added(mount_item);
	}

	// on_mount_added will handle signal events for when we add a mount
	private void on_mount_added(Mount mount) {
		string mount_uuid = get_mount_uuid(mount); // Get the UUID for this mount

		if (mount_uuid == NO_UUID) { // Failed to get the mount
			return;
		}

		if (items.contains(mount_uuid)) { // Already have this
			return;
		}

		add_item(mount, mount_uuid); // Create a new Mount item with this UUID
		changed();
	}

	// on_mount_removed will handle signal events for when a MountItem reports a disconnect
	private void on_mount_removed(MountItem mount_item) {
		// MountItem reports unmount, volume removal and drive disconnect alike, so this can run more than once per mount
		if (!items.contains(mount_item.uuid)) return;

		items.remove(mount_item.uuid); // Remove the item from our mounts
		mount_removed(mount_item); // Its layout position is kept so it returns to the same spot
		changed();
	}

	// get_mount_uuid will get a mount UUID, falling back to the volume UUID and then the device path
	private static string get_mount_uuid(Mount mount) {
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

		return NO_UUID;
	}
}
