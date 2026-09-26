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

void test_auto_arrange_column_major() {
	var result = LayoutOps.auto_arrange({ "a", "b", "c", "d", "e", "f", "g" }, 2, 3);
	assert_pos(result, "a", 0, 0);
	assert_pos(result, "c", 0, 2);
	assert_pos(result, "d", 1, 0);
	assert_pos(result, "f", 1, 2);
	assert_true(!result.contains("g")); // Past capacity
}

void test_place_resolves_collisions() {
	var known = positions({ "a", "b" }, { 1, 1.5 }, { 1, 1 });
	var result = LayoutOps.place({ "a", "b", "new" }, known, 4, 4);

	assert_pos(result, "a", 1, 1);
	assert_true(result.contains("b"));
	assert_true(result.contains("new"));
	assert_no_overlaps(result);
}

void test_move_keeps_group_shape() {
	var current = positions({ "a", "b", "c" }, { 0, 0, 3 }, { 0, 1, 3 });
	var result = LayoutOps.move(current, { "a", "b" }, 2, 0, true, 5, 5);

	assert_pos(result, "a", 2, 0);
	assert_pos(result, "b", 2, 1);
}

void test_move_free_placement() {
	var current = positions({ "a" }, { 0 }, { 0 });
	var result = LayoutOps.move(current, { "a" }, 1.4, 0.25, false, 5, 5);
	assert_pos(result, "a", 1.4, 0.25);
}

void test_move_collision_goes_to_nearest_free() {
	var current = positions({ "a", "b" }, { 0, 2 }, { 0, 0 });
	var result = LayoutOps.move(current, { "a" }, 2, 0, true, 5, 5);

	GridPos pos = result.get("a");
	assert_true(!LayoutGrid.overlaps(pos, current.get("b")));
	assert_true(Math.fabs(pos.col - 2) + Math.fabs(pos.row) == 1); // Adjacent to the taken cell
}

void test_move_clamps_to_bounds() {
	var current = positions({ "a" }, { 3 }, { 3 });
	var result = LayoutOps.move(current, { "a" }, 10, -10, true, 5, 5);
	assert_pos(result, "a", 4, 0);
}

void test_align_to_grid_prefers_aligned_items() {
	// b is already on (1, 0); a would round onto it and must yield
	var current = positions({ "a", "b" }, { 1.4, 1 }, { 0.3, 0 });
	var result = LayoutOps.align_to_grid(current, { "a", "b" }, 5, 5);

	assert_pos(result, "b", 1, 0);
	assert_no_overlaps(result);
	GridPos a = result.get("a");
	assert_true(a.col == Math.round(a.col) && a.row == Math.round(a.row));
}

void test_sort_in_place_keeps_cells() {
	var current = positions({ "c", "a", "b" }, { 0, 4, 2 }, { 0, 1, 3 });
	var result = LayoutOps.sort_in_place(current, { "a", "b", "c" }, 6, 6);

	assert_pos(result, "a", 0, 0);
	assert_pos(result, "b", 2, 3);
	assert_pos(result, "c", 4, 1);
}

void test_derive_anchors_edges() {
	var source = positions({ "home", "trash", "mid" }, { 0, 19, 18 }, { 0, 9, 1 });
	var result = LayoutOps.derive(source, 20, 10, 12, 8);

	assert_pos(result, "home", 0, 0);
	assert_pos(result, "trash", 11, 7); // Bottom-right stays bottom-right
	assert_pos(result, "mid", 10, 1); // Two from the right, one from the top
	assert_no_overlaps(result);
}

void test_derive_resolves_collisions() {
	var source = positions({ "a", "b" }, { 0, 1 }, { 0, 0 });
	var result = LayoutOps.derive(source, 2, 1, 1, 3);
	assert_no_overlaps(result);
}

void test_make_room_pushes_run_down() {
	var current = positions({ "a", "b", "c", "x" }, { 0, 0, 0, 1 }, { 0, 1, 2, 0 });
	var result = LayoutOps.make_room(current, { "x" }, new GridPos(0, 1), 2, 5);

	assert_true(result.size() == 3); // a is above the line, so it stays
	assert_pos(result, "x", 0, 1);
	assert_pos(result, "b", 0, 2);
	assert_pos(result, "c", 0, 3);
}

void test_make_room_stops_at_gap() {
	var current = positions({ "a", "b", "c", "x" }, { 0, 0, 0, 1 }, { 0, 1, 3, 0 });
	var result = LayoutOps.make_room(current, { "x" }, new GridPos(0, 1), 2, 5);

	assert_true(result.size() == 2);
	assert_pos(result, "b", 0, 2); // Fills the gap at row 2, so c doesn't move
}

