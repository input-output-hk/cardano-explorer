{ iohkLib, customConfig }:
with iohkLib.pkgs.lib;
let
  pkgs = iohkLib.pkgs;
  mkConnectScript = envConfig: let
    extraModule =  { lib, ... }: {
      _file = toString ./scripts.nix;
      services.cardano-exporter = {
        enable = true;
        inherit (envConfig) genesisFile genesisHash;
        cluster = envConfig.name;
        postgres.user = lib.mkOverride 900 "*";
      };
    };
    systemdCompat.options = {
      systemd.services = mkOption {};
      services.postgresql = mkOption {};
      users = mkOption {};
    };
    wrap = cfg: {
      services.cardano-exporter = cfg;
    };
    wrappedCustomConfig = { lib, ... }: if lib.isFunction customConfig then wrap (customConfig { inherit lib; }) else wrap customConfig;
    eval = pkgs.lib.evalModules {
      prefix = [];
      modules = [ ./nixos/cardano-exporter-service.nix systemdCompat extraModule wrappedCustomConfig ];
      args = { inherit pkgs; };
    };
  in eval.config.services.cardano-exporter.script;

  scripts = iohkLib.cardanoLib.forEnvironments (environment: {
    exporter = mkConnectScript environment;
  });
in scripts
