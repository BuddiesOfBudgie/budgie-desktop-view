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

void test_profiles_restore_after_resize() {
	string path = temp_path("layout.gvariant");
	var layout = new DesktopLayout(path);
	layout.activate(20, 10);
	layout.commit(positions({ "a", "b" }, { 3.5, 19 }, { 2, 9 }));

	layout.activate(12, 8);
	assert_true(layout.get_position("b") != null);
	assert_true(layout.get_position("b").col == 11);

	layout.activate(20, 10);
	assert_pos(layout.get_positions(), "a", 3.5, 2);
	assert_pos(layout.get_positions(), "b", 19, 9);

	var reloaded = new DesktopLayout(path);
	reloaded.load();
	assert_true(reloaded.profile_count == 1); // Derived 12x8 was never edited, so never saved
}

void test_assign_does_not_persist_derived() {
	string path = temp_path("layout.gvariant");
	var layout = new DesktopLayout(path);
	layout.activate(20, 10);
	layout.commit(positions({ "a" }, { 0 }, { 0 }));

	layout.activate(12, 8);
	layout.assign(positions({ "new" }, { 1 }, { 0 }));
	assert_pos(layout.get_positions(), "new", 1, 0);

	layout.activate(20, 10);
	layout.assign(positions({ "new" }, { 5 }, { 0 }));

	var reloaded = new DesktopLayout(path);
	reloaded.load();
	assert_true(reloaded.profile_count == 1);
	reloaded.activate(20, 10);
	assert_pos(reloaded.get_positions(), "new", 5, 0); // Persisted profile saves assignments
}

void test_persistence_round_trip() {
	string path = temp_path("layout.gvariant");
	var layout = new DesktopLayout(path);
	layout.activate(8, 6);
	layout.commit(positions({ "file:/home/u/Desktop/a=b [c].txt", "mount:1234" }, { 1.25, 7 }, { 0, 5 }));
	layout.activate(10, 6);
	layout.commit(positions({ "special:home" }, { 0 }, { 0 }));

	var reloaded = new DesktopLayout(path);
	reloaded.load();
	assert_true(reloaded.profile_count == 2);

	reloaded.activate(8, 6);
	assert_pos(reloaded.get_positions(), "file:/home/u/Desktop/a=b [c].txt", 1.25, 0);
	assert_pos(reloaded.get_positions(), "mount:1234", 7, 5);
}

void test_rename_and_remove() {
	string path = temp_path("layout.gvariant");
	var layout = new DesktopLayout(path);
	layout.activate(8, 6);
	layout.commit(positions({ "file:/d/old", "file:/d/gone" }, { 2, 3 }, { 2, 3 }));

	layout.rename("file:/d/old", "file:/d/new");
	layout.remove("file:/d/gone");

	var reloaded = new DesktopLayout(path);
	reloaded.load();
	reloaded.activate(8, 6);
	assert_pos(reloaded.get_positions(), "file:/d/new", 2, 2);
	assert_true(reloaded.get_position("file:/d/old") == null);
	assert_true(reloaded.get_position("file:/d/gone") == null);
}

void test_profile_cap() {
	string path = temp_path("layout.gvariant");
	var layout = new DesktopLayout(path);

	for (int i = 1; i <= DesktopLayout.MAX_PROFILES + 3; i++) {
		layout.activate(i, i);
		layout.commit(positions({ "a" }, { 0 }, { 0 }));
	}

	var reloaded = new DesktopLayout(path);
	reloaded.load();
	assert_true(reloaded.profile_count == DesktopLayout.MAX_PROFILES);
}

void test_corrupt_file_is_ignored() {
	string path = temp_path("layout.gvariant");
	try {
		FileUtils.set_contents(path, "not a variant");
	} catch (Error e) {
		error("%s", e.message);
	}

	var layout = new DesktopLayout(path);
	Test.expect_message(null, LogLevelFlags.LEVEL_WARNING, "*Failed to parse layout file*");
	layout.load();
	Test.assert_expected_messages();
	assert_true(layout.profile_count == 0);
}

void add_desktop_layout_tests() {
	Test.add_func("/layout/store/profiles-restore", test_profiles_restore_after_resize);
	Test.add_func("/layout/store/assign", test_assign_does_not_persist_derived);
	Test.add_func("/layout/store/round-trip", test_persistence_round_trip);
	Test.add_func("/layout/store/rename-remove", test_rename_and_remove);
	Test.add_func("/layout/store/profile-cap", test_profile_cap);
	Test.add_func("/layout/store/corrupt-file", test_corrupt_file_is_ignored);
}
