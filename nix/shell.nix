{pkgs ? import <nixpkgs> {}}:
with pkgs;
  mkShell {
    nativeBuildInputs = [
      meson
      ninja
      pkg-config
      vala
      intltool
    ];

    buildInputs = [
      gtk3
    ];
  }
