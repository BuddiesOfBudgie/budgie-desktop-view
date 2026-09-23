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

// ItemSelection tracks which items are selected and which one keyboard navigation continues from
public class ItemSelection {
	private GenericSet<DesktopItem> items; // Compared by identity, not by name
	public DesktopItem? cursor = null; // Last item the user selected; arrow keys move from here

	public ItemSelection() {
		items = new GenericSet<DesktopItem>(direct_hash, direct_equal);
	}

	public bool contains(DesktopItem item) {
		return items.contains(item);
	}

	// mark changes selection state without moving the cursor, e.g. while a rubber band sweeps over items
	public void mark(DesktopItem item, bool is_selected) {
		if (is_selected) {
			items.add(item);
		} else {
			items.remove(item);
		}

		item.is_selected = is_selected; // Drives the :selected CSS state
	}

	// select adds an item and makes it the keyboard cursor
	public void select(DesktopItem item) {
		mark(item, true);
		cursor = item;
	}

	// toggle flips an item's selection, as Ctrl+click does
	public void toggle(DesktopItem item) {
		if (contains(item)) {
			mark(item, false); // The cursor stays put so arrow keys continue from the same place
		} else {
			select(item);
		}
	}

	// clear unselects everything; the cursor stays so arrow keys continue from the same place
	public void clear() {
		items.foreach((item) => item.is_selected = false);
		items.remove_all();
	}

	// forget drops every reference to an item that is leaving the canvas
	public void forget(DesktopItem item) {
		mark(item, false);
		if (cursor == item) cursor = null;
	}

	// copy returns the current selection, used as the base a Ctrl/Shift rubber band adds to
	public GenericSet<DesktopItem> copy() {
		var snapshot = new GenericSet<DesktopItem>(direct_hash, direct_equal);
		items.foreach((item) => snapshot.add(item));
		return snapshot;
	}
}
