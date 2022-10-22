{config, ...}: {
  flake.overlays = rec {
    default = filestash;
    filestash = final: prev: {
      filestash = config.flake.packages.${prev.system}.default;
    };
  };
}
