############################################################################
#
# Hydra release jobset.
#
# The purpose of this file is to select jobs defined in default.nix and map
# them to all supported build platforms.
#
############################################################################

# The project sources
{ cardano-explorer ? { outPath = ./.; rev = "abcdef"; }

# Function arguments to pass to the project
, projectArgs ? { config = { allowUnfree = false; inHydra = true; }; }

# The systems that the jobset will be built for.
, supportedSystems ? [ "x86_64-linux" "x86_64-darwin" ]

# The systems used for cross-compiling
, supportedCrossSystems ? [ "x86_64-linux" ]

# A Hydra option
, scrubJobs ? true

# Import IOHK common nix lib
# TODO: remove line below, and uncomment the next line
, iohkLib ? import ./lib.nix {}
}:

with (import iohkLib.release-lib) {
  inherit (import ./lib.nix {}) pkgs;

  inherit supportedSystems supportedCrossSystems scrubJobs projectArgs;
  packageSet = import cardano-explorer;
  gitrev = cardano-explorer.rev;
};

with pkgs.lib;

let
  testsSupportedSystems = [ "x86_64-linux" ];
  collectTests = ds: filter (d: elem d.system testsSupportedSystems) (collect isDerivation ds);

  inherit (systems.examples) mingwW64 musl64;
  #inherit (import ./nix/nixos/tests { }) chairmansCluster;
  inherit (import ./docker { }) hydraJob patchedNixpkgs;
  self = import ./. {};
  sources = import ./nix/sources.nix;
  cardano-sources = import "${sources.cardano-node}/nix/sources.nix";

  mkPins = inputs: pkgs.runCommand "ifd-pins" {} ''
    mkdir $out
    cd $out
    ${lib.concatMapStringsSep "\n" (input: "ln -sv ${input.value} ${input.key}") (lib.attrValues (lib.mapAttrs (key: value: { inherit key value; }) inputs))}
  '';

  jobs = {
    native = mapTestOn (packagePlatforms project);
    #"${mingwW64.config}" = mapTestOnCross mingwW64 (packagePlatformsCross project);

    #chairmansCluster = chairmansCluster.x86_64-linux;
    docker-inputs = hydraJob;
    ifd-pins = mkPins {
      inherit (sources) iohk-nix ops-lib cardano-node;
      inherit patchedNixpkgs;
      inherit (self) haskell_nix;
      # TODO, have these in the haskell.nix ifd-pins
      stackageSrc = self.haskell.stackageSrc;
      hackageSrc = self.haskell.hackageSrc;
      # TODO, have these in the cardano-node ifd-pins
      cardano-pkgs = cardano-sources.nixpkgs;
      cardano-haskell = cardano-sources."haskell.nix";
      cardano-iohk-nix = cardano-sources.iohk-nix;
      cardano-hackage = (import sources.nixpkgs (import cardano-sources."haskell.nix")).haskell-nix.hackageSrc;
      cardano-stackage = (import sources.nixpkgs (import cardano-sources."haskell.nix")).haskell-nix.stackageSrc;
    };
  }
  // (
  # This aggregate job is what IOHK Hydra uses to update
  # the CI status in GitHub.
  mkRequiredJob (
    collectTests jobs.native.tests ++
    collectTests jobs.native.benchmarks ++
    [
      jobs.native.cardano-explorer-webapi.x86_64-linux
      jobs.native.cardano-explorer-db-tool.x86_64-linux
      jobs.native.cardano-explorer-node.x86_64-linux
      jobs.native.cardano-sl-core.x86_64-linux
      # TODO: fix chairman cluster once configs stabilize
      #jobs.chairmansCluster
      jobs.docker-inputs
    ]
  ))

  # Build the shell derivation in Hydra so that all its dependencies
  # are cached.
  // mapTestOn (packagePlatforms { inherit (project) shell; });

in jobs
