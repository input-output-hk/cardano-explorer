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
      ghc = pkgs.buildPackages.haskell-nix.compiler.${haskellCompiler};
      modules = [{
        packages.cardano-explorer-db.components.tests.test-db = {
          build-tools = [ pkgs.postgresql ];
          preCheck = ''
            echo pre-check
            export PGHOST=/tmp
            initdb --encoding=UTF8 --locale=en_US.UTF-8 --username=postgres $NIX_BUILD_TOP/db-dir
            postgres -k $PGHOST -D $NIX_BUILD_TOP/db-dir &
            PSQL_PID=$!
            sleep 10
            if (echo '\q' | psql postgres postgres); then
              echo "PostgreSQL server is verified to be started."
            else
              echo "Failed to connect to local PostgreSQL server."
              exit 2
            fi
            ls -ltrh $NIX_BUILD_TOP
            DBUSER=nixbld
            DBNAME=nixbld
            export PGPASSFILE=$NIX_BUILD_TOP/pgpass
            echo "/tmp:5432:$DBUSER:$DBUSER:*" > $PGPASSFILE
            cp -vir ${./schema} ../schema
            chmod 600 $PGPASSFILE
            psql postgres postgres <<EOF
              create role $DBUSER with createdb login password '$DBPASS';
              alter user $DBUSER with superuser;
              create database $DBNAME with owner = $DBUSER;
              \\connect $DBNAME
              ALTER SCHEMA public   OWNER TO $DBUSER;
            EOF
          '';
         # the postCheck is required on at least darwin
         postCheck = ''
         kill $PSQL_PID
         '';
        };
      }];
    }))
