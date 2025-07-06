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
        license = licenses.agpl3Only;
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

        npmDepsHash = "sha256-0idHEfAmeMMrOxgtYpn43CrpbvEU6E68nWcA8bhXXNo=";
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

      backend = pkgs.buildGoModule {
        pname = "filestash-backend";
        inherit src version;

        meta =
          meta
          // {
            mainProgram = "filestash";
          };

        vendorHash = "sha256-pI9BGqFOncwoj1B8cvB9cTqLa3dLGvN0oZ8lE9a1CsU=";

        ldflags = [
          "-X github.com/mickael-kerjean/filestash/server/common.BUILD_DATE=${toString src.lastModifiedDate}"
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
          stb
        ];

        nativeBuildInputs = with pkgs; [
          pkg-config
          gotools

          makeBinaryWrapper
        ];

        prePatch = "cp --recursive ${frontend} server/ctrl/static/www";

        patches = [
          ./cgo-ldflags.patch
          ./image-psd.patch
          ./video-tmp.patch

          # Without this, our `-X` in `ldflags` are overridden.
          ./no-generator-constants.patch
        ];
        patchFlags = "--strip=0";

        postPatch = ''
          # fix "imported and not used" errors
          goimports -w server

          # remove copy of ${pkgs.stb}/include/stb/stb_image.h
          # that is no longer used due to ${./image-psd.patch}
          rm server/plugin/plg_image_c/image_psd_vendor.h
        '';

        preBuild = "go generate -x ./server/...";

        postInstall = "mv $out/bin/{cmd,filestash}";

        preFixup = ''
          wrapProgram $out/bin/filestash \
            --suffix PATH : ${lib.makeBinPath (with pkgs; [
            ffmpeg.bin # runtime dependency of `plg_video_thumbnail`
          ])}
        '';
      };

      full =
        pkgs.runCommand "filestash" {
          inherit (backend) meta;

          nativeBuildInputs = [pkgs.makeBinaryWrapper];

          pathConfig = "/proc/self/cwd/state/config.json";
          pathDb = "/proc/self/cwd/state/db";
          pathLog = "/proc/self/cwd/state/log";
          pathPlugins = "/proc/self/cwd/state/plugins";
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
          ln --symbolic ${frontend}    public
          ln --symbolic "$pathConfig"  state/config/config.json
          ln --symbolic "$pathDb"      state/db
          ln --symbolic "$pathLog"     state/log
          ln --symbolic "$pathPlugins" state/plugins
          ln --symbolic "$pathSearch"  state/search
          ln --symbolic "$pathCert"    state/certs
          ln --symbolic "$pathTmp"     cache
        '';

      default = full;
    };
  };
}
