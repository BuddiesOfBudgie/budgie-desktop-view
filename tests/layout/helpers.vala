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

HashTable<string, GridPos> positions(string[] ids, double[] cols, double[] rows) {
	var table = new HashTable<string, GridPos>(str_hash, str_equal);
	for (int i = 0; i < ids.length; i++) {
		table.set(ids[i], new GridPos(cols[i], rows[i]));
	}
	return table;
}

void assert_pos(HashTable<string, GridPos> table, string id, double col, double row) {
	GridPos? pos = table.get(id);
	if (pos == null) {
		Test.message("%s has no position", id);
		Test.fail();
		return;
	}

	if (pos.col != col || pos.row != row) {
		Test.message("%s expected (%g, %g), got (%g, %g)", id, col, row, pos.col, pos.row);
		Test.fail();
	}
}

void assert_no_overlaps(HashTable<string, GridPos> table) {
	var all = new GenericArray<GridPos>();
	table.foreach((id, pos) => all.add(pos));

	for (int i = 0; i < all.length; i++) {
		for (int j = i + 1; j < all.length; j++) {
			if (LayoutGrid.overlaps(all[i], all[j])) {
				Test.message("overlap at (%g, %g) and (%g, %g)", all[i].col, all[i].row, all[j].col, all[j].row);
				Test.fail();
			}
		}
	}
}

string temp_path(string name) {
	try {
		string dir = DirUtils.make_tmp("bdv-layout-XXXXXX");
		return Path.build_filename(dir, name);
	} catch (Error e) {
		error("Failed to create temp dir: %s", e.message);
	}
}
