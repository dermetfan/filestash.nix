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

        /*
        Mostly taken from https://github.com/MatthewCroughan/filestash-nix:
        - libtranscode package
        - libresize package
        - source injection shell code

        Copyright (c) 2022 Matthew Croughan

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
        */
        postPatch = let
          libtranscode = pkgs.stdenv.mkDerivation {
            name = "libtranscode";
            src = "${src}/server/plugin/plg_image_light/deps/src";
            buildInputs = with pkgs; [libraw];
            buildPhase = ''
              $CC -Wall -c libtranscode.c
              ar rcs libtranscode.a libtranscode.o
            '';
            installPhase = ''
              mkdir -p $out/lib
              mv libtranscode.a $out/lib/
            '';
          };

          libresize = pkgs.stdenv.mkDerivation {
            name = "libresize";
            src = "${src}/server/plugin/plg_image_light/deps/src";
            buildInputs = with pkgs; [vips glib];
            nativeBuildInputs = with pkgs; [pkg-config];
            buildPhase = ''
              $CC -Wall -c libresize.c $(pkg-config --cflags glib-2.0)
              ar rcs libresize.a libresize.o
            '';
            installPhase = ''
              mkdir -p $out/lib
              mv libresize.a $out/lib/
            '';
          };

          platform =
            {
              aarch64-linux = "linux_arm";
              x86_64-linux = "linux_amd64";
            }
            .${pkgs.hostPlatform.system}
            or (throw "Unsupported system: ${pkgs.hostPlatform.system}");
        in ''
          sed -i 's#-L./deps -l:libresize_${platform}.a#-L${libresize}/lib -l:libresize.a -lvips#'         server/plugin/plg_image_light/lib_resize_${platform}.go
          sed -i 's#-L./deps -l:libtranscode_${platform}.a#-L${libtranscode}/lib -l:libtranscode.a -lraw#' server/plugin/plg_image_light/lib_transcode_${platform}.go
        '';

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
