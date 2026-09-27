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

using Gdk;
using Gtk;

// DesktopCanvas places DesktopItems on the grid and routes left-button input to selection, rubber band and drag handling
public class DesktopCanvas : Gtk.Fixed {
	private unowned UnifiedProps props;
	private ItemSelection selection;
	private RubberBand band; // Active while dragging from empty space
	private DragMove drag; // Active from a press on an item until its release

	// Pixel size of one grid cell; follows the icon size setting
	public int cell_width { get; private set; default = 1; }
	public int cell_height { get; private set; default = 1; }
	public bool snap_to_grid { get; set; default = true; } // Bound to the snap-to-grid setting by the view
	public DesktopItem? trash_item { get; set; default = null; } // Dropping dragged items on it trashes them instead of moving them

	// RoomFunc returns the new cell of every item that moves when the dragged items are inserted at the line above
	// cell, or null when they don't fit. The arranger provides it, since it knows the grid size.
	public delegate HashTable<DesktopItem, GridPos>? RoomFunc(GenericArray<DesktopItem> items, GridPos cell);
	private RoomFunc? room_func = null;

	// items_moved reports a finished drag; the view resolves collisions and saves the result. room is empty unless the
	// drop made room, in which case it holds where every moving item goes.
	public signal void items_moved(GenericArray<DesktopItem> items, double delta_col, double delta_row, HashTable<DesktopItem, GridPos> room);

	// items_trashed reports a drag dropped on the Trash item; the view trashes the items that can be
	public signal void items_trashed(GenericArray<DesktopItem> items);

	// items_dropped_into reports a drag dropped on a folder; the view moves the items that can be into it
	public signal void items_dropped_into(GenericArray<DesktopItem> items, DesktopItem folder);

	public DesktopCanvas(UnifiedProps p) {
		Object();
		props = p;
		selection = new ItemSelection();
		band = new RubberBand();
		drag = new DragMove();

		// Own window so presses on empty space reach us for the rubber band
		set_has_window(true);
		add_events(EventMask.BUTTON_PRESS_MASK | EventMask.BUTTON_RELEASE_MASK | EventMask.BUTTON_MOTION_MASK |
			EventMask.SCROLL_MASK | EventMask.SMOOTH_SCROLL_MASK); // Scrolls over items reach us too; they don't select them
	}

	public void set_cell_size(int width, int height) {
		cell_width = int.max(width, 1);
		cell_height = int.max(height, 1);
	}

	public void set_room_func(owned RoomFunc func) {
		room_func = (owned) func;
	}

	// place moves an item to a grid position, sizing it to fill one cell
	public void place(DesktopItem item, GridPos pos) {
		item.grid_pos = pos;
		item.set_size_request(cell_width - ITEM_MARGIN * 2, cell_height - ITEM_MARGIN * 2); // The item's own margin fills the rest of the cell
		show_at(item, pos);
	}

	// show_at moves an item's widget onto a cell without changing its grid position
	private void show_at(DesktopItem item, GridPos pos) {
		int x, y;
		item_origin(item, pos, out x, out y);
		move(item, x, y);
	}

	// item_origin returns where to put an item so it's centered on the cell at pos.
	// Its label's minimum width can make an item wider than the size request, so the offset comes from its real size.
	private void item_origin(DesktopItem item, GridPos pos, out int x, out int y) {
		Requisition size;
		item.get_preferred_size(null, out size); // Includes the item's margin
		x = col_to_x(pos.col) + (cell_width - size.width) / 2;
		y = row_to_y(pos.row) + (cell_height - size.height) / 2;
	}

	// col_to_x converts a column to a pixel offset; MARGIN keeps the first column off the screen edge
	private int col_to_x(double col) {
		return MARGIN + (int) Math.round(col * cell_width);
	}

	// row_to_y converts a row to a pixel offset
	private int row_to_y(double row) {
		return (int) Math.round(row * cell_height);
	}

	// grid_pos_at converts a point on the canvas to the position of an item dropped there
	public GridPos grid_pos_at(double x, double y) {
		double col = (x - MARGIN) / cell_width;
		double row = y / cell_height;

		if (snap_to_grid) {
			return new GridPos(Math.floor(col), Math.floor(row)); // The cell under the pointer
		}

		return new GridPos(col - 0.5, row - 0.5); // Center the item on the pointer
	}

