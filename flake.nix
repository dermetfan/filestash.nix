{
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixpkgs-unstable;
    parts = {
      url = github:hercules-ci/flake-parts;
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    npmlock2nix = {
      # https://github.com/nix-community/npmlock2nix/pull/94
      url = github:Sohalt/npmlock2nix/91bdfd4067aa7c0d3133ee157ccd8baf1921ffbb;
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
      ];

      perSystem = {pkgs, ...}: {
        formatter = pkgs.alejandra;
      };
    });
}
