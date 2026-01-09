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

public class DesktopItem : FlowBoxChild {
	protected unowned UnifiedProps props;
	protected int _label_width;
	protected bool _copying;
	protected bool _mount;
	protected string _name;
	protected string _type;
	protected bool _special_dir;

	protected Image? image;
	protected Label? label;
	protected EventBox event_box;
	protected Box main_layout;

	protected Pixbuf? original_image_pixbuf;

	public Icon? icon;

	public DesktopItem() {
		Object(); // Create our DesktopItem as a FlowBoxChild
		get_style_context().add_class("desktop-item");
		expand = true; // Expand when possible
		margin = ITEM_MARGIN;
		set_no_show_all(true);
		valign = Align.CENTER; // Center naturally, don't fill up space

		_copying = false;
		_special_dir = false; // This DesktopItem isn't special.

		event_box = new EventBox();

		main_layout = new Box(Orientation.VERTICAL, 0); // Create a box with a vertical layout and no spacing
		main_layout.sensitive = true;

		label = new Label(null);
		label.get_style_context().add_class("desktop-item-label");
		label.ellipsize = Pango.EllipsizeMode.END; // Ellipsize end
		label.justify = Gtk.Justification.CENTER;
		label.lines = 2; // Anything longer is just kinda overkill IMO
		label.wrap_mode = Pango.WrapMode.WORD_CHAR; // Wrap on characters
		label.wrap = true;

		main_layout.pack_end(label, true, true, 0); // Add the label
		event_box.add(main_layout);

		add(event_box);
		event_box.set_events(EventMask.BUTTON_PRESS_MASK & EventMask.ENTER_NOTIFY_MASK & EventMask.LEAVE_NOTIFY_MASK);
		event_box.enter_notify_event.connect(on_enter);
		event_box.leave_notify_event.connect(on_leave);
	}

	public bool is_copying {
		public get {
			return _copying;
		}

		public set {
			_copying = value;
			has_tooltip = value;
			saturate_image(_copying ? (float) 0.5 : (float) 1.0);

			if (_copying) {
				label.get_style_context().add_class("is-disabled");
				set_tooltip_text(_("File currently copying"));
			} else {
				label.get_style_context().remove_class("is-disabled");
				set_tooltip_text(""); // Clear tooltip
			}

			queue_draw();
		}
	}

	public bool is_mount {
		public get {
			return _mount;
		}

		public set {
			_mount = value;
		}
	}

	public bool is_special {
		public get {
			return _special_dir;
		}

		public set {
			_special_dir = value;
		}
	}

	public string item_type {
		public get {
			return _type;
		}
	}

	public string label_name {
		public get {
			return _name;
		}

		public set {
			_name = value;
			label.set_text(value);
		}
	}

	// on_enter handles mouse entry
	private bool on_enter(EventCrossing event) {
		if (event.mode != Gdk.CrossingMode.NORMAL) return EVENT_STOP;

		get_style_context().add_class("selected");

		if (_copying) { // Currently copying
			props.current_cursor = props.blocked_cursor;
		}

		return EVENT_STOP;
	}

	// on_leave handles mouse leaving
	private bool on_leave(EventCrossing event) {
		if (event.mode != Gdk.CrossingMode.NORMAL) return EVENT_STOP;

		get_style_context().remove_class("selected");

		if (!props.is_launching) props.current_cursor = props.hand_cursor;

		return EVENT_STOP;
	}

	// request_show will request showing specific elements
	public void request_show() {
		show();
		main_layout.show();
		event_box.show();

		if (image != null) {
			image.show();
		}

		if (label != null) {
			label.show();
		}
	}

	// saturate_image will set the saturation of an image
	// This will always be based on the "original" pixbuf
	public void saturate_image(float val) {
		if (image == null) { // If the image does not exist
			return;
		}

		Pixbuf? saturated_pixbuf = original_image_pixbuf.copy();
		original_image_pixbuf.saturate_and_pixelate(saturated_pixbuf, val, false);

		image.set_from_pixbuf(saturated_pixbuf);
	}

	// set_icon is responsible for setting an Icon Theme's representation of an Icon
	public void set_icon(Icon ico) throws Error {
		if (ico == null) {
			return;
		}

		icon = ico; // Set the icon

		IconInfo? icon_info = props.icon_theme.lookup_by_gicon_for_scale(icon, props.icon_size, (int) props.s_factor, IconLookupFlags.USE_BUILTIN & IconLookupFlags.GENERIC_FALLBACK);
		set_icon_from_iconinfo(icon_info);
	}

	// set_icon_from_name is responsible for setting our icon based on an icon name
	public void set_icon_from_name(string icon_name) throws Error {
		try {
			Pixbuf? pix = props.icon_theme.load_icon_for_scale(icon_name, props.icon_size, (int) props.s_factor, IconLookupFlags.GENERIC_FALLBACK);
			set_image_pixbuf(pix);
		} catch (Error e) {
			throw e;
		}
	}

	// set_icon_from_iconinfo will attempt to load the pixbuf from the IconInfo and set our image pixbuf
	public void set_icon_from_iconinfo(IconInfo? icon_info) throws Error {
		if (icon_info == null) { // Failed to lookup the icon
			throw new IconThemeError.FAILED("Failed to load icon for: %s\n", name);
		}

		Pixbuf? pix = null; // Our icon for the image

		try {
			pix = icon_info.load_icon(); // Attempt to load the icon
		} catch (Error e) { // Failed to load the icon
			throw e; // Throw up e (eww)
		}

		if (pix.get_width() > props.icon_size) { // Greater than our icon size
			pix = pix.scale_simple(props.icon_size, props.icon_size, InterpType.BILINEAR);
		}

		set_image_pixbuf(pix);
	}

	// set_icon_factors will update various icon factors based on what is provided
	public void set_icon_factors() throws Error {
		if (props.icon_size != null) { // Size set
			if (props.icon_size <= 48) { // Small or Normal
				_label_width = 12;
				label.get_style_context().remove_class("larger-text");
			} else if (props.icon_size == 64) { // Large
				_label_width = 18;
				label.get_style_context().add_class("larger-text");
			} else if (props.icon_size == 96) { // Massive
				_label_width = 20;
				label.get_style_context().add_class("larger-text");
			}

			label.max_width_chars = _label_width; // Set our label width
			label.width_chars = _label_width; // Set our label width
		}

		if (icon != null) { // Icon is set
			try {
				set_icon(icon); // Reload our icon
			} catch (Error e) {
				warning("Failed to set icon: %s", e.message);
			}
		}
	}

	// set_image_pixbuf will set the image pixbuf
	public void set_image_pixbuf(Pixbuf pix) {
		original_image_pixbuf = pix;

		if (image == null) { // If we haven't created the Image yet
			image = new Image.from_pixbuf(pix); // Load the image from pixbuf
			image.get_style_context().add_class("desktop-item-image");
			image.margin_bottom = 10;
			main_layout.pack_start(image, true, true, 0); // Indicate this is the center widget
		} else { // If the Image already exists
			image.set_from_pixbuf(pix); // Set from the pixbuf
		}
	}
}