	// remove also drops the item from selection and drag state, so neither holds a widget that is gone
	public override void remove(Widget widget) {
		if (widget is DesktopItem) {
			selection.forget((DesktopItem) widget);
			drag.forget((DesktopItem) widget);
		}

		base.remove(widget);
	}

	// get_items returns every item on the canvas, shown or hidden
	public List<DesktopItem> get_items() {
		var items = new List<DesktopItem>();
		foreach (Widget child in get_children()) {
			if (child is DesktopItem) items.append((DesktopItem) child);
		}
		return items;
	}

	// get_selected returns the selected items that are currently shown
	public List<DesktopItem> get_selected() {
		var items = new List<DesktopItem>();
		foreach (DesktopItem item in get_items()) {
			if (selection.contains(item) && item.get_visible()) items.append(item);
		}
		return items;
	}

	// get_cursor_item returns where keyboard navigation continues from, if that item is still shown
	private DesktopItem? get_cursor_item() {
		DesktopItem? cursor = selection.cursor;
		return (cursor != null && cursor.get_visible()) ? cursor : null; // A hidden cursor would send arrows off-screen
	}

	// select adds an item to the selection
	public void select(DesktopItem item) {
		selection.select(item);
	}

	public void unselect(DesktopItem item) {
		selection.mark(item, false);
	}

	// select_only replaces the selection with a single item
	public void select_only(DesktopItem item) {
		clear_selection();
		selection.select(item);
	}

	// select_all selects every shown item; hidden overflow items are left alone
	public void select_all() {
		foreach (DesktopItem item in get_items()) {
			if (item.get_visible()) selection.mark(item, true);
		}
	}

	// clear_selection unselects every item, including hidden ones
	public void clear_selection() {
		selection.clear();
	}

	// navigate selects the nearest shown item in an arrow key's direction. extend adds it to the selection instead.
	public void navigate(uint keyval, bool extend) {
		DesktopItem? from = get_cursor_item();
		DesktopItem? target = (from == null || from.grid_pos == null) ? first_item() : nearest_in_direction(from, keyval);

		if (target == null) return; // Nothing further in that direction

		if (extend) { // Shift+arrow grows the selection
			selection.select(target);
		} else {
			select_only(target);
		}
	}

	// first_item returns the top-left shown item, where keyboard navigation starts
	private DesktopItem? first_item() {
		DesktopItem? first = null;

		foreach (DesktopItem item in get_items()) {
			if (!item.get_visible() || item.grid_pos == null) continue;

			// Column-major, matching the order auto-arrange fills the grid in
			if (first == null || item.grid_pos.col < first.grid_pos.col ||
				(item.grid_pos.col == first.grid_pos.col && item.grid_pos.row < first.grid_pos.row)) {
				first = item;
			}
		}

		return first;
	}

	// nearest_in_direction returns the shown item closest to from in an arrow key's direction
	private DesktopItem? nearest_in_direction(DesktopItem from, uint keyval) {
		DesktopItem? target = null;
		double best_score = double.MAX;

		foreach (DesktopItem item in get_items()) {
			if (item == from || !item.get_visible() || item.grid_pos == null) continue;

			// Offset from the cursor in cells, so it works the same for snapped and free-placed items
			double dc = item.grid_pos.col - from.grid_pos.col;
			double dr = item.grid_pos.row - from.grid_pos.row;

			// "along" is distance in the arrow's direction, "across" is sideways drift from it
			double along = 0;
			double across = 0;
			switch (keyval) {
				case Gdk.Key.Left:
					along = -dc;
					across = dr;
					break;
				case Gdk.Key.Right:
					along = dc;
					across = dr;
					break;
				case Gdk.Key.Up:
					along = -dr;
					across = dc;
					break;
				default:
					along = dr;
					across = dc;
					break;
			}

			// Only consider items inside a 45 degree cone, and prefer ones in line with the cursor
			if (along < 0.5 || Math.fabs(across) > along) continue;

			double score = along + Math.fabs(across) * 2; // Drifting sideways costs more than going further
			if (score < best_score) {
				best_score = score;
				target = item;
			}
		}

		return target;
	}

