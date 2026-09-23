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

// ItemSortKey is the order auto-arrange uses and Sort By applies. The values match the ArrangeOrder enum in the
// gschema, so the arrange-order setting can be read and written with get_enum/set_enum.
public enum ItemSortKey {
	NAME = 0,
	TYPE = 1,
	MODIFIED = 2;

	// from_string parses the sort-by action's parameter; null for anything unknown
	public static ItemSortKey? from_string(string key) {
		switch (key) {
			case "name": return NAME;
			case "type": return TYPE;
			case "modified": return MODIFIED;
			default: return null;
		}
	}
}

// ItemOrder is the auto-arrange order: special folders, then mounts, then directories, then files.
// Names are compared with filename collation keys instead of the direct names, as they handle ints, -, and . in a
// predictable manner, e.g. cc.svg should be before cc-amex.svg, as well as handle locales. They're also faster.
namespace ItemOrder {
	// compare orders any two desktop items
	public int compare(DesktopItem c1, DesktopItem c2) {
		if (c1.is_special && !c2.is_special) { // First is special
			return -1;
		} else if (!c1.is_special && c2.is_special) { // Second is special
			return 1;
		} else if (c1.is_special && c2.is_special) { // Both are special: Home, then Trash
			return strcmp(((FileItem) c1).file_type, ((FileItem) c2).file_type); // "home" sorts before "trash"
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

		return compare_files((FileItem) c1, (FileItem) c2); // At this point, compare the dir / file names
	}

	// compare_by orders items for Sort By. Special folders and mounts always lead, as in auto-arrange, so sorting
	// never buries Home or Trash among files.
	public int compare_by(ItemSortKey key, DesktopItem c1, DesktopItem c2) {
		if (key == ItemSortKey.NAME || !(c1 is FileItem) || !(c2 is FileItem) || c1.is_special || c2.is_special) {
			return compare(c1, c2); // Name order, which also handles every special folder and mount case
		}

		FileItem f1 = (FileItem) c1;
		FileItem f2 = (FileItem) c2;

		if (key == ItemSortKey.TYPE) {
			// Folders first, then files grouped by content type, then by name within each type
			bool f1_is_dir = (f1.item_type == "dir");
			bool f2_is_dir = (f2.item_type == "dir");
			if (f1_is_dir != f2_is_dir) return f1_is_dir ? -1 : 1;

			int by_type = strcmp(f1.file_type, f2.file_type);
			if (by_type != 0) return by_type;

			return compare_files(f1, f2);
		}

		// Newest first, as file managers default to for dates; ties fall back to name
		uint64 m1 = f1.info.get_attribute_uint64(FileAttribute.TIME_MODIFIED);
		uint64 m2 = f2.info.get_attribute_uint64(FileAttribute.TIME_MODIFIED);
		if (m1 != m2) return (m1 > m2) ? -1 : 1;

		return compare_files(f1, f2);
	}

	// compare_files puts application launchers first, then folders, then other files, with the names in each group
	// collated. Launchers get their own group so apps don't end up mixed in among documents and media.
	public int compare_files(FileItem c1, FileItem c2) {
		int c1_group = file_group(c1);
		int c2_group = file_group(c2);
		if (c1_group != c2_group) return c1_group - c2_group;

		string c1_ck = c1.label_name.collate_key_for_filename();
		string c2_ck = c2.label_name.collate_key_for_filename();

		return strcmp(c1_ck, c2_ck); // Same group, so compare the collated names
	}

	// file_group ranks a file for compare_files: launchers 0, folders 1, everything else 2
	private int file_group(FileItem item) {
		if (item.is_launcher) return 0;
		if (item.item_type == "dir") return 1;
		return 2;
	}
}
