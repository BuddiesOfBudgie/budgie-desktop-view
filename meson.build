project(
	'budgie-desktop-view',
	['c', 'vala'],
	version: '1.3',
	license: [ 'Apache-2.0' ],
	default_options: [
		'b_lto=false',
		'c_std=c11',
		'buildtype=release',
		'optimization=3',
		'werror=true',
		'warning_level=3',
	],
)

gnome = import('gnome')

intltool = find_program('intltool-merge')

am_cflags = [
	'-Wconversion',
	'-Wformat',
	'-Wformat-security',
	'-Wstack-protector',
	'-Wundef',
	'-Wuninitialized',
	'-fstack-protector',
]

add_global_arguments(am_cflags, language: 'c')
meson.add_install_script('scripts/mesonPostInstall.sh')

glib_dep = '>= 2.64.0'
gnome_stack = '>= 3.24.0'

dep_glib = dependency('glib-2.0', version: glib_dep)
dep_gio = dependency('gio-unix-2.0', version: glib_dep)
dep_gdk = dependency('gdk-3.0', version: gnome_stack)
dep_gdk_x11 = dependency('gdk-x11-3.0', version: gnome_stack)
dep_gtk = dependency('gtk+-3.0', version: gnome_stack)
dep_vala = dependency('vapigen', version: '>= 0.48.0')

# Make gettext work
add_global_arguments('-DGETTEXT_PACKAGE="budgie-desktop-view"', language: 'c')

prefix = get_option('prefix')
libdir = join_paths(prefix, get_option('libdir'))
confdir = join_paths(prefix, get_option('sysconfdir'))
datadir = join_paths(prefix, get_option('datadir'))
localedir = join_paths(prefix, get_option('localedir'))
podir = join_paths(meson.source_root(), 'po')

with_stateless = get_option('with-stateless')
if with_stateless == true
    warning('Only use stateless option with a supported OS')
endif

xdg_appdir = get_option('xdg-appdir')
if xdg_appdir == ''
	if with_stateless == true
		xdg_appdir = join_paths(datadir, 'xdg', 'autostart')
	else
		xdg_appdir = join_paths(confdir, 'xdg', 'autostart')
	endif
endif

gresource = join_paths(meson.current_source_dir(), 'data', 'budgie-desktop-view.gresource.xml')
res = gnome.compile_resources(
	'budgie-desktop-view-resources',
	gresource,
	source_dir: join_paths(meson.current_source_dir(), 'data'),
	c_name: 'budgie_desktop_view',
)

subdir('po')

subdir('src')

subdir('data')

report = [
	'    Build configuration:',
	'    ====================',
	'',
	'    prefix:                                 @0@'.format(prefix),
	'    datadir:                                @0@'.format(datadir),
	'    sysconfdir:                             @0@'.format(confdir),
	'    localedir:                              @0@'.format(localedir),
	'    XDG Path:                               @0@'.format(xdg_appdir),
	'',
]


# Output some stuff to validate the build config
message('\n\n\n' + '\n'.join(report) + '\n\n')
