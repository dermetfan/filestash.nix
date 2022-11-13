{inputs, ...}: {
  perSystem = {
    lib,
    pkgs,
    ...
  }: {
    packages = let
      version = "0.5pre";
      src = pkgs.fetchFromGitHub {
        owner = "mickael-kerjean";
        repo = "filestash";
        # rev = "v${version}";
        rev = "bf2bca4cbb5ba57092c51c2163ea04cad987d0f3";
        hash = "sha256-wpS3Nozq8NgiaupC9Kg2p/WzlM+7b28+jyXF4z6DkV0=";
      };

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

            nodejs = pkgs.nodejs-14_x;
            nativeBuildInputs = [pkgs.python2];
          };

          NODE_ENV = "production";

          buildCommands = ["npm run build"];

          installPhase = "cp -r dist/data/public $out";
        };

      backend = pkgs.buildGo117Module {
        pname = "filestash-backend";
        inherit src version meta;

        vendorHash = null;

        subPackages = ["server"];

        ldflags = [
          "-X github.com/mickael-kerjean/filestash/server/common.BUILD_DATE=19700101"
          "-X github.com/mickael-kerjean/filestash/server/common.BUILD_REF=${src.rev}"
        ];

        tags = ["fts5"];

        nativeBuildInputs = with pkgs; [pkgconfig curl];

        CGO_CFLAGS_ALLOW = "-fopenmp";

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
