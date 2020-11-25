project(
	'budgie-desktop-view',
	['c', 'vala'],
	version: '0.99.2',
	license: [ 'Apache-2.0' ],
	default_options: [
		'b_lto=false',
		'c_std=c11',
		'buildtype=release',
		'optimization=3',
		'warning_level=3',
	],
)

gnome = import('gnome')

git = find_program('git', required: false)
intltool = find_program('intltool-merge')

am_cflags = [
	'-Werror',
	'-Wconversion',
	'-Wformat',
	'-Wformat-security',
	'-Wstack-protector',
	'-Wundef',
	'-Wuninitialized',
	'-fstack-protector',
]

add_global_arguments(am_cflags, language: 'c')

glib_dep = '>= 2.64.0'
gnome_stack = '>= 3.24.0'

dep_glib = dependency('glib-2.0', version: glib_dep)
dep_gio = dependency('gio-unix-2.0', version: glib_dep)
dep_gdk = dependency('gdk-3.0', version: gnome_stack)
dep_gtk = dependency('gtk+-3.0', version: gnome_stack)
dep_vala = dependency('vapigen', version: '>= 0.48.0')

package_version = meson.project_version()

if git.found()
	git_version = run_command('git', ['rev-parse', 'HEAD'])
	if git_version.returncode() == 0
		package_version += ' (git-'+git_version.stdout().strip()+')'
	endif
endif

# Create config.h
cdata = configuration_data()

cdata.set_quoted('PACKAGE_VERSION', package_version)

# Make gettext work
cdata.set_quoted('GETTEXT_PACKAGE', meson.project_name())
add_global_arguments('-DGETTEXT_PACKAGE="budgie-desktop-view"', language: 'c')

prefix = get_option('prefix')
libdir = join_paths(prefix, get_option('libdir'))
confdir = join_paths(prefix, get_option('sysconfdir'))
datadir = join_paths(prefix, get_option('datadir'))
localedir = join_paths(prefix, get_option('localedir'))
podir = join_paths(meson.source_root(), 'po')

with_stateless = get_option('with-stateless')
if with_stateless == true
    warning('Only use stateless option with a supported OS like Solus')
endif

xdg_appdir = get_option('xdg-appdir')
if xdg_appdir == ''
	if with_stateless == true
		xdg_appdir = join_paths(datadir, 'xdg', 'autostart')
	else
		xdg_appdir = join_paths(get_option('sysconfdir'), 'xdg', 'autostart')
	endif
endif

cdata.set_quoted('DATADIR', datadir)
cdata.set_quoted('SYSCONFDIR', confdir)
cdata.set_quoted('LOCALEDIR', localedir)
cdata.set_quoted('PACKAGE_URL', 'https://github.com/getsolus/budgie-desktop-view/')

configure_file(
	output: 'config.h',
	configuration: cdata,
)

gresource = join_paths(meson.current_source_dir(), 'data', 'budgie-desktop-view.gresource.xml')
res = gnome.compile_resources(
	'budgie-desktop-view-resources',
	gresource,
	source_dir: join_paths(meson.current_source_dir(), 'data'),
	c_name: 'budgie_desktop_view',
)

subdir('data')
subdir('src')

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
