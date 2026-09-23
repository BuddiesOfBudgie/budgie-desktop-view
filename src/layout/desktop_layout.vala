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

// DesktopLayout keeps one layout per grid size and persists them as GVariant text.
// Only one profile is active at a time: the one for the grid the screen currently fits.
public class DesktopLayout : Object {
	public const int MAX_PROFILES = 10; // Enough for every monitor setup someone realistically cycles through
	private const string VARIANT_TYPE = "a{s(xa{s(dd)})}"; // grid key -> (last used, item id -> (col, row))

	private string path;
	private HashTable<string, LayoutProfile> profiles; // Keyed by LayoutProfile.key
	private LayoutProfile? active = null;

	public DesktopLayout(string path) {
		this.path = path;
		profiles = new HashTable<string, LayoutProfile>(str_hash, str_equal);
	}

	public bool file_exists() {
		return FileUtils.test(path, FileTest.EXISTS);
	}

	// cols and rows are the active grid size, or 0 before the first activate()
	public int cols {
		get { return (active != null) ? active.cols : 0; }
	}

	public int rows {
		get { return (active != null) ? active.rows : 0; }
	}

	public uint profile_count {
		get { return profiles.size(); }
	}

	// load replaces all profiles with the ones in the layout file. A missing or corrupt file leaves no profiles.
	public void load() {
		profiles.remove_all();
		active = null;

		string contents;
		try {
			if (!FileUtils.get_contents(path, out contents)) return;
		} catch (Error e) {
			if (!(e is FileError.NOENT)) warning("Failed to read layout file %s: %s", path, e.message); // No file yet is normal
			return;
		}

		Variant root;
		try {
			root = Variant.parse(new VariantType(VARIANT_TYPE), contents); // Rejects anything that isn't exactly our type
		} catch (Error e) {
			warning("Failed to parse layout file %s: %s", path, e.message);
			return;
		}

		// Each child is one {key, (last_used, items)} dictionary entry
		for (size_t i = 0; i < root.n_children(); i++) {
			Variant entry = root.get_child_value(i);
			string key = entry.get_child_value(0).get_string();
			Variant val = entry.get_child_value(1);

			int cols, rows;
			if (!LayoutProfile.parse_key(key, out cols, out rows)) {
				warning("Ignoring layout profile with invalid key: %s", key);
				continue;
			}

			var profile = new LayoutProfile(cols, rows);
			profile.last_used = val.get_child_value(0).get_int64();
			profile.persisted = true; // It came from disk, so it is a layout the user made

			// Each item is an {id, (col, row)} dictionary entry
			Variant items = val.get_child_value(1);
			for (size_t j = 0; j < items.n_children(); j++) {
				Variant item = items.get_child_value(j);
				string id = item.get_child_value(0).get_string();
				Variant pos = item.get_child_value(1);
				profile.items.set(id, new GridPos(pos.get_child_value(0).get_double(), pos.get_child_value(1).get_double()));
			}

			profiles.set(key, profile);
		}
	}

	// save writes every persisted profile to the layout file, keeping only the most recently used ones
	public void save() {
		var persisted = new GenericArray<LayoutProfile>();
		profiles.foreach((key, profile) => {
			if (profile.persisted) persisted.add(profile); // Derived profiles are never written
		});

		// Newest first, so the cap drops the profiles that haven't been used in the longest time
		persisted.sort((a, b) => (a.last_used > b.last_used) ? -1 : ((a.last_used < b.last_used) ? 1 : 0));

		for (int i = MAX_PROFILES; i < persisted.length; i++) {
			profiles.remove(persisted[i].key);
		}

		var builder = new VariantBuilder(new VariantType(VARIANT_TYPE));
		for (int i = 0; i < persisted.length && i < MAX_PROFILES; i++) {
			LayoutProfile profile = persisted[i];
			var items = new VariantBuilder(new VariantType("a{s(dd)}"));

			profile.items.foreach((id, pos) => {
				items.add("{s(dd)}", id, pos.col, pos.row);
			});

			builder.add("{s(x@a{s(dd)})}", profile.key, profile.last_used, items.end()); // @ passes the items as an existing Variant
		}

		try {
			DirUtils.create_with_parents(Path.get_dirname(path), 0755);
			FileUtils.set_contents(path, builder.end().print(false) + "\n"); // Writes a temp file and renames it, so a crash never leaves half a file
		} catch (Error e) {
			warning("Failed to save layout file %s: %s", path, e.message);
		}
	}

