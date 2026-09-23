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

// DesktopArranger decides where every item on the canvas goes, and keeps the saved layout in step with what the user does
public class DesktopArranger : Object {
	// ShownItemsFunc returns the items that should be on screen, in any order
	public delegate GenericArray<DesktopItem> ShownItemsFunc();

	private DesktopCanvas canvas;
	private DesktopLayout layout;
	private GLib.Settings settings;
	private ShownItemsFunc shown_items;
	private HashTable<string, GridPos> pending_drops; // Where files dropped in from other apps should appear, by layout id
	private string? legacy_path = null; // A 10.10.x icon-positions.conf still waiting to be imported

	// Usable screen area in pixels; zero until the view knows the monitor
	private int screen_width = 0;
	private int screen_height = 0;

	public bool auto_arrange { get; private set; }
	public ItemSortKey sort_key { get; private set; } // The order auto-arrange uses, from the arrange-order setting

	public DesktopArranger(DesktopCanvas canvas, string layout_path, GLib.Settings settings, owned ShownItemsFunc shown_items) {
		this.canvas = canvas;
		this.settings = settings;
		this.shown_items = (owned) shown_items;
		pending_drops = new HashTable<string, GridPos>(str_hash, str_equal);

		layout = new DesktopLayout(layout_path);
		layout.load();

		auto_arrange = settings.get_boolean("auto-arrange");
		sort_key = (ItemSortKey) settings.get_enum("arrange-order");
		settings.changed["auto-arrange"].connect(on_auto_arrange_changed);
		settings.changed["arrange-order"].connect(on_arrange_order_changed);
		settings.changed["snap-to-grid"].connect(relayout); // Turning snapping on aligns anything between cells

		canvas.items_moved.connect(on_items_moved);
	}

	// ordered_items returns the items that should be shown, in the current arrange order
	private GenericArray<DesktopItem> ordered_items() {
		GenericArray<DesktopItem> shown = shown_items();
		shown.sort_with_data((a, b) => ItemOrder.compare_by(sort_key, a, b));
		return shown;
	}

	// layout_ids returns the items' layout ids, in the same order
	private string[] layout_ids(GenericArray<DesktopItem> items) {
		string[] ids = {};
		for (int i = 0; i < items.length; i++) {
			ids += items[i].layout_id;
		}
		return ids;
	}

	// set_geometry updates the screen area and cell size. The next relayout picks the layout profile for the resulting grid.
	public void set_geometry(int width, int height, int cell_width, int cell_height) {
		screen_width = width;
		screen_height = height;
		canvas.set_cell_size(cell_width, cell_height);
	}

	// relayout positions every item for the current grid and settings, hiding items that don't fit.
	// Called after anything that can change what is shown or where: files, mounts, settings, resolution, icon size.
	public void relayout() {
		if (screen_width == 0) return; // Too early in startup to know the screen size

		update_grid(); // Picks up resolution and icon size changes before anything is placed

		// The import needs the grid size, which is only known from the first allocation
		if (legacy_path != null && migrate_legacy(legacy_path)) legacy_path = null;

		// Identifiers of every item that should be shown, in arrange order. In manual mode the order still decides
		// which items claim a contested spot first and where new items go.
		string[] ids = layout_ids(ordered_items());

		HashTable<string, GridPos> placements; // Item id to final position; missing means hidden

		if (auto_arrange) {
			placements = LayoutOps.auto_arrange(ids, layout.cols, layout.rows);

			foreach (string id in ids) {
				pending_drops.remove(id); // Auto-arrange decides where dropped files go
			}
		} else {
			// Saved positions first; items without one fill the first free cells
			placements = LayoutOps.place(ids, layout.get_positions(), layout.cols, layout.rows);
			var dropped = apply_pending_drops(ids, placements); // Overrides the fill spot for files dropped from other apps

			// Remember where brand-new items went, so they don't move when something else changes
			var assigned = new HashTable<string, GridPos>(str_hash, str_equal);
			foreach (string id in ids) {
				if (dropped.contains(id)) continue;
				if (layout.get_position(id) == null && placements.contains(id)) assigned.set(id, placements.get(id));
			}

			if (dropped.size() > 0) layout.commit(dropped); // The user chose these spots, so they persist
			if (assigned.size() > 0) layout.assign(assigned); // New items keep the spot they were given

			if (canvas.snap_to_grid) snap_placements(placements);
		}

		// Apply the result to every item, including ones that shouldn't be shown
		foreach (DesktopItem item in canvas.get_items()) {
			GridPos? pos = placements.get(item.layout_id);

			if (pos == null) { // Hidden by settings or doesn't fit
				canvas.unselect(item); // Hidden items must not be acted on by Delete or Enter
				item.hide();
				continue;
			}

			canvas.place(item, pos);
			item.request_show();
		}
	}