	// cancel_interaction aborts an active drag or rubber band. Returns true if there was one.
	public bool cancel_interaction() {
		if (drag.active) {
			foreach (DesktopItem item in drag.items) {
				place(item, item.grid_pos); // grid_pos still holds the pre-drag position
			}

			show_room(null);
			set_drop_target(null);
			drag.reset();
			queue_draw();
			return true;
		}

		if (band.active) {
			band.cancel();
			queue_draw();
			return true;
		}

		return false;
	}

	// drop_target_at returns the Trash or folder item a drop at these root coordinates lands on, if any.
	// It's a geometric test because the pointer is over the dragged item's widget, and the grab keeps other items from seeing it.
	private DesktopItem? drop_target_at(double root_x, double root_y) {
		double x, y;
		root_to_canvas(root_x, root_y, out x, out y);

		foreach (DesktopItem item in get_items()) {
			if (!item.accepts_drops || !item.get_visible() || item.grid_pos == null) continue;
			if (drag.moves(item)) continue; // Moves with the pointer, so it can't be dropped on

			Gtk.Allocation alloc;
			item.get_allocation(out alloc); // Relative to the canvas window
			if (x >= alloc.x && x < alloc.x + alloc.width && y >= alloc.y && y < alloc.y + alloc.height) return item;
		}

		return null;
	}

	// root_to_canvas converts root coordinates, which stay consistent while dragged widgets move, to canvas coordinates
	private void root_to_canvas(double root_x, double root_y, out double x, out double y) {
		int origin_x, origin_y;
		get_window().get_origin(out origin_x, out origin_y);
		x = root_x - origin_x;
		y = root_y - origin_y;
	}

	// update_insertion makes room for the dragged items while the pointer is near the line between two cells, shifting
	// what's in the way. Moving off the line puts those items back.
	private void update_insertion(double root_x, double root_y) {
		GridPos? cell = snap_to_grid ? insertion_cell(root_x, root_y) : null;
		GridPos? previous = drag.insert_at;

		// Only recompute when the insertion point changes, not on every pixel of movement
		if (cell == null && previous == null) return;
		if (cell != null && previous != null && cell.col == previous.col && cell.row == previous.row) return;

		drag.insert_at = cell;
		HashTable<DesktopItem, GridPos>? room = null;

		if (cell != null && room_func != null) {
			room = room_func(drag.items, cell);
			if (room == null) drag.insert_at = null; // Nowhere to shift to, so the drop resolves collisions as usual
		}

		show_room(room);
	}

	// insertion_cell returns the cell just below the line where a drop inserts the dragged items. Coming within a
	// quarter cell of a line with an item on either side of it starts an insertion there. Null when there's none.
	private GridPos? insertion_cell(double root_x, double root_y) {
		double x, y;
		root_to_canvas(root_x, root_y, out x, out y);

		double col = Math.floor((x - MARGIN) / cell_width);
		double rows_down = y / cell_height;
		double line = Math.round(rows_down); // The line between rows line - 1 and line

		if (Math.fabs(rows_down - line) <= 0.25) {
			foreach (DesktopItem item in get_items()) {
				if (!item.get_visible() || item.grid_pos == null || drag.moves(item)) continue;
				if (item.grid_pos.col != col) continue;
				if (item.grid_pos.row == line || item.grid_pos.row == line - 1) return new GridPos(col, line);
			}
		}

		// Between lines, the last insertion holds until the pointer reaches another line or leaves the cells on either
		// side of it, so shifted items don't jump back mid-cell. A folder or Trash under the pointer takes the drop instead.
		GridPos? active = drag.insert_at;
		if (active != null && active.col == col && Math.fabs(rows_down - active.row) < 1 && drop_target_at(root_x, root_y) == null) {
			return active;
		}

		return null;
	}

	// show_room moves the items a drop would shift to their new cells, and puts ones no longer shifted back on their
	// own. Dragged items stay with the pointer; the snap outlines show where they land.
	private void show_room(HashTable<DesktopItem, GridPos>? room) {
		drag.room.foreach((item, pos) => {
			if (!drag.moves(item) && (room == null || !room.contains(item))) show_at(item, item.grid_pos);
		});

		if (room != null) {
			room.foreach((item, pos) => {
				if (!drag.moves(item)) show_at(item, pos);
			});
		}

		drag.room = room ?? new HashTable<DesktopItem, GridPos>(direct_hash, direct_equal);
		queue_draw();
	}

