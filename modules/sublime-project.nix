{ config, lib, pkgs, ... }:
let
  cfg = config.sublimeProject;
  projectFile = pkgs.writeText "sublime-project" ''
    // Automatically generated from devenv.nix, do not edit!!!
    ${lib.generators.toJSON { } cfg.config}
  '';
in
{
  options.sublimeProject = {
    enable = lib.mkEnableOption "Sublime Text project generation";

    fileName = lib.mkOption {
      type = lib.types.str;
      default = "${config.devenv.root}/${config.name}.sublime-project";
      description = "Path to the generated Sublime Text project file.";
    };

    config = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Attrset rendered as the Sublime Text project JSON.";
    };
  };

  config = lib.mkIf cfg.enable {
    enterShell = ''
      install -m 0644 ${projectFile} ${cfg.fileName}
    '';
  };
}
