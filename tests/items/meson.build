thumbnails_test = executable(
	'test-thumbnails',
	['test_thumbnails.vala', thumbnails_sources],
	dependencies: [dep_glib, dep_gio, dependency('gdk-pixbuf-2.0')],
	build_by_default: false,
)

test('thumbnails', thumbnails_test)
