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

          node_modules_attrs = rec {
            packageJson = lib.pipe "${src}/package.json" [
              lib.importJSON
              (
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
              )
              builtins.toJSON
              (pkgs.writeText "package.json")
              (d: d.outPath)
            ];

            packageLockJson = lib.pipe ./package-lock.json [
              lib.importJSON
              (
                p:
                  p
                  // {
                    dependencies =
                      __mapAttrs
                      (
                        k: v:
                          if v ? from
                          then
                            v
                            // rec {
                              from = version;
                              version = lib.pipe v.version [
                                # replace git+https with direct github support
                                (
                                  vv: let
                                    prefix = "git+https://github.com/";
                                  in
                                    if lib.hasPrefix prefix vv
                                    then "github:" + lib.removePrefix prefix vv
                                    else vv
                                )
                                # remove .git repo name suffix
                                (
                                  vv:
                                    if lib.hasInfix ".git#" vv
                                    then __replaceStrings [".git"] [""] vv
                                    else vv
                                )
                              ];
                            }
                          else v
                      )
                      p.dependencies;
                  }
              )
              builtins.toJSON
              (pkgs.writeText "package-lock.json")
              (d: d.outPath)
            ];

            nodejs = pkgs.nodejs-14_x;
            nativeBuildInputs = [pkgs.python2];

            githubSourceHashMap.mickael-kerjean = {
              aes-js."76d19e46f762e9a21ab2b58ded409e70434f7610" = "007w7baiz5f75p0bf5mra7aa0l05mgqwavqdajvkr95s1q0rladq";
              react-selectable."7e2456668bf3e8046271c6795f24ee33c009bdfb" = "0iln75k6h9wddhfgl11mznyaywmmwql3i181781ayqmhcf5q1kwd";
            };
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
