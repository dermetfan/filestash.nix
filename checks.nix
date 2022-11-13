parts: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: {
    checks.example = pkgs.nixosTest {
      name = "filestash";
      nodes.main = {
        config,
        lib,
        ...
      }: {
        imports = [parts.config.flake.nixosModules.default];

        nixpkgs.overlays = [parts.config.flake.overlays.default];

        environment.etc = lib.mapAttrs' (k: lib.nameValuePair "filestash/secrets/${k}") {
          secret_key.text = "SECRET_KEY";
          admin_password.text = "ADMIN_PASSWORD";
          api_key.text = "API_KEY";
          "connections/LOCAL/password".text = "LOCAL_PASSWORD";
        };

        services.filestash = {
          enable = true;

          settings = {
            general = {
              port = 8334;
              secret_key = "PLACEHOLDER";
              secret_key_file = "/etc/filestash/secrets/secret_key";
            };
            features.api = {
              enable = true;
              api_key = "PLACEHOLDER";
              api_key_file = "/etc/filestash/secrets/api_key";
            };
            auth = {
              admin = "PLACEHOLDER";
              admin_file = "/etc/filestash/secrets/admin_password";
            };
            connections = [
              {
                label = "LOCAL";
                type = "local";
                password_file = "/etc/filestash/secrets/connections/LOCAL/password";
                path = "${config.users.users.filestash.home}/files";
              }
            ];
          };
        };
      };

      testScript = {nodes, ...}:
        with nodes.main.services.filestash; let
          checkSecretConfig = secret: path: ''
            main.succeed("${lib.getExe pkgs.jq} --exit-status --arg secret ${lib.escapeShellArg nodes.main.environment.etc."filestash/secrets/${secret}".text} '${path} == $secret' ${paths.config}")
          '';
        in
          ''
            main.wait_for_unit("filestash")

            ${checkSecretConfig "secret_key" ".general.secret_key"}
            ${checkSecretConfig "api_key" ".features.api.api_key"}
            ${checkSecretConfig "admin_password" ".auth.admin"}
            ${checkSecretConfig "connections/LOCAL/password" ".connections[0].password"}

            main.succeed("curl http://127.0.0.1:${toString settings.general.port} -D- --no-progress-meter")
            main.succeed("stat ${lib.escapeShellArg paths.log}/access.log")
            # main.succeed("stat ${lib.escapeShellArg paths.db}")
            # main.succeed("stat ${lib.escapeShellArg paths.search}")
          ''
          + toString (
            map (v: ''
              # main.succeed("stat ${lib.escapeShellArg v.path}")
            '') (
              builtins.filter
              (v: v.type == "local")
              settings.connections
            )
          );
    };
  };
}
