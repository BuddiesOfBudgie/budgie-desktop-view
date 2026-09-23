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

using Gtk;

// RubberBand is the drag-to-select rectangle started from empty desktop space, in canvas coordinates
public class RubberBand {
	public bool active { get; private set; default = false; }

	// Where the press happened and where the pointer is now; either corner can be the top-left
	private double start_x;
	private double start_y;
	private double end_x;
	private double end_y;
	private GenericSet<DesktopItem>? kept = null; // Items that stay selected no matter where the band goes

	// begin starts a band. kept is the selection to add to when Ctrl or Shift is held, or null to replace it.
	public void begin(double x, double y, GenericSet<DesktopItem>? kept) {
		active = true;
		start_x = end_x = x;
		start_y = end_y = y;
		this.kept = kept;
	}

	public void update(double x, double y) {
		end_x = x;
		end_y = y;
	}

	// finish ends the band and returns whether it was dragged at all; a band that never moved was just a click
	public bool finish() {
		active = false;
		kept = null;
		return Math.fabs(end_x - start_x) > 1 || Math.fabs(end_y - start_y) > 1; // Ignore a pixel of pointer jitter
	}

	// cancel ends the band without treating it as a click, e.g. on Escape
	public void cancel() {
		active = false;
		kept = null;
	}

	// selects returns whether an item belongs in the selection while the band is at its current size
	public bool selects(DesktopItem item) {
		if (kept != null && kept.contains(item)) return true;

		Gtk.Allocation alloc;
		item.get_allocation(out alloc); // Relative to the canvas window, same as the band

		// Touching the item counts; it doesn't need to be fully inside the band
		Gdk.Rectangle item_rect = { alloc.x, alloc.y, alloc.width, alloc.height };
		Gdk.Rectangle overlap;
		return rect().intersect(item_rect, out overlap);
	}

	// rect normalizes the two corners into a rectangle with positive size
	public Gdk.Rectangle rect() {
		return {
			(int) double.min(start_x, end_x),
			(int) double.min(start_y, end_y),
			(int) Math.fabs(end_x - start_x),
			(int) Math.fabs(end_y - start_y)
		};
	}

	// draw paints the band with the theme's rubberband style
	public void draw(StyleContext ctx, Cairo.Context cr) {
		Gdk.Rectangle band = rect();

		// Themes style the rubberband class, so the band matches file managers
		ctx.save();
		ctx.add_class("rubberband");
		ctx.render_background(cr, band.x, band.y, band.width, band.height);
		ctx.render_frame(cr, band.x, band.y, band.width, band.height);
		ctx.restore();
	}
}
