############################################################################
# cardano-explorer Nix build
#
# This is the main nix descriptor function of the
# cardano-explorer project.
#
# This file is a function with default arguments (system, crossSystem, ...)
# to allow some flexiblity when importing it.
#
# It builds the current project from source `./.` as a `cabalProject` using
# haskell.nix.
#
############################################################################

{ system ? builtins.currentSystem
, crossSystem ? null
, config ? {}
, overlays ? []
# nixpkgs-19.09-darwin as of Jan 16th 2020
, nixpkgs ? import (builtins.fetchTarball https://github.com/NixOS/nixpkgs-channels/archive/f69a5b2.tar.gz)

# haskell.nix as of Jan 16th 2020
, haskell-nix ? import (builtins.fetchTarball https://github.com/input-output-hk/haskell.nix/archive/ff240d1.tar.gz)

# pkgs is nixpkgs with the haskell-nix as agument. But we'll extend haskell-nix to allow adding additional overlays and config values.
, pkgs ? nixpkgs (haskell-nix // {
    inherit system crossSystem;
    overlays = (haskell-nix.overlays or []) ++ overlays;
    config = (haskell-nix.config or {}) // config;
  })
, haskellCompiler ? "ghc865"
}:
# for CI to build all attributes, we need to recurse into them; so we'll use this helper
let recRecurseIntoAttrs = with pkgs; pred: x: if pred x then recurseIntoAttrs (lib.mapAttrs (n: v: if n == "buildPackages" then v else recRecurseIntoAttrs pred v) x) else x; in
recRecurseIntoAttrs (x: with pkgs; lib.isAttrs x && !lib.isDerivation x)
  # we are only intersted in listing the project packages
  (pkgs.haskell-nix.haskellLib.selectProjectPackages
    # from our project which is based on a cabal project.
    (pkgs.haskell-nix.cabalProject {
        src = pkgs.haskell-nix.haskellLib.cleanGit { src = ./.; };
        ghc = pkgs.haskell-nix.compiler.${haskellCompiler};
    }))
