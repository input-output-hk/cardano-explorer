{ system, compiler, flags, pkgs, hsPkgs, pkgconfPkgs, ... }:
  {
    flags = {};
    package = {
      specVersion = "1.10";
      identifier = { name = "cardano-config"; version = "0.1.0.0"; };
      license = "Apache-2.0";
      copyright = "";
      maintainer = "operations@iohk.io";
      author = "IOHK";
      homepage = "";
      url = "";
      synopsis = "";
      description = "";
      buildType = "Simple";
      };
    components = {
      "library" = {
        depends = [
          (hsPkgs.base)
          (hsPkgs.aeson)
          (hsPkgs.async)
          (hsPkgs.bytestring)
          (hsPkgs.cardano-crypto-wrapper)
          (hsPkgs.cardano-ledger)
          (hsPkgs.cardano-prelude)
          (hsPkgs.cardano-prelude-test)
          (hsPkgs.cardano-shell)
          (hsPkgs.cborg)
          (hsPkgs.contra-tracer)
          (hsPkgs.generic-monoid)
          (hsPkgs.iohk-monitoring)
          (hsPkgs.lobemo-backend-aggregation)
          (hsPkgs.lobemo-backend-editor)
          (hsPkgs.lobemo-backend-ekg)
          (hsPkgs.lobemo-backend-monitoring)
          (hsPkgs.lobemo-scribe-systemd)
          (hsPkgs.network)
          (hsPkgs.optparse-applicative)
          (hsPkgs.ouroboros-consensus)
          (hsPkgs.ouroboros-network)
          (hsPkgs.iproute)
          (hsPkgs.safe-exceptions)
          (hsPkgs.string-conv)
          (hsPkgs.stm)
          (hsPkgs.text)
          ];
        };
      };
    } // {
    src = (pkgs.lib).mkDefault (pkgs.fetchgit {
      url = "https://github.com/input-output-hk/cardano-node";
      rev = "38b6133f5678bbc32712f207b049d49e1cc274d2";
      sha256 = "0bhyj71qyk68ynxiqgnr4wg518q9zdjf5cs478ggfy146im1cqjy";
      });
    postUnpack = "sourceRoot+=/cardano-config; echo source root reset to \$sourceRoot";
    }