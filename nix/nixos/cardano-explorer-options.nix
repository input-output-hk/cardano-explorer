{ config, lib, pkgs, ... }:

let
  inherit (import ../../lib.nix { }) environments;
  inherit (lib) types mkOption;

  cfg = config.services.cardano-exporter;
  envConfig = environments.${cfg.environment};
in {
  options.services.cardano-explorer = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable cardano-explorer, a exporter implementing ouroboros protocols
        (the blockchain protocols running cardano).
      '';
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/cardano-exporter";
      description = ''
        Directory to store blockchain data.
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

    secondsToWaitForSocket = mkOption {
      type = types.int;
      default = 60 * 30;
      description = ''
        Amount of seconds to wait for the cardano-node socket to appear.
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
