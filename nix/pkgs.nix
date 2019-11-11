############################################################################
# Builds Haskell packages with Haskell.nix
############################################################################

{ pkgs
# Filtered sources of this project
, src
}:

let
  preCheck = ''
    echo pre-check
    initdb --encoding=UTF8 --locale=en_US.UTF-8 --username=postgres $NIX_BUILD_TOP/db-dir
    postgres -D $NIX_BUILD_TOP/db-dir &
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
    cp -vir ${../schema} ../schema
    chmod 600 $PGPASSFILE
    psql postgres postgres <<EOF
      create role $DBUSER with createdb login password '$DBPASS';
      alter user $DBUSER with superuser;
      create database $DBNAME with owner = $DBUSER;
      \\connect $DBNAME
      ALTER SCHEMA public   OWNER TO $DBUSER;
    EOF
  '';

  # This creates the Haskell package set.
  # https://input-output-hk.github.io/haskell.nix/user-guide/projects/
in
  pkgs.haskell-nix.cabalProject' {
    name = "cardano-explorer";
    inherit src;
    modules = [
      # Add source filtering to local packages
      {
        packages.cardano-explorer.src = src + "/cardano-explorer";
        # packages.another-package = src + /another-package;
        packages.ekg.components.library.enableSeparateDataOutput = true;
      }

      # setup a psql server for the tests
      {
        packages = {
          cardano-explorer-db.components.tests.test-db = {
            build-tools = [ pkgs.postgresql ];
            inherit preCheck;
          };
          cardano-explorer.components.tests.test = {
            build-tools = [ pkgs.postgresql ];
            inherit preCheck;
          };
        };
      }
    ];
  }
