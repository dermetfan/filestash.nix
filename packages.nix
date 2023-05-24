{inputs, ...}: {
  perSystem = {
    lib,
    pkgs,
    system,
    ...
  }: {
    packages = let
      src = inputs.filestash;
      version = src.shortRev;

      meta = with lib; {
        description = "🦄 A modern web client for SFTP, S3, FTP, WebDAV, Git, Minio, LDAP, CalDAV, CardDAV, Mysql, Backblaze, …";
        homepage = https://github.com/mickael-kerjean/filestash;
        license = licenses.agpl3;
        maintainers = with maintainers; [dermetfan];
        platforms = platforms.linux;
      };
    in rec {
      frontend =
        (pkgs.extend (final: prev: {
          npmlock2nix = import inputs.npmlock2nix {pkgs = prev;};
        }))
        .npmlock2nix
        .build {
          inherit src version;

          node_modules_attrs = let
            transformJsonFile = file: f:
              lib.pipe file [
                lib.importJSON
                f
                builtins.toJSON
                (pkgs.writeText (baseNameOf file))
                (d: d.outPath)
              ];

            lenientPkgs = import inputs.nixpkgs {
              inherit system;
              config.permittedInsecurePackages = [
                "nodejs-14.21.3"
                "openssl-1.1.1t"
                "python-2.7.18.6"
              ];
            };
          in rec {
            packageJson = transformJsonFile "${src}/package.json" (
              p:
                p
                // {
                  dependencies =
                    __mapAttrs
                    (
                      k: v:
                        if lib.hasPrefix "git+" v
                        then (lib.importJSON packageLockJson).dependencies.${k}.version
                        else v
                    )
                    p.dependencies;
                }
            );

            packageLockJson = transformJsonFile ./package-lock.json (
              p:
                p
                // {
                  dependencies =
                    __mapAttrs
                    (
                      k: v:
                        if v ? from
                        then v // {from = v.version;}
                        else v
                    )
                    p.dependencies;
                }
            );

            nodejs = lenientPkgs.nodejs-14_x;
            nativeBuildInputs = with lenientPkgs; [python2];
          };

          NODE_ENV = "production";

          buildCommands = ["npm run build"];

          installPhase = "cp -r server/ctrl/static/www $out";
        };

      backend = pkgs.buildGo120Module {
        pname = "filestash-backend";
        inherit src version meta;

        vendorHash = null;

        subPackages = ["server"];

        ldflags = [
          "-X github.com/mickael-kerjean/filestash/server/common.BUILD_DATE=${toString src.lastModified}"
          "-X github.com/mickael-kerjean/filestash/server/common.BUILD_REF=${src.rev}"
          "-extldflags=-static"
        ];

        tags = ["fts5"];

        nativeBuildInputs = with pkgs; [pkgconfig curl];

        prePatch = "cp -r ${frontend} server/ctrl/static/www";

        preBuild = "make build_init";
      };

      full =
        pkgs.runCommand "filestash" {
          nativeBuildInputs = [pkgs.makeWrapper];

          pathConfig = "/proc/self/cwd/state/config.json";
          pathDb = "/proc/self/cwd/state/db";
          pathLog = "/proc/self/cwd/state/log";
          pathSearch = "/proc/self/cwd/state/search";
        } ''
          mkdir -p $out/bin
          ln -s ${backend}/bin/server $out/bin/filestash
          wrapProgram $out/bin/filestash \
            --set-default WORK_DIR $out/libexec/filestash

          mkdir -p $out/libexec/filestash
          pushd $out/libexec/filestash

          mkdir -p data/state/config
          ln -s ${frontend} data/public
          ln -s "$pathConfig" data/state/config/config.json
          ln -s "$pathDb" data/state/db
          ln -s "$pathLog" data/state/log
          ln -s "$pathSearch" data/state/search
        '';

      default = full;
    };
  };
}
