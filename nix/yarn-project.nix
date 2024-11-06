# This file is generated by running "yarn install" inside your project.
# Manual changes might be lost - proceed with caution!

{ lib, stdenv, nodejs, git, cacert, fetchurl, writeShellScript, writeShellScriptBin }:
{ src, overrideAttrs ? null, ... } @ args:

let

  yarnBin = fetchurl {
    url = "https://repo.yarnpkg.com/4.5.1/packages/yarnpkg-cli/bin/yarn.js";
    hash = "sha512-NB25OWtuKJ/swwzXqzr2UGDgXr/0s7R1R7J4ueZ7CPSF7NjHkAa0BURiYhQsejgVREXvfxfB1dHefZC/nOcFTQ==";
  };

  cacheFolder = ".yarn/cache";
  lockfile = ./../yarn.lock;

  # Call overrideAttrs on a derivation if a function is provided.
  optionalOverride = fn: drv:
    if fn == null then drv else drv.overrideAttrs fn;

  # Simple stub that provides the global yarn command.
  yarn = writeShellScriptBin "yarn" ''
    exec '${nodejs}/bin/node' '${yarnBin}' "$@"
  '';

  # Common attributes between Yarn derivations.
  drvCommon = {
    # Make sure the build uses the right Node.js version everywhere.
    buildInputs = [ nodejs yarn ];
    # All dependencies should already be cached.
    yarn_enable_network = "0";
    # Tell node-gyp to use the provided Node.js headers for native code builds.
    npm_config_nodedir = nodejs;
  };

  # Comman variables that we set in a Nix build, but not in a Nix shell.
  buildVars = ''
    # Make Yarn produce friendlier logging for automated builds.
    export CI=1
    # Tell node-pre-gyp to never fetch binaries / always build from source.
    export npm_config_build_from_source=true
    # Disable Nixify plugin to save on some unnecessary processing.
    export yarn_enable_nixify=false
  '';

  cacheDrv = stdenv.mkDerivation {
    name = "yarn-cache";
    buildInputs = [ yarn git cacert ];
    buildCommand = ''
      cp --reflink=auto --recursive '${src}' ./src
      cd ./src/
      ${buildVars}
      HOME="$TMP" yarn_enable_global_cache=false yarn_cache_folder="$out" \
        yarn nixify fetch
      rm $out/.gitignore
    '';
    outputHashMode = "recursive";
    outputHash = "sha512-hoLzOaE5fvtkoVutJNQ6o/3sQB2sBuPU3H1knHiLHh6qJniJK1r0nf7qOhePsuqzZgSbAdguot2N8VD+2oRB9A==";
  };

  # Main project derivation.
  project = stdenv.mkDerivation (drvCommon // {
    inherit src;
    name = "@catppuccin/vscode-monorepo";

    configurePhase = ''
      ${buildVars}

      # Copy over the Yarn cache.
      rm -fr '${cacheFolder}'
      mkdir -p '${cacheFolder}'
      cp --reflink=auto --recursive ${cacheDrv}/* '${cacheFolder}/'

      # Yarn may need a writable home directory.
      export yarn_global_folder="$TMP"

      # Ensure global cache is disabled. Cache must be part of our output.
      touch .yarnrc.yml
      sed -i -e '/^enableGlobalCache/d' .yarnrc.yml
      echo 'enableGlobalCache: false' >> .yarnrc.yml

      # Some node-gyp calls may call out to npm, which could fail due to an
      # read-only home dir.
      export HOME="$TMP"

      # running preConfigure after the cache is populated allows for
      # preConfigure to contain substituteInPlace for dependencies as well as the
      # main project. This is necessary for native bindings that maybe have
      # hardcoded values.
      runHook preConfigure

      # Run normal Yarn install to complete dependency installation.
      yarn install --immutable --immutable-cache

      runHook postConfigure
    '';

    buildPhase = ''
      runHook preBuild
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      # Move the package contents to the output directory.
      if grep -q '"workspaces"' package.json; then
        # We can't use `yarn pack` in a workspace setup, because it only
        # packages the outer workspace.
        mkdir -p "$out/libexec"
        mv $PWD "$out/libexec/$name"
      else
        # - If the package.json has a `files` field, only files matching those patterns are copied
        # - Otherwise all files are copied.
        yarn pack --out package.tgz
        mkdir -p "$out/libexec/$name"
        tar xzf package.tgz --directory "$out/libexec/$name" --strip-components=1

        cp --reflink=auto .yarnrc* "$out/libexec/$name"
        cp --reflink=auto ${lockfile} "$out/libexec/$name/yarn.lock"
        cp --reflink=auto --recursive .yarn "$out/libexec/$name"

        # Copy the Yarn linker output into the package.
        cp --reflink=auto --recursive node_modules "$out/libexec/$name"
      fi

      cd "$out/libexec/$name"

      # Invoke a plugin internal command to setup binaries.
      mkdir -p "$out/bin"
      yarn nixify install-bin $out/bin

      # A package with node_modules doesn't need the cache
      yarn cache clean

      runHook postInstall
    '';

    passthru = {
      inherit nodejs;
      yarn-freestanding = yarn;
      yarn = writeShellScriptBin "yarn" ''
        exec '${yarn}/bin/yarn' --cwd '${overriddenProject}/libexec/${overriddenProject.name}' "$@"
      '';
    };
  });

  overriddenProject = optionalOverride overrideAttrs project;

in overriddenProject
