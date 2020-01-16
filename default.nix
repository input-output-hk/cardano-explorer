# This is the main nix descriptor function of the
# cardano-explorer project.
#
# This file is a function with default arguments (system, crossSystem, ...)
# to allow some flexiblity when importing it.
#
# It builds the current project from source `./.` as a `cabalProject` using
# haskell.nix.
#
{ system ? builtins.currentSystem
, crossSystem ? null
, config ? {}
, overlays ? []
# nixpkgs-19.09-darwin as of Jan 16th 2020
, nixpkgs ? import (builtins.fetchTarball https://github.com/NixOS/nixpkgs-channels/archive/f69a5b2.tar.gz)
# haskell.nix as of Jan 16th 2020
, haskell-nix ? import (builtins.fetchTarball https://github.com/input-output-hk/haskell.nix/archive/e68599b.tar.gz)

# pkgs is nixpkgs with the haskell-nix as agument. But we'll extend haskell-nix to allow adding additional overlays and config values.
, pkgs ? nixpkgs (haskell-nix // {
    inherit system crossSystem;
    overlays = (haskell-nix.overlays or []) ++ overlays;
    config = (haskell-nix.config or {}) // config;
  })
}:
  pkgs.haskell-nix.cabalProject {
    src = pkgs.haskell-nix.haskellLib.cleanGit { src = ./.; };
  }