	// snap_placements aligns every placed item that sits between cells, updating placements and saving the result.
	// Items land between cells when they were moved with snapping off, so this runs when it's turned back on.
	private void snap_placements(HashTable<string, GridPos> placements) {
		string[] off_grid = {};
		placements.foreach((id, pos) => {
			if (pos.col != Math.round(pos.col) || pos.row != Math.round(pos.row)) off_grid += id;
		});

		if (off_grid.length == 0) return; // The usual case: everything is already on a cell

		// Aligned items keep their cells; only the off-grid ones move, each to its nearest free cell
		var aligned = LayoutOps.align_to_grid(placements, off_grid, layout.cols, layout.rows);
		aligned.foreach((id, pos) => placements.set(id, pos));
		layout.commit(aligned);
	}

	// update_grid activates the layout profile for the grid the screen fits at the current cell size
	private void update_grid() {
		// The first column starts MARGIN in from the left edge, and the last one needs the same room on the right
		int cols = int.max((screen_width - MARGIN * 2) / canvas.cell_width, 1);
		int rows = int.max(screen_height / canvas.cell_height, 1);

		// Only switch profiles when the grid actually changed, e.g. not when the icon theme did
		if (cols != layout.cols || rows != layout.rows) {
			layout.activate(cols, rows);
		}
	}

	// expect_drop records where a file being dropped in should appear once the Desktop folder picks it up
	public void expect_drop(File target, GridPos pos) {
		pending_drops.set(FileItem.layout_id_for(target), pos);
	}

	// apply_pending_drops moves newly appeared items to where they were dropped, updating placements
	private HashTable<string, GridPos> apply_pending_drops(string[] ids, HashTable<string, GridPos> placements) {
		var dropped = new HashTable<string, GridPos>(str_hash, str_equal);
		string[] dropped_ids = {};

		// Only items that are new to this layout; a file that already has a saved spot keeps it
		foreach (string id in ids) {
			if (pending_drops.contains(id) && layout.get_position(id) == null) dropped_ids += id;
		}

		if (dropped_ids.length == 0) return dropped;

		// place() gave these items a first-free spot; ignore it so they only compete with everything else
		var grid = new LayoutGrid(layout.cols, layout.rows);
		placements.foreach((id, pos) => {
			if (!(id in dropped_ids)) grid.occupy(pos);
		});

		foreach (string id in dropped_ids) {
			GridPos? claimed = grid.claim(pending_drops.get(id)); // Several files dropped together spread out from the drop point
			pending_drops.remove(id);

			if (claimed == null) continue; // Grid is full; keep the spot place() gave it, if any
			placements.set(id, claimed);
			dropped.set(id, claimed);
		}

		return dropped;
	}

	// file_renamed moves a file's saved positions to its new name
	public void file_renamed(File from, File to) {
		layout.rename(FileItem.layout_id_for(from), FileItem.layout_id_for(to));
	}

	// file_deleted drops a file's saved positions
	public void file_deleted(File file) {
		layout.remove(FileItem.layout_id_for(file));
	}

	// current_positions returns the id and position of every shown item, as laid out right now
	private HashTable<string, GridPos> current_positions() {
		var current = new HashTable<string, GridPos>(str_hash, str_equal);

		foreach (DesktopItem item in canvas.get_items()) {
			if (item.get_visible() && item.grid_pos != null) current.set(item.layout_id, item.grid_pos);
		}

		return current;
	}

	// on_items_moved saves the result of a drag on the canvas
	private void on_items_moved(GenericArray<DesktopItem> items, double delta_col, double delta_row) {
		var current = current_positions(); // Pre-drag positions; the canvas only moved the widgets

		// Applies the delta to each item and sends any that land on another item to the nearest free cell
		var moved = LayoutOps.move(current, layout_ids(items), delta_col, delta_row, canvas.snap_to_grid, layout.cols, layout.rows);
		apply_arrangement(current, moved);
	}

	// align_to_grid moves the given items, or every shown item when none are given, to their nearest free cells
	public void align_to_grid(List<DesktopItem> selected) {
		if (auto_arrange) return; // Auto-arrange only ever uses whole cells, so there's nothing to align

		var current = current_positions();
		string[] ids = layout_ids(arrange_targets(selected));
		apply_arrangement(current, LayoutOps.align_to_grid(current, ids, layout.cols, layout.rows));
	}

