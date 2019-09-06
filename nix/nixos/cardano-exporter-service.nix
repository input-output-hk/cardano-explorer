{ config, lib, pkgs, ... }:

let
  inherit (lib) mkIf hasPrefix removePrefix;
  inherit (import ../.. { }) cardano-explorer-db-manage;
  cfg = config.services.cardano-exporter;
in {
  config = mkIf cfg.enable (let stateDirBase = "/var/lib/";
  in {
    systemd.services.cardano-exporter = {
      description = "cardano-explorer exporter service";
      after = [ "cardano-explorer-node.service" ];
      wantedBy = [ "multi-user.target" ];

      environment.PGPASSFILE = __toFile "pgpass" "/tmp:5432:cexplorer:*:*";

      path = [
        cfg.package
        cardano-explorer-db-manage
        config.services.postgresql.package
      ];

      script = cfg.script;

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        Restart = "always";
        # This assumes /var/lib/ is a prefix of cfg.stateDir.
        # This is checked as an assertion below.
        StateDirectory = removePrefix stateDirBase cfg.stateDir;
        WorkingDirectory = cfg.stateDir;
      };
    };

    assertions = [{
      assertion = hasPrefix stateDirBase cfg.stateDir;
      message =
        "The option services.cardano-exporter.stateDir should have ${stateDirBase} as a prefix!";
    }];
  });
}
