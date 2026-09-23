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

// LayoutGrid tracks which parts of a cols x rows grid are taken while an operation places items
public class LayoutGrid {
	public int cols;
	public int rows;
	private GenericArray<GridPos> occupied; // Positions claimed so far; can be fractional

	public LayoutGrid(int cols, int rows) {
		this.cols = int.max(cols, 1); // Never allow an empty grid, so there is always somewhere to clamp to
		this.rows = int.max(rows, 1);
		occupied = new GenericArray<GridPos>();
	}

	// overlaps returns whether two one-cell items would cover each other
	public static bool overlaps(GridPos a, GridPos b) {
		// Every item is one cell in size, so they overlap when closer than a cell on both axes
		return (Math.fabs(a.col - b.col) < 1.0) && (Math.fabs(a.row - b.row) < 1.0);
	}

	// clamp pulls a position inside the grid so the whole item stays on screen
	public GridPos clamp(GridPos p) {
		return new GridPos(p.col.clamp(0, cols - 1), p.row.clamp(0, rows - 1));
	}

	public bool is_free(GridPos p) {
		for (int i = 0; i < occupied.length; i++) {
			if (overlaps(p, occupied[i])) return false;
		}

		return true;
	}

	public void occupy(GridPos p) {
		occupied.add(p);
	}

	// nearest_free returns the free whole cell closest to p
	public GridPos? nearest_free(GridPos p) {
		GridPos? best = null;
		double best_dist = double.MAX;

		// Check every cell. Grids are a few hundred cells at most, so this stays cheap.
		for (int c = 0; c < cols; c++) {
			for (int r = 0; r < rows; r++) {
				var candidate = new GridPos(c, r);
				double dist = Math.pow(c - p.col, 2) + Math.pow(r - p.row, 2); // Squared distance is enough for comparing

				// Strictly less than, so ties go to the earlier cell in column-major order
				if (dist < best_dist && is_free(candidate)) {
					best = candidate;
					best_dist = dist;
				}
			}
		}

		return best; // null when every cell is taken
	}

	// first_free returns the first free cell in column-major order, the order auto-arrange fills in
	public GridPos? first_free() {
		for (int c = 0; c < cols; c++) {
			for (int r = 0; r < rows; r++) {
				var candidate = new GridPos(c, r);
				if (is_free(candidate)) return candidate;
			}
		}

		return null; // Grid is full
	}

	// claim occupies p if it is free, otherwise the nearest free cell. Returns null when the grid is full.
	public GridPos? claim(GridPos p) {
		GridPos target = clamp(p); // Off-grid positions come back onto the grid first

		if (!is_free(target)) {
			target = nearest_free(target); // Taken, so fall back to the closest whole cell
		}

		if (target != null) occupy(target);
		return target;
	}
}
