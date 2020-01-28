{ lib, dockerTools, pkgs, closureInfo }:

let
  self = import ../. {};

  explorerDrv = builtins.readFile pkgs.bashInteractive.drvPath;
  storeDirRe = lib.replaceStrings [ "." ] [ "\\." ] builtins.storeDir;
  storeBaseRe = "[0-9a-df-np-sv-z]{32}-[+_?=a-zA-Z0-9-][+_?=.a-zA-Z0-9-]*";
  re = "(${storeDirRe}/${storeBaseRe}\\.drv)";
  readDrv = pkg: let
    drv = lib.readFile pkg;
    inputDrvs = lib.concatLists (lib.filter lib.isList (__split re drv));
  in { inherit inputDrvs; };
  inputDrvs' = list: drvs:
    lib.foldl (list: drv: if lib.elem drv list then list else inputDrvs' (list ++ lib.singleton drv) (readDrv drv).inputDrvs) list drvs;
  inputDrvs = drv: inputDrvs' [] [ drv ];
  explorerClosure = inputDrvs explorerDrv;

  contents = [
    (map import explorerClosure)
    #pkgs.bashInteractive
  ];

in __trace (__toJSON contents) dockerTools.buildImageWithNixDb {
#in dockerTools.buildImage {
  name = "explorer-builder";
  inherit contents;
  #runAsRoot = ''
  #      echo "Generating the nix database..."
  #      echo "Warning: only the database of the deepest Nix layer is loaded."
  #      echo "         If you want to use nix commands in the container, it would"
  #      echo "         be better to only have one layer that contains a nix store."

  #      export NIX_REMOTE=local?root=$PWD
  #      # A user is required by nix
  #      # https://github.com/NixOS/nix/blob/9348f9291e5d9e4ba3c4347ea1b235640f54fd79/src/libutil/util.cc#L478
  #      export USER=nobody
  #      ${pkgs.nix}/bin/nix-store --load-db < ${closureInfo {rootPaths = contents;}}/registration
  #'';
}
#      runAsRoot = ''
#      #!${pkgs.stdenv.shell}
#      ${dockerTools.shadowSetup}
#      groupadd --system cardano
#      useradd --system --gid cardano cardano
#    '';
