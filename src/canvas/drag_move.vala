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

// DragMove follows a left-button press on an item: a click if it stays put, a group move once it passes the drag threshold
public class DragMove {
	public DesktopItem? press_item { get; private set; default = null; } // Item under the press; null when no press is in progress
	public bool had_modifier { get; private set; default = false; } // Ctrl or Shift was held, so a click edits the selection instead of opening
	public bool active { get; private set; default = false; } // Past the threshold and moving items
	public GenericArray<DesktopItem> items { get; private set; } // Items being moved
	public DesktopItem? drop_target { get; set; default = null; } // Trash or a folder under the pointer, which a drop moves the items into

	// How far the pointer has moved since the press, in pixels and in cells
	public double delta_x { get; private set; default = 0; }
	public double delta_y { get; private set; default = 0; }
	public double delta_col { get; private set; default = 0; }
	public double delta_row { get; private set; default = 0; }

	// Root coordinates stay consistent while the item under the pointer moves, so deltas come from them
	private double press_root_x;
	private double press_root_y;

	public DragMove() {
		items = new GenericArray<DesktopItem>();
	}

	// press records the start of a possible drag
	public void press(DesktopItem item, double root_x, double root_y, bool had_modifier) {
		press_item = item;
		press_root_x = root_x;
		press_root_y = root_y;
		this.had_modifier = had_modifier;
	}

	// past_threshold returns whether the pointer has moved far enough from the press to count as a drag
	public bool past_threshold(double root_x, double root_y) {
		int threshold = Gtk.Settings.get_default().gtk_dnd_drag_threshold; // Same distance GTK uses to start drag and drop
		return Math.fabs(root_x - press_root_x) >= threshold || Math.fabs(root_y - press_root_y) >= threshold;
	}

	// begin starts moving the selected items
	public void begin(List<DesktopItem> selected) {
		active = true;
		items = new GenericArray<DesktopItem>();

		foreach (DesktopItem item in selected) {
			if (item.grid_pos != null) items.add(item); // Not placed yet, so there is nothing to move it from
		}
	}

	// moves returns whether an item is one of the items being dragged
	public bool moves(DesktopItem item) {
		uint index;
		return items.find(item, out index);
	}

	// update tracks the pointer, converting the pixel offset to cells for the drop
	public void update(double root_x, double root_y, int cell_width, int cell_height) {
		delta_x = root_x - press_root_x;
		delta_y = root_y - press_root_y;
		delta_col = delta_x / cell_width;
		delta_row = delta_y / cell_height;
	}

	// snap_targets returns the cell each item would snap to if dropped now. Collisions are resolved on drop, so the result can differ.
	public GenericArray<GridPos> snap_targets() {
		var targets = new GenericArray<GridPos>();

		for (int i = 0; i < items.length; i++) {
			GridPos from = items[i].grid_pos; // Still the pre-drag position; the canvas only moves the widget
			targets.add(new GridPos(from.col + delta_col, from.row + delta_row).rounded());
		}

		return targets;
	}

	// forget drops an item that left the canvas mid-drag, e.g. a file deleted by another app
	public void forget(DesktopItem item) {
		items.remove(item);
		if (press_item == item) press_item = null;
		if (drop_target == item) drop_target = null;
	}

	// reset clears all press and drag state, ready for the next press
	public void reset() {
		press_item = null;
		had_modifier = false;
		active = false;
		drop_target = null;
		items = new GenericArray<DesktopItem>();
		delta_x = delta_y = delta_col = delta_row = 0;
	}
}
