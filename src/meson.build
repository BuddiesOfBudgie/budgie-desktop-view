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
	dep_gtk
]

c_flags = []

optimization_level = get_option('optimization')

if optimization_level == '0'
	warning('We recommend setting an optimization level')
else
	c_flags += '-O'+optimization_level
endif

executable(
	'us.getsol.budgie-desktop-view',
	desktop_view_sources,
	dependencies: desktop_view_deps,
	vala_args: [
		'--pkg', 'gdk-3.0',
		'--pkg', 'gio-unix-2.0',
		'--pkg', 'gtk+-3.0',
		'--target-glib=2.64',
	],
	install: true,
	install_dir: join_paths(get_option('prefix'), get_option('bindir')),
	c_args: c_flags,
)