void test_make_room_closes_dragged_hole() {
	// Dragging a down past b and c: they move up into a's cell, and a lands between c and d
	var current = positions({ "a", "b", "c", "d" }, { 0, 0, 0, 0 }, { 0, 1, 2, 3 });
	var result = LayoutOps.make_room(current, { "a" }, new GridPos(0, 3), 1, 5);

	assert_true(result.size() == 3); // d is below the line and there's room above it, so it stays
	assert_pos(result, "b", 0, 0);
	assert_pos(result, "c", 0, 1);
	assert_pos(result, "a", 0, 2);
}

void test_make_room_free_cell_above_line() {
	var current = positions({ "a", "c", "x" }, { 0, 0, 1 }, { 0, 2, 0 });
	var result = LayoutOps.make_room(current, { "x" }, new GridPos(0, 2), 2, 5);

	assert_true(result.size() == 1); // Row 1 is free, so nothing moves
	assert_pos(result, "x", 0, 1);
}

void test_make_room_gap_keeps_items_above() {
	// The gap at row 1 stops the closing up, so a stays and b is pushed instead
	var current = positions({ "x", "a", "b" }, { 0, 0, 0 }, { 0, 2, 3 });
	var result = LayoutOps.make_room(current, { "x" }, new GridPos(0, 3), 1, 5);

	assert_true(result.size() == 2);
	assert_pos(result, "x", 0, 3);
	assert_pos(result, "b", 0, 4);
}

void test_make_room_wraps_to_next_column() {
	var current = positions({ "a", "b", "c", "d", "x" }, { 0, 0, 0, 1, 2 }, { 0, 1, 2, 0, 0 });
	var result = LayoutOps.make_room(current, { "x" }, new GridPos(0, 1), 3, 3);

	assert_pos(result, "x", 0, 1);
	assert_pos(result, "b", 0, 2);
	assert_pos(result, "c", 1, 0);
	assert_pos(result, "d", 1, 1);
}

void test_make_room_bottom_line() {
	var current = positions({ "a", "b" }, { 0, 0 }, { 0, 1 });
	var result = LayoutOps.make_room(current, { "a" }, new GridPos(0, 2), 2, 2);

	assert_pos(result, "b", 0, 0);
	assert_pos(result, "a", 0, 1);
}

void test_make_room_full_grid() {
	var current = positions({ "a", "b" }, { 0, 0 }, { 0, 1 });
	assert_true(LayoutOps.make_room(current, { "x" }, new GridPos(0, 1), 1, 2) == null);
}

void test_make_room_several_items() {
	var current = positions({ "a", "b", "c", "y", "x" }, { 0, 0, 0, 1, 1 }, { 0, 1, 2, 3, 2 });
	var result = LayoutOps.make_room(current, { "y", "x" }, new GridPos(0, 0), 2, 4);

	assert_pos(result, "x", 0, 0); // x came before y in fill order, so it stays first
	assert_pos(result, "y", 0, 1);
	assert_pos(result, "a", 0, 2);
	assert_pos(result, "b", 0, 3);
	assert_pos(result, "c", 1, 0);
}

void test_make_room_off_grid() {
	var current = positions({ "a" }, { 0 }, { 0 });
	assert_true(LayoutOps.make_room(current, { "x" }, new GridPos(2, 0), 2, 5) == null);
}

void add_layout_ops_tests() {
	Test.add_func("/layout/ops/auto-arrange", test_auto_arrange_column_major);
	Test.add_func("/layout/ops/place-collisions", test_place_resolves_collisions);
	Test.add_func("/layout/ops/move-group", test_move_keeps_group_shape);
	Test.add_func("/layout/ops/move-free", test_move_free_placement);
	Test.add_func("/layout/ops/move-collision", test_move_collision_goes_to_nearest_free);
	Test.add_func("/layout/ops/move-clamp", test_move_clamps_to_bounds);
	Test.add_func("/layout/ops/align-grid", test_align_to_grid_prefers_aligned_items);
	Test.add_func("/layout/ops/sort-in-place", test_sort_in_place_keeps_cells);
	Test.add_func("/layout/ops/derive-anchors", test_derive_anchors_edges);
	Test.add_func("/layout/ops/derive-collisions", test_derive_resolves_collisions);
	Test.add_func("/layout/ops/make-room-run", test_make_room_pushes_run_down);
	Test.add_func("/layout/ops/make-room-gap", test_make_room_stops_at_gap);
	Test.add_func("/layout/ops/make-room-close-hole", test_make_room_closes_dragged_hole);
	Test.add_func("/layout/ops/make-room-free-above", test_make_room_free_cell_above_line);
	Test.add_func("/layout/ops/make-room-gap-above", test_make_room_gap_keeps_items_above);
	Test.add_func("/layout/ops/make-room-wrap", test_make_room_wraps_to_next_column);
	Test.add_func("/layout/ops/make-room-bottom", test_make_room_bottom_line);
	Test.add_func("/layout/ops/make-room-full", test_make_room_full_grid);
	Test.add_func("/layout/ops/make-room-several", test_make_room_several_items);
	Test.add_func("/layout/ops/make-room-off-grid", test_make_room_off_grid);
}
