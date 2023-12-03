{
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-23.11;
    parts = {
      url = github:hercules-ci/flake-parts;
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    filestash = {
      url = github:mickael-kerjean/filestash;
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    parts,
    ...
  }:
    parts.lib.mkFlake {
      inherit self;
    } ({lib, ...}: {
      systems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

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
