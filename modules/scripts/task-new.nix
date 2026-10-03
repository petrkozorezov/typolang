{ config, ... }:
{
  scripts.task-new.exec = builtins.replaceStrings
    [ "@ROOT@" ]
    [ config.devenv.root ]
    (builtins.readFile ./task-new.sh);
}
