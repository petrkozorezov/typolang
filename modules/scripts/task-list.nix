{ config, ... }:
{
  scripts.task-list.exec = builtins.replaceStrings
    [ "@ROOT@" ]
    [ config.devenv.root ]
    (builtins.readFile ./task-list.sh);
}
