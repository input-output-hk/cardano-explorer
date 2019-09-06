{ commonLib, customConfig }:
let
  inherit (commonLib.pkgs.lib) mkDefault mkOption modules;
  pkgs = commonLib.pkgs;
  pkgsModule = {
    config._module.args.pkgs = mkDefault pkgs;
  };
  mkExporterScript = envConfig: let
    defaultConfig = {
      environment = envConfig;
      cluster = envConfig.name;
      loggingConfig = ../log-configuration.yaml;
    };

    config = defaultConfig // envConfig // customConfig;
    topologyFile = config.topologyFile or commonLib.mkEdgeTopology {
      inherit (config) hostAddr port nodeId edgeHost edgePort;
    };
    serviceConfig = {
      inherit (config)
        genesisFile
        genesisHash
        stateDir
        signingKey
        delegationCertificate
        consensusProtocol
        pbftThreshold
        hostAddr
        port
        nodeId;
      logger.configFile = config.loggingConfig;
      topology = topologyFile;
    };
    nodeConf = { config.services.cardano-node = serviceConfig; };
    systemdCompat.options.systemd.services = mkOption {};
    nodeScript = (modules.evalModules {
      modules = [
        ./nixos/cardano-exporter-options.nix
        nodeConf
        pkgsModule
        systemdCompat
      ];
    }).config.services.cardano-node.script;
  in pkgs.writeScript "cardano-node-${envConfig.name}" ''
    #!${pkgs.runtimeShell}
    set -euo pipefail
    mkdir -p "state-node-${envConfig.name}"
    cd "state-node-${envConfig.name}"
    ${nodeScript} $@
  '';
  scripts = commonLib.cardanoLib.forEnvironments (environment:
  {
    # node = mkNodeScript environment;
    exporter = mkExporterScript environment;
  });
in scripts
