{ pkgs, commonLib, ... }:

let
  testScript = pkgs.writeScript "test-cardano-exporter.sh" ''
    #!${pkgs.stdenv.shell}
  '';
in {
  name = "cardano-exporter-test";
  nodes = {
    machine = { config, pkgs, ... }: {
      imports = [ ../. ];

      services = {
        cardano-exporter = {
          enable = true;
          inherit (commonLib.cardanoLib.environments.testnet)
            genesisFile genesisHash;
        };
        cardano-explorer.enable = true;
        cardano-node = {
          enable = true;
          environment = "testnet";
          inherit (commonLib.cardanoLib.environments.testnet)
            genesisFile genesisHash;
        };
      };

      environment.systemPackages = [ pkgs.postgresql ];
      virtualisation.memorySize = 7000;
    };
  };
  testScript = ''
    sub psql {
      my ($sql) = @_;
      return "sudo -u cardano-exporter psql cexplorer -tAc '" . $sql . "'";
    }

    startAll
    $machine->waitForUnit("cardano-exporter.service");
    $machine->sleep(10);
    $machine->requireActiveUnit("cardano-exporter.service");
    $machine->succeed(psql("\\d"));
    $machine->succeed(psql("SELECT * FROM schema_version;"));
  '';
}
