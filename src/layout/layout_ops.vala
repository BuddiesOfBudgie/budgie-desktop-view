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

// LayoutOps take the positions of all visible items and return new positions for the ones they change
namespace LayoutOps {
	// auto_arrange fills the grid column by column in the given order
	public HashTable<string, GridPos> auto_arrange(string[] ordered_ids, int cols, int rows) {
		var result = new HashTable<string, GridPos>(str_hash, str_equal);
		int capacity = int.max(cols, 1) * int.max(rows, 1);
		int per_column = int.max(rows, 1);

		// Items past capacity get no position, which the view treats as hidden
		for (int i = 0; i < ordered_ids.length && i < capacity; i++) {
			result.set(ordered_ids[i], new GridPos(i / per_column, i % per_column));
		}

		return result;
	}

	// place resolves final positions for visible items
	public HashTable<string, GridPos> place(string[] ordered_ids, HashTable<string, GridPos> known, int cols, int rows) {
		var result = new HashTable<string, GridPos>(str_hash, str_equal);
		var grid = new LayoutGrid(cols, rows);
		var unplaced = new GenericArray<string>();

		// Items with a saved position go first so a new item can't take a spot someone chose
		foreach (string id in ordered_ids) {
			GridPos? pos = known.get(id);
			if (pos == null) {
				unplaced.add(id);
				continue;
			}

			// A saved spot can already be taken, e.g. by a file placed while a mount was unplugged
			GridPos? claimed = grid.claim(pos);
			if (claimed != null) result.set(id, claimed);
		}

		// New items fill the gaps in auto-arrange order
		for (int i = 0; i < unplaced.length; i++) {
			GridPos? pos = grid.first_free();
			if (pos == null) break; // Grid is full; the rest stay hidden

			grid.occupy(pos);
			result.set(unplaced[i], pos);
		}

		return result;
	}

	private LayoutGrid grid_without(HashTable<string, GridPos> current, string[] ids, int cols, int rows) {
		var grid = new LayoutGrid(cols, rows);

		current.foreach((id, pos) => {
			if (!(id in ids)) grid.occupy(pos);
		});

		return grid;
	}

	// move shifts ids by a delta in cell units
	public HashTable<string, GridPos> move(HashTable<string, GridPos> current, string[] ids, double delta_col, double delta_row, bool snap, int cols, int rows) {
		var result = new HashTable<string, GridPos>(str_hash, str_equal);

		// Only items outside the moving set block; the set can pass through its own old cells
		var grid = grid_without(current, ids, cols, rows);

		foreach (string id in ids) {
			GridPos? orig = current.get(id);
			if (orig == null) continue;

			var target = new GridPos(orig.col + delta_col, orig.row + delta_row);
			if (snap) target = target.rounded();

			// claim clamps to the grid and falls back to the nearest free cell on a collision
			GridPos? claimed = grid.claim(target);
			if (claimed == null) { // Grid is full, stay put
				claimed = orig;
				grid.occupy(orig);
			}

			result.set(id, claimed);
		}

		return result;
	}

	// make_room inserts the moving ids at the line above insert_at, returning every item's new cell, or null when they don't fit
	public HashTable<string, GridPos>? make_room(HashTable<string, GridPos> current, string[] moving_ids, GridPos insert_at, int cols, int rows) {
		// The row can be rows, the line under the last row
		if (insert_at.col < 0 || insert_at.col >= cols || insert_at.row < 0 || insert_at.row > rows) return null;

		// Work in column-major order, the order auto-arrange fills in, so the bottom of a column runs on to the top of the next
		int capacity = cols * rows;
		int insert = (int) insert_at.col * rows + (int) insert_at.row;
		var occupant = new string?[capacity]; // Item on each cell by column-major index
		var vacated = new bool[capacity]; // Cells the moving items left

		foreach (unowned string id in current.get_keys()) {
			int index = cell_index(current.get(id), cols, rows);
			if (index < 0) continue;

			if (id in moving_ids) {
				vacated[index] = true;
			} else {
				occupant[index] = id;
			}
		}

		var result = new HashTable<string, GridPos>(str_hash, str_equal);
		int count = moving_ids.length;

		// Walk up from the line, counting the cells the moving items can land on above it: holes they left in the run of
		// items above the line, and free cells right above it
		int start = insert;
		int holes = 0;
		bool past_items = false;
		for (int index = insert - 1; index >= 0 && holes < count; index--) {
			if (occupant[index] != null) {
				past_items = true;
			} else if (vacated[index] || !past_items) {
				holes++;
			} else {
				break; // A gap above the items, which stay put
			}

			start = index;
		}

		// The items walked over close up toward the top, leaving the holes right above the line
		int next = start;
		for (int index = start; index < insert; index++) {
			string? id = occupant[index];
			if (id == null) continue;

			if (index != next) result.set(id, cell_at(next, rows));
			next++;
		}

		// The rest of the moving items take the cells from the line down, pushing what's there along until a free cell
		// absorbs the push
		int end = insert + count - holes;
		if (end > capacity) return null;

		var waiting = new Queue<string>(); // Pushed items in order, each waiting for the next cell it can take

		for (int index = insert; index < capacity; index++) {
			if (waiting.is_empty() && index >= end) break; // Past the landing cells with nothing left to place

			string? here = occupant[index];

			if (index < end) {
				if (here != null) waiting.push_tail(here);
				continue;
			}

			if (waiting.is_empty()) continue; // Nothing is pushing, so an item here stays put

			// Items keep their order, so whatever is here queues behind the ones pushing into it
			if (here != null) waiting.push_tail(here);
			result.set(waiting.pop_head(), cell_at(index, rows));
		}

		if (!waiting.is_empty()) return null; // Items left waiting would fall off the end of the grid

		// Moving items land on consecutive cells at the line, keeping the order they had; any without a cell go last
		var moving = new GenericArray<string>();
		foreach (string id in moving_ids) {
			moving.add(id);
		}

		moving.sort_with_data((a, b) => fill_order(current, a, cols, rows) - fill_order(current, b, cols, rows));

		for (int i = 0; i < moving.length; i++) {
			result.set(moving[i], cell_at(insert - holes + i, rows));
		}

		return result;
	}

