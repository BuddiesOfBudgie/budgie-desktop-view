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

void test_suffix_before_extension() {
	assert_true(CopyName.add_suffix("notes.txt") == "notes (Copy).txt");
	assert_true(CopyName.add_suffix("archive.tar.gz") == "archive.tar (Copy).gz"); // Only the last extension is kept separate
}

void test_suffix_without_extension() {
	assert_true(CopyName.add_suffix("README") == "README (Copy)");
}

void test_next_free_first_copy() {
	string name = CopyName.next_free("notes.txt", (candidate) => false);
	assert_true(name == "notes (Copy).txt");
}

void test_next_free_skips_taken() {
	string[] taken = { "notes (Copy).txt", "notes (Copy) (Copy).txt" };
	string name = CopyName.next_free("notes.txt", (candidate) => candidate in taken);
	assert_true(name == "notes (Copy) (Copy) (Copy).txt");
}

public static int main(string[] args) {
	Test.init(ref args);

	Test.add_func("/sources/copy-name/suffix-extension", test_suffix_before_extension);
	Test.add_func("/sources/copy-name/suffix-no-extension", test_suffix_without_extension);
	Test.add_func("/sources/copy-name/first-copy", test_next_free_first_copy);
	Test.add_func("/sources/copy-name/skips-taken", test_next_free_skips_taken);

	return Test.run();
}
