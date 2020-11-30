![view](https://github.com/getsolus/budgie-desktop-view/raw/master/.github/screenshots/budgie-desktop-settings-with-view.jpg)

# Budgie Desktop View

Budgie Desktop View is the official Budgie desktop icons application / implementation, developed by [Solus](https://getsol.us/).

![#budgie-desktop-dev on Freenode](https://img.shields.io/badge/freenode-%23budgie--desktop--dev-4AF)
![#solus-dev on Freenode](https://img.shields.io/badge/freenode-%23solus--dev-28C)

## Scope

The scope of this project is to provide quick access to the content and applications you consider most important. It is not designed to replace your file manager or to perform typical file manager actions.

Budgie Desktop View provides:

1. Options to enable and access "special" folders such as your Home directory and Trash.
2. Showing active drive / volume mounts (including mounted removable media).
3. An ordered list of Desktop directory contents, prioritizing folders before files while maintaining order of content that respects locales.
4. Independently adjustable icon sizing from your file manager
5. Right-click menu options for the background canvas to quickly access Budgie Desktop and System Settings, as well right-click menu options for opening a file using the default app, or via the Terminal.

Budgie Desktop View is designed for the Budgie Desktop. Usage outside of Budgie is not supported and is outside this project's scope.

![Budgie logo](https://getsol.us/imgs/budgie-small.png)

![Solus logo](https://build.getsol.us/logo.png)

## TODO

As Budgie Desktop View has a rigorous focus and scope of functionality, the TODO is currently limited to the following:

- Introduce an option to choose between single and double-click options for launching items.
- Ensuring long-press gestures on items work for 2-in-1 devices.
- Drag & Drop support: TBD on full scope. Current thinking is it will copy files and symlink directories (to avoid the need for recursive copy functionality).
- GTK4 port.

## Building

### Dependencies

The dependencies provided below are build-time dependencies and named according to the package name on Solus. You may need to look up the equivelant for your own operating system.

Name | Minimum Version | Max. (Tested) Version
---- | ---- | ----
glib2-devel | 2.64.0 | 2.66.3
libgtk-3-devel | 3.24.0 | 3.34.22
vala | 0.48.0 | 0.50.2

#### Solus

To install these under Solus, run:

```
sudo eopkg install -c system.devel libgtk-3-devel vala
```

### Defaults and Configure Options

By default, we will build with:

- `c_std` as `11`
- `buildtype` as `release`
- Link-time optimization (LTO) enabled as `b_lto`, which reduces executable size.
- `-03` GCC optimization level, which optimizes for both code size and execution time
- Warning level (`warning_level`) set to max (3). This is the equivelant to `-Wall` / `-Wpedantic`.

#### Stateless

Budgie Desktop View supports stateless XDG paths. This is **disabled** by default and typically reserved for Solus, which a proponent of statelessness. Should you wish to enable this (which will set the XDG application directory for autostart to datadir + `xdg/autostart` as opposed to using sysconfdir), you can use `-Dwith-stateless=true`

#### Custom XDG Application Directory

By default, Budgie Desktop View will install its autostart file to either datadir + `xdg/autostart` or sysconfdir + `xdg/autostart`. If you use an operating system that uses a different location for autostart files, you should use `-Dxdg-appdir=/full/path/to/directory` and replace the example path with the full path.

### Debug

Given the above mentioned defaults, it is highly recommended that you specifying `-Dbuildtype=debugoptimized` during meson "configure" time in order to get useful debug info, for example:

```
meson --prefix=/usr --libdir="lib64" --sysconfdir=/etc -Dbuildtype=debugoptimized  -Dwith-stateless=true build
```

### Release

A release configure would look something like:

```
meson --prefix=/usr --libdir="lib64" --sysconfdir=/etc -Dwith-stateless=true build
```

Obviously change any of the above mentioned defaults or flags as necessary.

### Compiling

Once aforementioned dependencies have been installed and Meson configuration step executed, you can compile sources.

```
ninja -C build
```

### Installing

Budgie Desktop View can be installed using this command:

```
sudo ninja -C build install
```

### Uninstalling

Budgie Desktop View can be uninstalled using this command:

```
sudo ninja -C build uninstall
```

## License

Budgie Desktop View is licensed under the Apache-2.0 license.

## Authors

Copyright © 2020 Solus Project