	// activate switches to the profile for this grid size
	public void activate(int cols, int rows) {
		string key = LayoutProfile.profile_key(cols, rows);
		LayoutProfile? profile = profiles.get(key);

		if (profile == null) {
			// Derived profiles aren't persisted, so a temporary resolution never overwrites a saved layout
			profile = new LayoutProfile(cols, rows);
			LayoutProfile? source = closest_persisted(cols, rows);

			if (source != null) { // With nothing saved yet the profile starts empty and the view fills it
				profile.items = LayoutOps.derive(source.items, source.cols, source.rows, cols, rows);
			}

			profiles.set(key, profile);
		}

		profile.last_used = get_real_time();
		active = profile;
	}

	// closest_persisted finds the saved profile to derive a new grid size from
	private LayoutProfile? closest_persisted(int cols, int rows) {
		LayoutProfile? best = null;
		int best_dist = int.MAX;

		profiles.foreach((key, profile) => {
			if (!profile.persisted) return; // Deriving from a derived profile would compound its guesses

			// Closeness is column-count difference plus row-count difference; ties go to the most recently used
			int dist = (profile.cols - cols).abs() + (profile.rows - rows).abs();
			if (dist < best_dist || (dist == best_dist && profile.last_used > best.last_used)) {
				best = profile;
				best_dist = dist;
			}
		});

		return best;
	}

	// get_position returns an item's saved position in the active profile, or null if it has none
	public GridPos? get_position(string id) {
		return (active != null) ? active.items.get(id) : null;
	}

	// get_positions returns a copy of the active profile, so callers can modify it freely
	public HashTable<string, GridPos> get_positions() {
		var copy = new HashTable<string, GridPos>(str_hash, str_equal);
		if (active != null) {
			active.items.foreach((id, pos) => copy.set(id, pos));
		}
		return copy;
	}

	// commit records a change the user made and saves it. This is what turns a derived profile into a saved one.
	public void commit(HashTable<string, GridPos> updates) {
		if (active == null) return;

		updates.foreach((id, pos) => active.items.set(id, pos)); // Merge; items not in updates keep their positions
		active.persisted = true;
		active.last_used = get_real_time();
		save();
	}

	// assign records positions the view picked on its own, like a spot for a new file.
	// Unlike commit, this doesn't make a derived profile persist.
	public void assign(HashTable<string, GridPos> updates) {
		if (active == null) return;

		updates.foreach((id, pos) => active.items.set(id, pos));
		if (active.persisted) save(); // A saved profile should remember where new items went
	}

	// remove drops an id from every profile, used when its file is deleted
	public void remove(string id) {
		bool changed = false;

		profiles.foreach((key, profile) => {
			if (profile.items.remove(id) && profile.persisted) changed = true;
		});

		if (changed) save(); // Only touch the disk if a saved profile lost something
	}

	// rename re-keys an id in every profile so a renamed file keeps its position
	public void rename(string old_id, string new_id) {
		bool changed = false;

		profiles.foreach((key, profile) => {
			GridPos? pos = profile.items.get(old_id);
			if (pos == null) return; // This profile never saw the old name

			profile.items.remove(old_id);
			profile.items.set(new_id, pos);
			if (profile.persisted) changed = true;
		});

		if (changed) save();
	}
}
