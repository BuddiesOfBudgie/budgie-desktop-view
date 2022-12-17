{
  lib,
  stdenv,
  desktop-file-utils,
  gtk3,
  intltool,
  meson,
  ninja,
  pkg-config,
  vala,
  wrapGAppsHook,
}:
stdenv.mkDerivation {
  pname = "budgie-desktop-view";
  version = "unstable";

  src = lib.cleanSource ../.;

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    vala
    intltool
    desktop-file-utils
    wrapGAppsHook
  ];

  buildInputs = [
    gtk3
  ];

  meta = with lib; {
    description = "Official Budgie desktop icons application/implementation";
    longDescription = ''
      Budgie Desktop View is the official Budgie desktop icons application/implementation.
    '';
    homepage = "https://blog.buddiesofbudgie.org/";
    downloadPage = "https://github.com/BuddiesOfBudgie/budgie-desktop-view/releases";
    mainProgram = "org.buddiesofbudgie.budgie-desktop-view";
    platforms = platforms.linux;
    license = licenses.asl20;
  };
}
