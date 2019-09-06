############################################################################
# cardano-explorer Nix build
#
# fixme: document top-level attributes and how to build them
#
############################################################################

{ system ? builtins.currentSystem
, crossSystem ? null
, config ? {}
# Import IOHK common nix lib
, commonLib ? import ./lib.nix { inherit system crossSystem config; }
# Use nixpkgs pin from commonLib
, pkgs ? commonLib.pkgs
, customConfig ? {}
}:

let
  haskell = pkgs.callPackage commonLib.nix-tools.haskell {};
  src = commonLib.cleanSourceHaskell ./.;
  util = pkgs.callPackage ./nix/util.nix {};

  # Example of using a package from iohk-nix
  # TODO: Declare packages required by the build.
  inherit (commonLib.rust-packages.pkgs) jormungandr;

  scripts = import ./nix/scripts.nix {
    inherit commonLib customConfig;
  };
  nixosTests = import ./nix/nixos/tests {
    inherit (commonLib) pkgs;
    inherit commonLib;
  };

  # Import the Haskell package set.
  haskellPackages = import ./nix/pkgs.nix {
    inherit pkgs haskell src;
    # Pass in any extra programs necessary for the build as function arguments.
    # Provide cross-compiling secret sauce
    inherit (commonLib.nix-tools) iohk-extras iohk-module;
  };

  mkConnectScript = { genesisFile, genesisHash, name, ... }:
  let
    extraModule = {
      services.cardano-exporter = {
        enable = true;
        inherit genesisFile genesisHash;
        cluster = name;
      };
    };
    eval = pkgs.lib.evalModules {
      prefix = [];
      check = false;
      modules = [ ./module.nix extraModule customConfig ];
      args = { inherit pkgs; };
    };
  in eval.config.services.cardano-exporter.script;

in {
  inherit pkgs commonLib src haskellPackages scripts nixosTests;
  inherit (haskellPackages.cardano-explorer.identifier) version;

  # Grab the executable component of our package.
  inherit (haskellPackages.cardano-explorer.components.exes) cardano-explorer;

  cardano-sl-core = haskellPackages.cardano-explorer-db.components.library;
  cardano-explorer-node = haskellPackages.cardano-explorer-node.components.exes.cardano-explorer-node;
  cardano-explorer-db-manage = haskellPackages.cardano-explorer-db.components.exes.cardano-explorer-db-manage;

  tests = util.collectComponents "tests" util.isIohkSkeleton haskellPackages;
  benchmarks = util.collectComponents "benchmarks" util.isIohkSkeleton haskellPackages;

  # scripts.exporter = commonLib.cardanoLib.forEnvironments mkConnectScript;

  # This provides a development environment that can be used with nix-shell or
  # lorri. See https://input-output-hk.github.io/haskell.nix/user-guide/development/
  shell = haskellPackages.shellFor {
    name = "iohk-skeleton-shell";
    # TODO: List all local packages in the project.
    packages = ps: with ps; [
      cardano-explorer
    ];
    # These programs will be available inside the nix-shell.
    buildInputs =
      with pkgs.haskellPackages; [ hlint stylish-haskell weeder ghcid lentil ];
  };

  # Example of a linting script used by Buildkite.
  checks.lint-fuzz = pkgs.callPackage ./nix/check-lint-fuzz.nix {};

  # Attrset of PDF builds of LaTeX documentation.
  docs = pkgs.callPackage ./docs/default.nix {};
}
