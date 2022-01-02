custom_target('org.buddiesofbudgie.budgie-desktop-view',
	input : 'org.buddiesofbudgie.budgie-desktop-view.desktop.in',
	output : 'org.buddiesofbudgie.budgie-desktop-view.desktop',
	command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
	install : true,
	install_dir : join_paths(datadir, 'applications'),
)

install_data(
	'org.buddiesofbudgie.budgie-desktop-view.gschema.xml',
	install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)

custom_target('desktop-file-autostart-view', 
	input: 'org.buddiesofbudgie.budgie-desktop-view.desktop.in',
	output: 'org.buddiesofbudgie.budgie-desktop-view-autostart.desktop',
	command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
	install: true,
	install_dir: xdg_appdir
)