	// set_drop_target tracks where a drop would move the dragged items. Over a target, the cursor shows whether any of
	// them can be moved there.
	private void set_drop_target(DesktopItem? target) {
		if (drag.drop_target == target) return;

		drag.drop_target = target;

		if (target == null) {
			props.current_cursor = props.hand_cursor;
			return;
		}

		bool any_movable = false;
		foreach (DesktopItem item in drag.items) {
			if (item.is_desktop_file) any_movable = true;
		}

		props.current_cursor = any_movable ? props.drop_cursor : props.blocked_cursor;
	}

	// item_for_event returns the item an event happened on, or null for empty canvas space
	private DesktopItem? item_for_event(Event ev) {
		Widget? widget = Gtk.get_event_widget(ev); // Usually the item's inner event box, not the item itself

		// Walk up to the DesktopItem that owns the widget, stopping at the canvas
		while (widget != null && widget != this) {
			if (widget is DesktopItem) return (DesktopItem) widget;
			widget = widget.get_parent();
		}

		return null;
	}

	// button_press_event starts a rubber band on empty space, or a click/drag on an item
	public override bool button_press_event(EventButton ev) {
		if (ev.button != 1) return Gdk.EVENT_PROPAGATE; // Right click is handled by the items and the window

		DesktopItem? item = item_for_event((Event) ev);
		bool ctrl_down = (ev.state & ModifierType.CONTROL_MASK) != 0;
		bool shift_down = (ev.state & ModifierType.SHIFT_MASK) != 0;

		if (item == null) {
			if (ev.type != EventType.BUTTON_PRESS) return Gdk.EVENT_PROPAGATE;

			// The press landed on our own window, so its coordinates are canvas coordinates
			band.begin(ev.x, ev.y, (ctrl_down || shift_down) ? selection.copy() : null);
			return Gdk.EVENT_STOP;
		}

		// GTK sends a normal press first, then a double press; double-click mode opens on the second
		if (ev.type == EventType.DOUBLE_BUTTON_PRESS) {
			if (!props.is_single_click) item.open();
			return Gdk.EVENT_STOP;
		}

		if (ev.type != EventType.BUTTON_PRESS) return Gdk.EVENT_STOP; // Ignore triple presses

		drag.press(item, ev.x_root, ev.y_root, ctrl_down || shift_down);

		// Selection changes on press, so a drag that starts right away already moves the right items
		if (ctrl_down) {
			selection.toggle(item);
		} else if (shift_down) {
			selection.select(item); // Adds to the selection; there is no range selection on a free-form desktop
		} else if (!selection.contains(item)) {
			select_only(item);
		} else {
			selection.cursor = item; // Keep the selection so a drag can move all of it
		}

		return Gdk.EVENT_STOP;
	}

	// motion_notify_event grows the rubber band or moves dragged items; only sent while the button is held
	public override bool motion_notify_event(EventMotion ev) {
		if (band.active) {
			band.update(ev.x, ev.y); // The band's implicit grab keeps these coordinates relative to the canvas

			// Recompute from scratch each time so items drop out again when the band shrinks
			foreach (DesktopItem item in get_items()) {
				if (!item.get_visible()) continue;

				bool hit = band.selects(item);
				selection.mark(item, hit);
				if (hit) selection.cursor = item;
			}

			queue_draw();
			return Gdk.EVENT_STOP;
		}

		if (drag.press_item == null) return Gdk.EVENT_PROPAGATE; // No press in progress

		if (!drag.active) {
			if (!drag.past_threshold(ev.x_root, ev.y_root)) return Gdk.EVENT_STOP; // Still a click, not a drag

			// A Ctrl-click can deselect the pressed item; dragging it should still move it
			if (!selection.contains(drag.press_item)) selection.select(drag.press_item);
			drag.begin(get_selected());

			// Items added earlier, like Home, stack below Trash, which would put Trash's window under the pointer instead
			foreach (DesktopItem item in drag.items) {
				item.get_window().raise();
			}
		}

		drag.update(ev.x_root, ev.y_root, cell_width, cell_height);
		update_insertion(ev.x_root, ev.y_root);
		set_drop_target(drag.insert_at == null ? drop_target_at(ev.x_root, ev.y_root) : null); // Making room wins near a line

		// Move the widgets only; grid_pos keeps the pre-drag position until the view saves the drop
		foreach (DesktopItem item in drag.items) {
			int x, y;
			item_origin(item, item.grid_pos, out x, out y);
			move(item, x + (int) drag.delta_x, y + (int) drag.delta_y);
		}

		queue_draw(); // Redraw the snap targets
		return Gdk.EVENT_STOP;
	}

