{ system, compiler, flags, pkgs, hsPkgs, pkgconfPkgs, ... }:
  {
    flags = {};
    package = {
      specVersion = "1.10";
      identifier = { name = "cardano-explorer-db-node"; version = "0.1.0.0"; };
      license = "Apache-2.0";
      copyright = "(c) 2019 IOHK";
      maintainer = "operations@iohk.io";
      author = "IOHK Engineering Team";
      homepage = "https://github.com/input-output-hk/cardano-explorer";
      url = "";
      synopsis = "The DB node for the Cardano Block Explorer";
      description = "A Cardano node that follows the Cardano chain and inserts data from the\nchain into a PostgresQL database.";
      buildType = "Simple";
      };
    components = {
      "library" = {
        depends = [
          (hsPkgs.base)
          (hsPkgs.bytestring)
          (hsPkgs.cardano-explorer-core)
          (hsPkgs.conduit)
          (hsPkgs.conduit-extra)
          (hsPkgs.containers)
          (hsPkgs.directory)
          (hsPkgs.extra)
          (hsPkgs.filepath)
          (hsPkgs.monad-logger)
          (hsPkgs.persistent)
          (hsPkgs.persistent-postgresql)
          (hsPkgs.resourcet)
          (hsPkgs.text)
          (hsPkgs.time)
          (hsPkgs.transformers)
          ];
        };
      exes = {
        "cardano-explorer-db-node" = {
          depends = [ (hsPkgs.base) (hsPkgs.cardano-explorer-db-node) ];
          };
        "cardano-explorer-db-manage" = {
          depends = [
            (hsPkgs.base)
            (hsPkgs.cardano-explorer-db-node)
            (hsPkgs.optparse-applicative)
            ];
          };
        };
      tests = {
        "test" = {
          depends = [
            (hsPkgs.base)
            (hsPkgs.cardano-explorer-db-node)
            (hsPkgs.hedgehog)
            ];
          };
        };
      };
    } // rec { src = (pkgs.lib).mkDefault ../.././cardano-explorer-db-node; }