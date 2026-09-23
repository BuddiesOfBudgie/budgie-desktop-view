layout_test = executable(
	'test-layout',
	[
		'helpers.vala',
		'main.vala',
		'test_desktop_layout.vala',
		'test_layout_ops.vala',
		'test_legacy_positions.vala',
		layout_sources,
	],
	dependencies: [dep_glib, dep_gio, dep_m],
	build_by_default: false,
)

test('layout', layout_test)
