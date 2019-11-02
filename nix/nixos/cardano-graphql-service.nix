{ lib, pkgs, config, ... }:
let
  self = import ../.. { };
  cfg = config.services.cardano-graphql;
  sources = import ../../nix/sources.nix;

  # GraphQL Engine:

    # Method 1: Quick test using Craige's nixpkgs branch now at iohk nixpkgs.
    # Note the last commit breaks things again (c874b1c8111), so pinned at commit 7008719046b

  #nixpkgsHasuraAttrSrc = sources.nixpkgs-hasura-attr;
  #nixpkgsHasuraAttr = import nixpkgsHasuraAttrSrc { config = { allowBroken = true; }; };
  #graphqlEngineAttr = nixpkgsHasuraAttr.pkgs.callPackage (nixpkgsHasuraAttrSrc + "/pkgs/development/libraries/graphql-engine") { };
  #graphqlEngine = graphqlEngineAttr.graphql-engine;

    # Method 2: Bring the changes made to nixpkgs locally, using a compatible nixpkgs rev for callPackage
    # (the base commit under Craige's changes: 933a5c89fdf)
    # Also adjust the haskell.lib properties to not require `config = { allowBroken = true; };`

  nixpkgsHasuraBaseSrc = sources.nixpkgs-hasura-base;
  nixpkgsHasuraAttr = import nixpkgsHasuraBaseSrc {};
  graphqlEngineAttr = nixpkgsHasuraAttr.pkgs.callPackage ./graphql-engine/default.nix {};
  graphqlEngine = graphqlEngineAttr.graphql-engine;


  # FE Component:

    # Method 1: Source is not yet importable via niv, so pull it from a local pre-clone on the appropriate branch

  feBaseSrc = (import /etc/nixos/secrets/fe.nix).path;
  feBaseAttr = import feBaseSrc;
  fe = feBaseAttr.cardano-graphql;

in {
  options = {
    services.cardano-graphql = {
      enable = lib.mkEnableOption "cardano-explorer graphql service";

      host = lib.mkOption {
        type = lib.types.str;
        default = "/var/run/postgresql";
      };

      dbUser = lib.mkOption {
        type = lib.types.str;
        default = "cexplorer";
      };

      password = lib.mkOption {
        type = lib.types.str;
        default = ''""'';
      };

      db = lib.mkOption {
        type = lib.types.str;
        default = "cexplorer";
      };

      dbPort = lib.mkOption {
        type = lib.types.int;
        default = 5432;
      };

      enginePort = lib.mkOption {
        type = lib.types.int;
        default = 9999;
      };

      hasuraUri = lib.mkOption {
        type = lib.types.str;
        default = "https://127.0.0.1:9999/v1/graphql";
      };
    };
  };
  config = {
    systemd.services.graphql-engine = {
      wantedBy = [ "multi-user.target" ];
      script = ''
        ${graphqlEngine}/bin/graphql-engine \
          --host ${cfg.host} \
          -u ${cfg.dbUser} \
          --password ${cfg.password} \
          -d ${cfg.db} \
          --port ${toString cfg.dbPort} \
          serve \
          --server-port ${toString cfg.enginePort}
      '';
    };
    systemd.services.cardano-graphql = {
      wantedBy = [ "multi-user.target" ];
      environment = {
        HASURA_URI = cfg.hasuraUri;
      };
      path = [ nixpkgsHasuraAttr.pkgs.nodejs-12_x ];
      script = ''
        node --version
        node ${fe}/index.js
        #${fe}/bin/cardano-graphql
      '';
    };
  };
}
