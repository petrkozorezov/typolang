{ lib, ... }:
let
  moduleNames =
    lib.pipe (builtins.readDir ./.) [
      (lib.filterAttrs (name: type:
        type == "regular"
        && name != "default.nix"
        && lib.hasSuffix ".nix" name
      ))
      builtins.attrNames
      (lib.sort lib.lessThan)
    ];
in
{
  imports = [ ./scripts ] ++ map (name: ./. + "/${name}") moduleNames;
}
