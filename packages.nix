{
  inputs,
  config,
  ...
}: {
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
        license = licenses.agpl3Only;
        maintainers = with maintainers; [dermetfan];
        platforms = platforms.linux;
      };

      nixosOptionsDoc = pkgs.nixosOptionsDoc {
        inherit
          (lib.evalModules {
            modules = [
              config.flake.nixosModules.filestash
              {
                _module = {
                  check = false;
                  args = {inherit pkgs;};
                };
              }
            ];
          })
          options
          ;
        documentType = "none";
        warningsAreErrors = false;
      };
    in rec {
      frontend = pkgs.buildNpmPackage rec {
        inherit src version meta;
        pname = "${packageJson.name}-frontend";

        postPatch = ''
          cp --force ${packageJsonFile} package.json
          ln --symbolic ${./package-lock.json} package-lock.json
        '';

        npmDepsHash = "sha256-NX54LLtaIgbKWhkt6o17hhrK3CFzdDQiGVbUc5/HKes=";
        npmInstallFlags = "--legacy-peer-deps";
        makeCacheWritable = true;

        NODE_ENV = "production";

        nativeBuildInputs = with pkgs; [python3];

        installPhase = "cp --recursive server/ctrl/static/www $out";

        passthru.generate-package-lock-json = pkgs.writeShellApplication {
          name = "generate-package-lock-json";
          runtimeInputs = with pkgs; [nodejs];
          text = ''
            tmp=$(mktemp --directory)
            trap 'rm --recursive "$tmp"' EXIT

            ln --symbolic ${src}/* ${src}/.* "$tmp"/
            ln --symbolic --force ${packageJsonFile} "$tmp"/package.json

            pushd "$tmp"
            npm install --package-lock-only ${npmInstallFlags}
            popd

            mv "$tmp"/package-lock.json .
          '';
        };
      };

      backend = pkgs.buildGo121Module {
        pname = "filestash-backend";
        inherit src version;

        meta =
          meta
          // {
            mainProgram = "filestash";
          };

        vendorHash = "sha256-cbpvwMt3Qp0lmcOrHtkOIFIo9NjstqC/wYUjkckV8f4=";

        ldflags = [
          "-X github.com/mickael-kerjean/filestash/server/common.BUILD_DATE=${toString src.lastModified}"
          "-X github.com/mickael-kerjean/filestash/server/common.BUILD_REF=${src.rev}"
        ];

        tags = ["fts5"];

        excludedPackages = [
          "server/generator"
        ];

        buildInputs = with pkgs; [
          vips
          libjpeg
          libpng
          libwebp
          libraw
          giflib
          libheif
        ];

        nativeBuildInputs = with pkgs; [pkg-config gotools];

        prePatch = "cp --recursive ${frontend} server/ctrl/static/www";

        patches = [./cgo-ldflags.patch];
        patchFlags = "--strip=0";

        # fix "imported and not used" errors
        postPatch = "goimports -w server";

        preBuild = "go generate -x ./server/...";

        postInstall = ''
          rm $out/bin/public
          mv $out/bin/{cmd,filestash}
        '';
      };

      full =
        pkgs.runCommand "filestash" {
          inherit (backend) meta;

          nativeBuildInputs = [pkgs.makeBinaryWrapper];

          pathConfig = "/proc/self/cwd/state/config.json";
          pathDb = "/proc/self/cwd/state/db";
          pathLog = "/proc/self/cwd/state/log";
          pathSearch = "/proc/self/cwd/state/search";
          pathCert = "/proc/self/cwd/state/certs";
          pathTmp = "/proc/self/cwd/cache";
        } ''
          mkdir --parents $out/bin
          ln --symbolic ${backend}/bin/filestash $out/bin/filestash
          wrapProgram $out/bin/filestash \
            --set-default FILESTASH_PATH $out/libexec/filestash

          mkdir --parents $out/libexec/filestash
          pushd $out/libexec/filestash

          mkdir --parents state/config
          ln --symbolic ${frontend}   public
          ln --symbolic "$pathConfig" state/config/config.json
          ln --symbolic "$pathDb"     state/db
          ln --symbolic "$pathLog"    state/log
          ln --symbolic "$pathSearch" state/search
          ln --symbolic "$pathCert"   state/certs
          ln --symbolic "$pathTmp"    cache
        '';

      default = full;

      "nixosModuleDocs/asciiDoc" = nixosOptionsDoc.optionsAsciiDoc;
      "nixosModuleDocs/commonMark" = nixosOptionsDoc.optionsCommonMark;
      "nixosModuleDocs/json" = nixosOptionsDoc.optionsJSON;
    };
  };
}
