{
  description = "watch anime with automatic anilist syncing and other cool stuff";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
  flake-utils.lib.eachDefaultSystem (system:
  with import nixpkgs { system = "${system}"; };
  let
    pkgs = import nixpkgs { inherit system; };
  in {
    packages.jerry = callPackage ./default.nix { };
    packages.default = self.packages.${system}.jerry;
		packages.full = callPackage ./full.nix { };
  });
}
