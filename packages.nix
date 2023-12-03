{inputs, ...}: {
  perSystem = {
    lib,
    pkgs,
    ...
  }: {
    packages = let
      src = inputs.filestash;
      version = src.shortRev;

      packageJson = let
        orig = lib.importJSON "${src}/package.json";
      in
        removeAttrs orig ["devDependencies"]
        // {
          dependencies = orig.dependencies // orig.devDependencies;
        };
      packageJsonFile = pkgs.writers.writeJSON "package.json" packageJson;

      meta = with lib; {
        description = "🦄 A modern web client for SFTP, S3, FTP, WebDAV, Git, Minio, LDAP, CalDAV, CardDAV, Mysql, Backblaze, …";
        homepage = https://github.com/mickael-kerjean/filestash;
        license = licenses.agpl3;
        maintainers = with maintainers; [dermetfan];
        platforms = platforms.linux;
      };
    in rec {
      frontend = pkgs.buildNpmPackage rec {
        inherit src version meta;
        pname = "${packageJson.name}-frontend";

        postPatch = ''
          cp --force ${packageJsonFile} package.json
          ln --symbolic ${./package-lock.json} package-lock.json
        '';

        npmDepsHash = "sha256-yF2IrPfkyKZKghIZfwQy3QyUtXabL13GhU1CLiA65U4=";
        npmInstallFlags = "--legacy-peer-deps";
        makeCacheWritable = true;

        NODE_ENV = "production";

        nativeBuildInputs = with pkgs; [python3];

        installPhase = "cp -r server/ctrl/static/www $out";

        passthru.generate-package-lock-json = pkgs.writeShellApplication {
          name = "generate-package-lock-json";
          runtimeInputs = with pkgs; [nodejs];
          text = ''
            tmp=$(mktemp -d)
            trap 'rm -r "$tmp"' EXIT

            ln --symbolic ${src}/* ${src}/.* "$tmp"/
            ln --symbolic --force ${packageJsonFile} "$tmp"/package.json

            pushd "$tmp"
            npm install --package-lock-only ${npmInstallFlags}
            popd

            mv "$tmp"/package-lock.json .
          '';
        };
      };

      backend = pkgs.buildGo120Module {
        pname = "filestash-backend";
        inherit src version;

        meta =
          meta
          // {
            mainProgram = "filestash";
          };

        vendorHash = null;

        ldflags = [
          "-X github.com/mickael-kerjean/filestash/server/common.BUILD_DATE=${toString src.lastModified}"
          "-X github.com/mickael-kerjean/filestash/server/common.BUILD_REF=${src.rev}"
          "-extldflags=-static"
        ];

        tags = ["fts5"];

        excludedPackages = [
          "server/generator"
          "server/plugin/plg_starter_http2"
          "server/plugin/plg_starter_https"
          "server/plugin/plg_search_sqlitefts"
        ];

        buildInputs = with pkgs; [vips];

        nativeBuildInputs = with pkgs; [pkg-config gotools];

        prePatch = "cp --recursive ${frontend} server/ctrl/static/www";

        # fix "imported and not used" errors
        postPatch = "goimports -w server";

        preBuild = "make build_init";

        postInstall = "rm $out/bin/public";
      };

      full =
        pkgs.runCommand "filestash" {
          inherit (backend) meta;

          nativeBuildInputs = [pkgs.makeWrapper];

          pathConfig = "/proc/self/cwd/state/config.json";
          pathDb = "/proc/self/cwd/state/db";
          pathLog = "/proc/self/cwd/state/log";
          pathSearch = "/proc/self/cwd/state/search";
          pathCert = "/proc/self/cwd/state/certs";
          pathTmp = "/proc/self/cwd/cache/tmp";
        } ''
          mkdir -p $out/bin
          ln -s ${backend}/bin/filestash $out/bin/filestash
          wrapProgram $out/bin/filestash \
            --set-default WORK_DIR $out/libexec/filestash

          mkdir -p $out/libexec/filestash
          pushd $out/libexec/filestash

          mkdir -p data/state/config data/cache
          ln -s ${frontend}   data/public
          ln -s "$pathConfig" data/state/config/config.json
          ln -s "$pathDb"     data/state/db
          ln -s "$pathLog"    data/state/log
          ln -s "$pathSearch" data/state/search
          ln -s "$pathCert"   data/state/certs
          ln -s "$pathTmp"    data/cache/tmp
        '';

      default = full;
    };
  };
}
