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

void test_legacy_order() {
	string path = temp_path("icon-positions.conf");
	try {
		FileUtils.set_contents(path, "# header\n\nfile:/d/b=2\nspecial:home=0\nfile:/d/x=y=1\nbad line\nfile:/d/neg=-1\n");
	} catch (Error e) {
		error("%s", e.message);
	}

	string[] order = LegacyPositions.read_order(path);
	assert_true(order.length == 3);
	assert_true(order[0] == "special:home");
	assert_true(order[1] == "file:/d/x=y");
	assert_true(order[2] == "file:/d/b");
}

void add_legacy_positions_tests() {
	Test.add_func("/layout/legacy/order", test_legacy_order);
}
