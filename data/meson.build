custom_target('us.getsol.budgie-desktop-view',
	input : 'us.getsol.budgie-desktop-view.desktop.in',
	output : 'us.getsol.budgie-desktop-view.desktop',
	command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
	install : true,
	install_dir : join_paths(datadir, 'applications'),
)

install_data(
	'us.getsol.budgie-desktop-view.gschema.xml',
	install_dir: join_paths(datadir, 'glib-2.0', 'schemas'),
)

custom_target('desktop-file-autostart-view', 
	input: 'us.getsol.budgie-desktop-view.desktop.in',
	output: 'us.getsol.budgie-desktop-view-autostart.desktop',
	command : [intltool, '--desktop-style', podir, '@INPUT@', '@OUTPUT@'],
	install: true,
	install_dir: xdg_appdir
)