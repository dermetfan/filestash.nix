parts: rec {
  flake.nixosModules = let
    filestash = "filestash";
  in {
    default = flake.nixosModules.${filestash};

    ${filestash} = {
      options,
      config,
      lib,
      pkgs,
      ...
    }: let
      opts = options.services.${filestash};
      cfg = config.services.${filestash};
    in {
      options.services.${filestash} = with lib; {
        enable = mkEnableOption filestash;

        package = mkOption {
          type = types.package;
          default = pkgs.${filestash} or parts.config.flake.packages.${pkgs.system}.default;
        };

        paths = {
          config = mkOption {
            type = types.path;
            default = "/run/${filestash}/config.json";
          };
          db = mkOption {
            type = types.path;
            default = "/var/lib/${filestash}/db";
          };
          cert = mkOption {
            type = types.path;
            default = "/var/lib/${filestash}/cert";
          };
          log = mkOption {
            type = types.path;
            default = "/var/log/${filestash}";
          };
          search = mkOption {
            type = types.path;
            default = "/var/cache/${filestash}/search";
          };
          tmp = mkOption {
            type = types.path;
            default = "/var/cache/${filestash}";
          };
        };

        user = mkOption {
          type = types.str;
          default = filestash;
        };

        group = mkOption {
          type = types.str;
          default = filestash;
        };

        settings = mkOption {
          type = types.submodule {
            freeformType = with types; attrsOf anything;

            options = {
              general.secret_key_file = mkOption {
                type = with types; nullOr path;
                default = null;
                description = lib.mdDoc ''
                  The secret key in the config file will be replaced
                  with the contents of this file before start.
                  Only works if `paths.config` is its default value.
                '';
              };

              features.api.api_key_file = mkOption {
                type = with types; nullOr path;
                default = null;
                description = lib.mdDoc ''
                  The API key in the config file will be replaced
                  with the contents of this file before start.
                  Only works if `paths.config` is its default value.
                '';
              };

              auth.admin_file = mkOption {
                type = with types; nullOr path;
                default = null;
                description = lib.mdDoc ''
                  The admin password in the config file will be replaced
                  with the contents of this file before start.
                  Only works if `paths.config` is its default value.
                '';
              };

              connections = mkOption {
                type = types.listOf (
                  types.submodule {
                    freeformType = with types; attrsOf anything;

                    options.password_file = mkOption {
                      type = with types; nullOr path;
                      default = null;
                      description = lib.mdDoc ''
                        The conection password in the config file will be replaced
                        with the contents of this file before start.
                        Only works if `paths.config` is its default value.
                      '';
                    };
                  }
                );
                default = [];
              };
            };
          };
        };
      };

      config = lib.mkIf cfg.enable {
        # seems to be broken and logs ffmpeg errors on the backend
        services.filestash.settings.features.video.enable_transcoder = lib.mkDefault false;

        systemd.services.${filestash} = {
          description = "Filestash";
          wantedBy = ["multi-user.target"];
          after = ["network.target"];

          restartTriggers = with cfg;
            map builtins.toJSON [
              settings
              paths
            ];

          serviceConfig = {
            User = cfg.user;
            Group = cfg.group;

            ConfigurationDirectory = filestash;
            StateDirectory = filestash;
            CacheDirectory = filestash;
            LogsDirectory = filestash;
            RuntimeDirectory = filestash;

            ExecStart = lib.getExe (cfg.package.overrideAttrs (_: {
              pathConfig = cfg.paths.config;
              pathDb = cfg.paths.db;
              pathLog = cfg.paths.log;
              pathSearch = cfg.paths.search;
              pathCert = cfg.paths.cert;
              pathTmp = cfg.paths.tmp;
            }));
          };

          preStart = let
            replaceSecret = file: path:
              lib.optionalString (file != null) ''
                < ${lib.escapeShellArg file} \
                  ${lib.getExe' pkgs.jq "jq"} --raw-input \
                  --slurpfile config "$RUNTIME_DIRECTORY"/config.json \
                  '
                    . as $secret |
                    $config[] |
                    ${path} = $secret
                  ' \
                  > "$RUNTIME_DIRECTORY"/config-secret.json
                mv "$RUNTIME_DIRECTORY"/config{-secret,}.json
              '';
          in
            ''
              mkdir --parents ${with cfg.paths; lib.escapeShellArgs [db log search tmp]}
            ''
            + lib.optionalString (cfg.paths.config == opts.paths.config.default) ''
              cp "$CONFIGURATION_DIRECTORY"/config.json "$RUNTIME_DIRECTORY"/config.json
              ${replaceSecret cfg.settings.general.secret_key_file or null ".general.secret_key"}
              ${replaceSecret cfg.settings.features.api.api_key_file or null ".features.api.api_key"}
              ${replaceSecret cfg.settings.auth.admin_file or null ".auth.admin"}
              ${toString (
                lib.imap0
                (i: v: replaceSecret v.password_file ".connections[${toString i}].password")
                cfg.settings.connections
              )}
            '';
        };

        environment.etc."${filestash}/config.json" = {
          inherit (cfg) user group;
          text = lib.generators.toJSON {} (
            cfg.settings
            // {
              general = removeAttrs cfg.settings.general ["secret_key_file"];
              features = removeAttrs cfg.settings.features ["api_key_file"];
              auth = removeAttrs cfg.settings.auth ["admin_file"];
              connections =
                map
                (v: removeAttrs v ["password_file"])
                cfg.settings.connections;
            }
          );
        };

        users = {
          users = lib.mkIf (cfg.user == filestash) {
            ${filestash} = {
              isSystemUser = true;
              inherit (cfg) group;
              home = "/var/lib/${filestash}";
            };
          };

          groups = lib.mkIf (cfg.group == filestash) {
            ${filestash} = {};
          };
        };
      };
    };
  };
}
