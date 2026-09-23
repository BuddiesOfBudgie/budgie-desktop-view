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

// LayoutProfile holds item positions for one grid size, e.g. every layout used on an 11x6 grid
public class LayoutProfile {
	public int cols;
	public int rows;
	public int64 last_used; // Microseconds since the epoch; used to evict old profiles and break ties
	public bool persisted; // Derived profiles stay in memory until the user changes something in them
	public HashTable<string, GridPos> items; // Item identifier to position

	public LayoutProfile(int cols, int rows) {
		this.cols = cols;
		this.rows = rows;
		last_used = 0;
		persisted = false;
		items = new HashTable<string, GridPos>(str_hash, str_equal);
	}

	// key is how this profile is stored in the layout file
	public string key {
		owned get {
			return profile_key(cols, rows);
		}
	}

	// profile_key formats a grid size as "<cols>x<rows>"
	public static string profile_key(int cols, int rows) {
		return "%dx%d".printf(cols, rows);
	}

	// parse_key reads a "<cols>x<rows>" key back. Returns false for anything malformed or non-positive.
	public static bool parse_key(string key, out int cols, out int rows) {
		cols = 0;
		rows = 0;
		string[] parts = key.split("x");
		if (parts.length != 2) return false;

		int64 c = 0, r = 0;
		if (!int64.try_parse(parts[0], out c) || !int64.try_parse(parts[1], out r)) return false;
		if (c <= 0 || r <= 0) return false; // A zero-size grid would make every position invalid

		cols = (int) c;
		rows = (int) r;
		return true;
	}
}
