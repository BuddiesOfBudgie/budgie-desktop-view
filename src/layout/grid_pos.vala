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

// GridPos is an item's position in cell units rather than pixels, so it survives icon size changes.
// Whole numbers are a snapped cell; fractions are an item placed between cells with snapping off.
public class GridPos {
	public double col; // Columns from the left edge of the grid
	public double row; // Rows from the top edge of the grid

	public GridPos(double col, double row) {
		this.col = col;
		this.row = row;
	}

	// rounded returns the nearest whole cell
	public GridPos rounded() {
		return new GridPos(Math.round(col), Math.round(row));
	}
}
