{ config, pkgs, ... }:
{
  packages = [ pkgs.graphviz ];

  scripts.task-graph.exec = builtins.replaceStrings
    [ "@ROOT@" "@DOT@" ]
    [ config.devenv.root "${pkgs.graphviz}/bin/dot" ]
    (builtins.readFile ./task-graph.sh);
}
