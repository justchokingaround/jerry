{
  description = "Watch anime with automatic anilist syncing and other cool stuff";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    flake-parts,
    systems,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = import systems;

      perSystem = {pkgs, ...}: let
        inherit (pkgs) callPackage;

        default = callPackage ./. {};
        full = callPackage ./. {
          withRofi = true;
          imagePreviewSupport = true;
          infoSupport = true;
        };
      in {
        formatter = pkgs.alejandra;

        devShells.default = pkgs.mkShell {
          inputsFrom = [full];
          packages = with pkgs; [
            # Nix
            alejandra
            statix
            deadnix

            # Shell
            bash-language-server
            shellcheck
            shfmt
          ];
        };

        packages = {
          jerry = default;
          inherit default;
          inherit full;
        };
      };
    };
}
