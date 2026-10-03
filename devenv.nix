{ config, pkgs, lib, ... }: let

in {
  imports = [
    ./modules
  ];

  name = "typolang";

  packages = with pkgs; [
    git
    devenv
    # для агентов
    yq
    jq
    python3
    ripgrep
    shellcheck
    actionlint
  ];

  env.NIX_CONFIG = "extra-experimental-features = nix-command";

  sublimeProject = {
    enable = true;
    config = {
      folders = [{
          path = ".";
          folder_exclude_patterns = [
            ".git"
            "tmp"
            ".devenv"
            ".direnv"
          ];
          file_exclude_patterns =[ ".devenv*" ];
      }];
      settings = {
        LSP = {
        };
      };
    };
  };

  codex = {
    enable = true;
    githubMcp.enable = true;
    extraConfig = {
      model = "gpt-6.1-sol";
      model_reasoning_effort = "medium";
      suppress_unstable_features_warning = true;
      mcp_servers = {
      };
      tui = {
        status_line = [
          "model-with-reasoning"
          "current-dir"
          "git-branch"
          "context-remaining"
          "weekly-limit"
          "used-tokens"
          "thread-title"
        ];
        show_tooltips = false;
      };
    };
  };

  devenv.warnOnNewVersion = false;
}
