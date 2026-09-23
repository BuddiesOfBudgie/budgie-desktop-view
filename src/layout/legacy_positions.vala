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

// LegacyPositions reads the icon-positions.conf written by 10.10.x, which stored a sort index per item instead of a position
namespace LegacyPositions {
	// read_order returns item ids sorted by their stored index. Missing or unreadable files give an empty list.
	public string[] read_order(string path) {
		var entries = new GenericArray<string>();
		var indexes = new HashTable<string, int64?>(str_hash, str_equal);

		string contents;
		try {
			if (!FileUtils.get_contents(path, out contents)) return {};
		} catch (Error e) {
			return {};
		}

		// Each entry is "identifier=index"; blank lines and # comments are skipped
		foreach (string line in contents.split("\n")) {
			string trimmed = line.strip();
			if (trimmed.length == 0 || trimmed.has_prefix("#")) continue;

			// Split on the last '=' since file paths can contain one
			int sep = trimmed.last_index_of("=");
			if (sep <= 0) continue;

			string id = trimmed.substring(0, sep).strip();
			int64 index;
			if (!int64.try_parse(trimmed.substring(sep + 1).strip(), out index) || index < 0) continue;

			if (!indexes.contains(id)) entries.add(id); // A repeated id keeps one entry, with its last index
			indexes.set(id, index);
		}

		entries.sort_with_data((a, b) => {
			int64 ia = indexes.get(a);
			int64 ib = indexes.get(b);
			return (ia < ib) ? -1 : ((ia > ib) ? 1 : 0);
		});

		string[] ordered = {};
		for (int i = 0; i < entries.length; i++) {
			ordered += entries[i];
		}

		return ordered;
	}
}
