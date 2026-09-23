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

	// items_moved reports a finished drag; the view resolves collisions and saves the result
	public signal void items_moved(GenericArray<DesktopItem> items, double delta_col, double delta_row);

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

	// place moves an item to a grid position, sizing it to fill one cell
	public void place(DesktopItem item, GridPos pos) {
		item.grid_pos = pos;
		item.set_size_request(cell_width - ITEM_MARGIN * 2, cell_height - ITEM_MARGIN * 2); // The item's own margin fills the rest of the cell
		move(item, col_to_x(pos.col), row_to_y(pos.row));
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
			for (int i = 0; i < drag.items.length; i++) {
				place(drag.items[i], drag.items[i].grid_pos); // grid_pos still holds the pre-drag position
			}

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
		}

		drag.update(ev.x_root, ev.y_root, cell_width, cell_height);

		// Move the widgets only; grid_pos keeps the pre-drag position until the view saves the drop
		for (int i = 0; i < drag.items.length; i++) {
			DesktopItem item = drag.items[i];
			move(item, col_to_x(item.grid_pos.col) + (int) drag.delta_x, row_to_y(item.grid_pos.row) + (int) drag.delta_y);
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

		if (drag.active) {
			// Reset before emitting so the relayout the handler triggers doesn't draw the old snap outlines
			var moved = drag.items;
			double delta_col = drag.delta_col;
			double delta_row = drag.delta_row;
			drag.reset();
			queue_draw(); // Clears the snap target outlines

			items_moved(moved, delta_col, delta_row);
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

		// Outline where each dragged item will land; with snapping off it lands exactly where it is drawn
		if (drag.active && snap_to_grid) {
			ctx.save();
			ctx.add_class("drop-target");

			GenericArray<GridPos> targets = drag.snap_targets();
			for (int i = 0; i < targets.length; i++) {
				ctx.render_frame(cr, col_to_x(targets[i].col) + ITEM_MARGIN, row_to_y(targets[i].row) + ITEM_MARGIN, cell_width - ITEM_MARGIN * 2, cell_height - ITEM_MARGIN * 2);
			}

			ctx.restore();
		}

		if (band.active) band.draw(ctx, cr);

		return Gdk.EVENT_PROPAGATE;
	}
}
