{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.services.cardano-explorer;
  inherit (import ../.. { }) cardano-explorer;
in {
  config = mkIf cfg.enable (let stateDirBase = "/var/lib/";
  in {
    networking.firewall.allowedTCPPorts = [ 3001 8100 ];

    users.groups.${cfg.group}.gid = 10017;

    users.users.${cfg.user} = {
      description = "cardano-explorer daemon user";
      uid = 10017;
      group = cfg.group;
    };

    systemd.services = {
      cardano-explorer-node = {
        description = "cardano-explorer node";
        wantedBy = [ "multi-user.target" ];
        after = [ "postgresql.service" ];
        preStart = ''
          for i in {1..${toString cfg.secondsToWaitForSocket}};
            do test -S ${cfg.socketPath} && break || sleep 1;
          done

          chgrp ${cfg.group} ${config.services.cardano-exporter.socketPath}
          chmod g+w ${config.services.cardano-exporter.socketPath}
        '';
        serviceConfig = {
          PermissionsStartOnly = "true";
          User = cfg.user;
          Group = cfg.group;
          StateDirectory = removePrefix stateDirBase cfg.stateDir;
          WorkingDirectory = cfg.stateDir;
        };
        environment.PGPASSFILE = __toFile "pgpass" "/tmp:5432:cexplorer:*:*";
        script = ''
          ${cardano-explorer}/bin/cardano-explorer
        '';
      };

      cardano-explorer-webapi = {
        description = "cardano-explorer web API";
        wantedBy = [ "multi-user.target" ];
        after = [ "postgresql.service" "cardano-explorer-node" ];
        environment.PGPASSFILE = __toFile "pgpass" "/tmp:5432:cexplorer:*:*";
        serviceConfig = {
          PermissionsStartOnly = "true";
          User = cfg.user;
          Group = cfg.group;
          StateDirectory = removePrefix stateDirBase cfg.stateDir;
          WorkingDirectory = cfg.stateDir;
        };

        script = ''
          ${cardano-explorer}/bin/cardano-explorer
        '';
      };
    };

    services.postgresql = {
      enable = true;
      enableTCPIP = false;
      extraConfig = ''
        max_connections = 200
        shared_buffers = 2GB
        effective_cache_size = 6GB
        maintenance_work_mem = 512MB
        checkpoint_completion_target = 0.7
        wal_buffers = 16MB
        default_statistics_target = 100
        random_page_cost = 1.1
        effective_io_concurrency = 200
        work_mem = 10485kB
        min_wal_size = 1GB
        max_wal_size = 2GB
      '';

      initialScript = pkgs.writeText "explorerPythonAPI-initScript" ''
        CREATE ROLE "cardano-explorer" WITH CREATEDB LOGIN PASSWORD ''';
        CREATE DATABASE cexplorer WITH OWNER "cardano-explorer";
        ALTER SCHEMA public OWNER TO "cardano-explorer";
      '';

      identMap = ''
        explorer-users root cardano-explorer
        explorer-users cardano-explorer cardano-explorer
        explorer-users postgres postgres
      '';

      authentication = ''
        local all all ident map=explorer-users
      '';
    };

    assertions = [{
      assertion = hasPrefix stateDirBase cfg.stateDir;
      message =
        "The option services.cardano-explorer.stateDir should have ${stateDirBase} as a prefix!";
    }];
  });
}
