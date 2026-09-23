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

// CopyName picks the name a dropped file gets when the Desktop already has one by that name
namespace CopyName {
	public delegate bool TakenFunc(string name);

	// next_free adds " (Copy)" before the extension, repeating until taken says the name is free,
	// e.g. "a.txt" becomes "a (Copy).txt", then "a (Copy) (Copy).txt"
	public string next_free(string name, TakenFunc taken) {
		string candidate = name;

		do {
			candidate = add_suffix(candidate);
		} while (taken(candidate));

		return candidate;
	}

	// add_suffix inserts " (Copy)" before the last extension, or at the end when there isn't one
	public string add_suffix(string name) {
		int last_dot_pos = name.last_index_of(".");
		if (last_dot_pos == -1) return name + " (Copy)";

		return name.substring(0, last_dot_pos) + " (Copy)" + name.substring(last_dot_pos);
	}
}
