# Budgie Desktop View

The Budgie Desktop View is the official Budgie desktop icons application / implementation, developed by [Solus](https://getsol.us/).

This implementation is **not** designed to replace your file manager or to perform typical file manager actions, its purpose is pretty simple:

1. Display an optimal amount of your folders and files in your Desktop folder, based on screen resolution and our options for icon sizes.
2. Provide options to enable quick access to your Home folder, "Trash", as well as mounts.

Budgie Desktop View is designed for the Budgie Desktop. Usage outside of Budgie is not supported and is outside this project's scope.

![Budgie logo](https://getsol.us/imgs/budgie-small.png)

![Solus logo](https://build.getsol.us/logo.png)

## Building

### Dependencies

The dependencies provided below are build-time dependencies and named according to the package name on Solus. You may need to look up the equivelant for your own operating system.

Name | Minimum Version | Max. (Tested) Version
---- | ---- | ----
glib2-devel | 2.64.0 | 2.64.4
libgtk-3-devel | 3.24.0 | 3.34.22
vala | 0.48.0 | 0.48.9

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

## License

Budgie Desktop View is licensed under the Apache-2.0 license.

## Authors

Copyright © 2020 Solus