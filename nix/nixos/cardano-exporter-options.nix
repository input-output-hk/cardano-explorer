{ config, lib, pkgs, ... }:

let
  commonLib = import ../../lib.nix { };
  inherit (commonLib) environments;
  inherit (commonLib.pkgs.lib) types mkOption;
  inherit (import ../.. { }) cardano-explorer-node;

  cfg = config.services.cardano-exporter;
  envConfig = environments.${cfg.environment};
in {
  options.services.cardano-exporter = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable cardano-exporter, a exporter implementing ouroboros protocols
        (the blockchain protocols running cardano).
      '';
    };

    script = mkOption {
      type = types.str;
      default = ''
        exec cardano-explorer-node \
          --log-config ${cfg.logConfig} \
          --genesis-file ${cfg.genesisFile} \
          --genesis-hash ${cfg.genesisHash} \
          --socket-path ${cfg.socketPath} \
          --schema-dir ${cfg.schemaDir}
      '';
    };

    package = mkOption {
      type = types.package;
      default = cardano-explorer-node;
      defaultText = "cardano-explorer-node";
      description = ''
        The cardano-explorer-node package that should be used
      '';
    };

    environment = mkOption {
      type = types.enum (__attrNames environments);
      default = "testnet";
      description = ''
        environment node will connect to
      '';
    };

    group = mkOption {
      type = types.str;
      default = "cardano-explorer";
      description = ''
        Group to run the service with
      '';
    };

    user = mkOption {
      type = types.str;
      default = "cardano-explorer";
      description = ''
        User to run the service with
      '';
    };

    schemaDir = mkOption {
      type = types.path;
      default = ../../schema;
      description = ''
        The directory containing the migrations.
      '';
    };

    logConfig = mkOption {
      type = types.path;
      default = ../../log-configuration.yaml;
      description = ''
        Configuration file for logging
      '';
    };

    genesisFile = mkOption {
      type = types.path;
      default = envConfig.genesisFile;
      description = ''
        Genesis json file
      '';
    };

    genesisHash = mkOption {
      type = types.nullOr types.str;
      default = envConfig.genesisHash;
      description = ''
        Hash of the genesis file
      '';
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/cardano-exporter";
      description = ''
        Directory to store blockchain data.
      '';
    };

    socketPath = mkOption {
      type = types.path;
      default = "/var/lib/cardano-node/socket/node-core-0.socket";
      description = ''
        path to a cardano-node socket
      '';
    };
  };
}