	// sort makes key the arrange order. With auto-arrange on, that alone re-sorts the desktop and keeps it sorted.
	// With it off, the given items (or every shown item) are also reordered once, within the cells they occupy.
	public void sort(List<DesktopItem> selected, ItemSortKey key) {
		settings.set_enum("arrange-order", key); // on_arrange_order_changed relayouts when auto-arrange is on
		if (auto_arrange) return;

		var current = current_positions();
		GenericArray<DesktopItem> targets = arrange_targets(selected);
		targets.sort_with_data((a, b) => ItemOrder.compare_by(key, a, b));

		apply_arrangement(current, LayoutOps.sort_in_place(current, layout_ids(targets), layout.cols, layout.rows));
	}

	// arrange_targets is what Align and Sort act on: the selection if there is one, otherwise the whole desktop.
	// Items that didn't fit on screen are left out, since they have no position to arrange from.
	private GenericArray<DesktopItem> arrange_targets(List<DesktopItem> selected) {
		var placed = new GenericArray<DesktopItem>();

		if (selected.length() > 0) {
			foreach (DesktopItem item in selected) {
				if (item.get_visible() && item.grid_pos != null) placed.add(item);
			}
			return placed;
		}

		GenericArray<DesktopItem> shown = shown_items();
		for (int i = 0; i < shown.length; i++) {
			if (shown[i].get_visible() && shown[i].grid_pos != null) placed.add(shown[i]);
		}

		return placed;
	}

	// apply_arrangement saves a user's rearrangement and lays it out. current is every shown item's position beforehand.
	private void apply_arrangement(HashTable<string, GridPos> current, HashTable<string, GridPos> changed) {
		// When auto-arrange was on, everything else is saved where it is so only the changed items move
		if (auto_arrange) {
			changed.foreach((id, pos) => current.set(id, pos));
			layout.commit(current);
			switch_to_manual();
		} else {
			layout.commit(changed);
		}

		relayout(); // Moves the widgets to their final, collision-free positions
	}

	// switch_to_manual turns auto-arrange off after the caller has saved the positions manual mode should start from
	private void switch_to_manual() {
		auto_arrange = false; // Before the setting, so on_auto_arrange_changed sees nothing to do
		settings.set_boolean("auto-arrange", false);
	}

	// on_auto_arrange_changed handles changes to the auto-arrange setting, from the desktop menu or elsewhere
	private void on_auto_arrange_changed() {
		bool value = settings.get_boolean("auto-arrange");
		if (value == auto_arrange) return; // switch_to_manual() sets the field before the setting, so there's nothing left to do

		// Turning it off keeps the desktop as it looks now; the widgets still hold the auto layout at this point
		if (!value) layout.commit(current_positions());

		auto_arrange = value;
		relayout();
	}

	// on_arrange_order_changed handles changes to the arrange-order setting, from Sort By or elsewhere
	private void on_arrange_order_changed() {
		sort_key = (ItemSortKey) settings.get_enum("arrange-order");

		// Manual layouts keep their positions; the new order only applies when something is sorted or auto-arrange is on
		if (auto_arrange) relayout();
	}

	// import_legacy queues a 10.10.x icon-positions.conf for import on the next layout pass, if there's no new layout yet
	public void import_legacy(string path) {
		if (layout.file_exists() || !FileUtils.test(path, FileTest.EXISTS)) return; // Only once, before any new layout exists
		legacy_path = path;
	}

	// migrate_legacy imports the order from an icon-positions.conf into the active grid. Returns false when it should be
	// tried again later.
	private bool migrate_legacy(string path) {
		string[] legacy_order = LegacyPositions.read_order(path);
		if (legacy_order.length == 0) return true; // Nothing usable in it

		string[] present = layout_ids(ordered_items());
		if (present.length == 0) return false; // Icons are turned off; try again once they're shown

		// Items from the old file come first in their saved order; deleted files would leave gaps, so skip them
		string[] ids = {};
		foreach (string id in legacy_order) {
			if (id in present) ids += id;
		}

		// Items the old file never saw follow in auto-arrange order
		foreach (string id in present) {
			if (!(id in ids)) ids += id;
		}

		layout.commit(LayoutOps.auto_arrange(ids, layout.cols, layout.rows));
		switch_to_manual(); // A positions file meant manual mode; the relayout that called us picks this up
		return true;
	}
}