	// fill_order returns an item's column-major index, putting items that aren't on the grid after every cell
	private int fill_order(HashTable<string, GridPos> current, string id, int cols, int rows) {
		GridPos? pos = current.get(id);
		int index = (pos != null) ? cell_index(pos, cols, rows) : -1;
		return (index >= 0) ? index : cols * rows;
	}

	// cell_at returns the cell at a column-major index
	private GridPos cell_at(int index, int rows) {
		return new GridPos(index / rows, index % rows);
	}

	// cell_index returns a whole cell's column-major index, or -1 when it's off the grid
	private int cell_index(GridPos pos, int cols, int rows) {
		GridPos cell = pos.rounded();
		if (cell.col < 0 || cell.col >= cols || cell.row < 0 || cell.row >= rows) return -1;

		return (int) cell.col * rows + (int) cell.row;
	}

	// align_to_grid rounds each item to its nearest cell
	public HashTable<string, GridPos> align_to_grid(HashTable<string, GridPos> current, string[] ids, int cols, int rows) {
		var ordered = new GenericArray<string>();
		foreach (string id in ids) {
			if (current.contains(id)) ordered.add(id);
		}

		// Items already nearest a cell claim first, so aligned items never get pushed out by unaligned ones
		ordered.sort_with_data((a, b) => {
			double da = snap_distance(current.get(a));
			double db = snap_distance(current.get(b));
			return (da < db) ? -1 : ((da > db) ? 1 : 0);
		});

		return move(current, ordered.data, 0, 0, true, cols, rows);
	}

	private double snap_distance(GridPos p) {
		GridPos r = p.rounded();
		return Math.pow(p.col - r.col, 2) + Math.pow(p.row - r.row, 2);
	}

	// sort_in_place reorders ids within the cells they already occupy
	public HashTable<string, GridPos> sort_in_place(HashTable<string, GridPos> current, string[] ordered_ids, int cols, int rows) {
		// Free-placed items need a whole cell first so the sorted result lands on the grid
		var snapped = align_to_grid(current, ordered_ids, cols, rows);
		var cells = new GenericArray<GridPos>();

		snapped.foreach((id, pos) => {
			cells.add(pos);
		});

		// Column-major, matching the auto-arrange fill order
		cells.sort((a, b) => {
			if (a.col != b.col) return (a.col < b.col) ? -1 : 1;
			if (a.row != b.row) return (a.row < b.row) ? -1 : 1;
			return 0;
		});

		var result = new HashTable<string, GridPos>(str_hash, str_equal);
		int i = 0;

		foreach (string id in ordered_ids) {
			if (!snapped.contains(id)) continue;
			result.set(id, cells[i++]);
		}

		return result;
	}

	// derive maps a layout onto a grid of a different size
	public HashTable<string, GridPos> derive(HashTable<string, GridPos> source, int src_cols, int src_rows, int cols, int rows) {
		var result = new HashTable<string, GridPos>(str_hash, str_equal);
		var grid = new LayoutGrid(cols, rows);
		var ids = new GenericArray<string>();
		var mapped = new HashTable<string, GridPos>(str_hash, str_equal);
		var anchor_dist = new HashTable<string, double?>(str_hash, str_equal);

		source.foreach((id, pos) => {
			double col = pos.col;
			double row = pos.row;
			double dist = 0;

			// Items in the left half keep their distance from the left edge, items in the right half
			// from the right edge. Rows work the same way, so a bottom-right Trash stays bottom-right.
			if (col < src_cols / 2.0) {
				dist += col;
			} else {
				dist += (src_cols - 1) - col;
				col = cols - (src_cols - col);
			}

			if (row < src_rows / 2.0) {
				dist += row;
			} else {
				dist += (src_rows - 1) - row;
				row = rows - (src_rows - row);
			}

			ids.add(id);
			mapped.set(id, grid.clamp(new GridPos(col, row)));
			anchor_dist.set(id, dist);
		});

		// Items hugging an edge claim first; items in the middle of the old grid are the ones that move
		ids.sort_with_data((a, b) => {
			double da = anchor_dist.get(a);
			double db = anchor_dist.get(b);
			if (da != db) return (da < db) ? -1 : 1;
			return strcmp(a, b);
		});

		for (int i = 0; i < ids.length; i++) {
			GridPos pos = mapped.get(ids[i]);
			GridPos? claimed = grid.claim(pos);
			result.set(ids[i], claimed ?? pos); // Keep the overlap when full; place() drops it at render time
		}

		return result;
	}
}
