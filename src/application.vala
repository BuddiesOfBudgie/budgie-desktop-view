/*
Copyright 2022 Buddies of Budgie
Copyright 2021 Solus Project

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

using Gtk;

public class BudgieDesktopViewApp : Gtk.Application {
	public BudgieDesktopViewApp () {
		Object (application_id: "us.getsol.budgie-desktop-view", flags: ApplicationFlags.FLAGS_NONE);
	}

	protected override void activate() {
		DesktopView view = new DesktopView(this); // Create our new DesktopView
		view.show_all(); // Show the window
	}

	public static int main (string[] args) {
		BudgieDesktopViewApp app = new BudgieDesktopViewApp();
		return app.run(args);
	}
}