{ config, ... }:
{
  scripts.task-check.exec = builtins.replaceStrings
    [ "@ROOT@" ]
    [ config.devenv.root ]
    (builtins.readFile ./task-check.sh);

  git-hooks.hooks.task-check = {
    enable = true;
    name = "Task state";
    entry = "${config.scripts.task-check.scriptPackage}/bin/task-check --staged";
    pass_filenames = false;
    always_run = true;
  };
}
