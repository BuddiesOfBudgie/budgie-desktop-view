project(
	'budgie-desktop-view',
	['c', 'vala'],
	version: '10.10-preview.1',
	license: [ 'Apache-2.0' ],
	default_options: [
		'c_std=c11',
		'warning_level=3',
	],
)

gnome = import('gnome')

intltool = find_program('intltool-merge')

# Vala generates bad C code and missing these on gcc 14 will cause FTBFS
# Additionally, Meson 1.4 unhides warnings from valac-generated C code,
# which causes unreadable logspam. Reenables prior behavior.
am_cflags = [
	'-w',
	'-Wno-incompatible-pointer-types',
	'-Wno-implicit-function-declaration',
]
add_global_arguments(am_cflags, language: 'c')

meson.add_install_script('scripts/mesonPostInstall.sh')

glib_dep = '>= 2.64.0'
gnome_stack = '>= 3.24.0'

dep_glib = dependency('glib-2.0', version: glib_dep)
dep_gio = dependency('gio-unix-2.0', version: glib_dep)
dep_gdk = dependency('gdk-3.0', version: gnome_stack)
dep_gtk = dependency('gtk+-3.0', version: gnome_stack)
dep_vala = dependency('vapigen', version: '>= 0.48.0')
dep_gtk_layer_shell = dependency('gtk-layer-shell-0', version: '>= 0.8.0')
dep_xfce4windowing = dependency('libxfce4windowing-0', version: '>= 4.19.7')

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
