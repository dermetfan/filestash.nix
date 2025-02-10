{
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-24.11;
    parts = {
      url = github:hercules-ci/flake-parts;
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    filestash = {
      url = github:mickael-kerjean/filestash;
      flake = false;
    };
    systems.url = github:nix-systems/default;
  };

  outputs = inputs @ {
    parts,
    systems,
    ...
  }:
    parts.lib.mkFlake {
      inherit inputs;
    } ({lib, ...}: {
      systems = import systems;

      imports = [
        ./packages.nix
        ./overlays.nix
        ./nixosModules.nix
        ./checks.nix
        ./apps.nix
      ];

      perSystem = {pkgs, ...}: {
        formatter = pkgs.alejandra;
      };
    });
}
