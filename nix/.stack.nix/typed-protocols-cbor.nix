{ system, compiler, flags, pkgs, hsPkgs, pkgconfPkgs, ... }:
  {
    flags = {};
    package = {
      specVersion = "1.10";
      identifier = { name = "typed-protocols-cbor"; version = "0.1.0.0"; };
      license = "Apache-2.0";
      copyright = "2019 Input Output (Hong Kong) Ltd.";
      maintainer = "alex@well-typed.com, duncan@well-typed.com, marcin.szamotulski@iohk.io";
      author = "Alexander Vieth, Duncan Coutts, Marcin Szamotulski";
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
          (hsPkgs.bytestring)
          (hsPkgs.cborg)
          (hsPkgs.serialise)
          (hsPkgs.io-sim-classes)
          (hsPkgs.typed-protocols)
          ];
        };
      tests = {
        "test-typed-protocols-cbor" = {
          depends = [
            (hsPkgs.base)
            (hsPkgs.bytestring)
            (hsPkgs.cborg)
            (hsPkgs.serialise)
            (hsPkgs.QuickCheck)
            (hsPkgs.tasty)
            (hsPkgs.tasty-quickcheck)
            (hsPkgs.io-sim-classes)
            (hsPkgs.typed-protocols)
            ];
          };
        };
      };
    } // {
    src = (pkgs.lib).mkDefault (pkgs.fetchgit {
      url = "https://github.com/input-output-hk/ouroboros-network";
      rev = "7a6c4071003bfd3d9829972c21bf43709447c626";
      sha256 = "15bjap25cwpasl2wjzdd35nwfkcznjhvnnpy944lx9dw266hldsk";
      });
    postUnpack = "sourceRoot+=/typed-protocols-cbor; echo source root reset to \$sourceRoot";
    }