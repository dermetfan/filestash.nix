{inputs, ...}: {
  perSystem = {
    config,
    lib,
    ...
  }: {
    apps.generate-package-lock-json = {
      type = "app";
      program = lib.getExe config.packages.frontend.passthru.generate-package-lock-json;
    };
  };
}