	// button_release_event finishes whatever the press started: a band, a drag, or a click
	public override bool button_release_event(EventButton ev) {
		if (ev.button != 1) return Gdk.EVENT_PROPAGATE;

		if (band.active) {
			bool dragged = band.finish();
			queue_draw();

			// An empty-space click without a drag is left to the window, which clears the selection and hides menus
			return dragged ? Gdk.EVENT_STOP : Gdk.EVENT_PROPAGATE;
		}

		DesktopItem? item = drag.press_item;
		if (item == null) return Gdk.EVENT_PROPAGATE;

		DesktopItem? target = (drag.active && drag.insert_at == null) ? drop_target_at(ev.x_root, ev.y_root) : null;
		if (target != null) {
			var dropped = drag.items;

			// Items that can't be moved stay where they were; moved files leave once the Desktop folder sees them go
			foreach (DesktopItem dropped_item in dropped) {
				place(dropped_item, dropped_item.grid_pos);
			}

			set_drop_target(null);
			drag.reset();
			queue_draw(); // Clears the target highlight

			if (target == trash_item) {
				items_trashed(dropped);
			} else {
				items_dropped_into(dropped, target);
			}

			return Gdk.EVENT_STOP;
		}

		if (drag.active) {
			// Reset before emitting so the relayout the handler triggers doesn't draw the old snap outlines
			var moved = drag.items;
			var room = drag.room;
			double delta_col = drag.delta_col;
			double delta_row = drag.delta_row;
			drag.reset();
			queue_draw(); // Clears the snap target outlines

			items_moved(moved, delta_col, delta_row, room);
			return Gdk.EVENT_STOP;
		}

		bool had_modifier = drag.had_modifier;
		drag.reset();

		// A plain click on an already selected item narrows the selection to it
		if (!had_modifier) {
			select_only(item);
			if (props.is_single_click) item.open();
		}

		return Gdk.EVENT_STOP;
	}

	// draw paints the items, then the snap outlines and rubber band on top of them
	public override bool draw(Cairo.Context cr) {
		base.draw(cr); // Draws the child items

		StyleContext ctx = get_style_context();

		// Highlight the drop target in place of the snap outlines, since a drop there moves the items off the desktop
		if (drag.active && drag.drop_target != null) {
			Gtk.Allocation alloc;
			drag.drop_target.get_allocation(out alloc);

			ctx.save();
			ctx.add_class(drag.drop_target == trash_item ? "trash-target" : "folder-target");
			ctx.render_background(cr, alloc.x, alloc.y, alloc.width, alloc.height);
			ctx.render_frame(cr, alloc.x, alloc.y, alloc.width, alloc.height);
			ctx.restore();
		} else if (drag.active && snap_to_grid) { // Outline where each dragged item will land; with snapping off it lands exactly where it is drawn
			ctx.save();
			ctx.add_class("drop-target");

			GenericArray<GridPos> targets = drag.snap_targets(); // Same order as drag.items
			for (int i = 0; i < targets.length; i++) {
				Gtk.Allocation alloc;
				drag.items[i].get_allocation(out alloc);

				int x, y;
				item_origin(drag.items[i], targets[i], out x, out y);
				ctx.render_background(cr, x + ITEM_MARGIN, y + ITEM_MARGIN, alloc.width, alloc.height);
				ctx.render_frame(cr, x + ITEM_MARGIN, y + ITEM_MARGIN, alloc.width, alloc.height);
			}

			ctx.restore();
		}

		if (band.active) band.draw(ctx, cr);

		return Gdk.EVENT_PROPAGATE;
	}
}
