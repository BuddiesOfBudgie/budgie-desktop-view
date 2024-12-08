# Provides Budgie Desktop View component

desktop_view_sources = [
	res,
	'application.vala',
	'budgie_desktop_view.vala',
	'desktop_item.vala',
	'desktop_menu.vala',
	'file_item.vala',
	'file_menu.vala',
	'mount_item.vala',
	'unified_props.vala'
]

desktop_view_deps = [
	dep_gdk,
	dep_glib,
	dep_gio,
	dep_gtk,
	dep_gtk_layer_shell,
	dep_xfce4windowing
]

c_flags = []

executable(
	'org.buddiesofbudgie.budgie-desktop-view',
	desktop_view_sources,
	dependencies: desktop_view_deps,
	vala_args: [
		'--pkg', 'gdk-3.0',
		'--pkg', 'gio-unix-2.0',
		'--pkg', 'gtk+-3.0',
		'--target-glib=2.64',
		'--vapidir', join_paths(meson.source_root(), 'vapi'),
	],
	install: true,
	install_dir: join_paths(get_option('prefix'), get_option('bindir')),
	c_args: c_flags,
)
