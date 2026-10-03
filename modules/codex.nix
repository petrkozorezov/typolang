{ config, lib, pkgs, ... }:
let
  cfg = config.codex;
  toml = pkgs.formats.toml { };
  codexHome = "${config.devenv.state}/codex";
  codexXdgDataHome = "${config.devenv.state}/xdg-data";
  sandboxCodexHome = "/var/lib/codex";
  sandboxReadOnlyResourceNames = [ "plugins" "proxy" "skills" ];
  caEnvironmentVariables = [
    "CODEX_CA_CERTIFICATE" "SSL_CERT_FILE" "REQUESTS_CA_BUNDLE"
    "CURL_CA_BUNDLE" "GIT_SSL_CAINFO" "NODE_EXTRA_CA_CERTS"
    "BUNDLE_SSL_CA_CERT" "CARGO_HTTP_CAINFO" "NPM_CONFIG_CAFILE"
    "PIP_CERT" "npm_config_cafile"
  ];
  permissionProfileName = "project";
  approvalsReviewer = "auto_review";
  approvalPolicy.granular = {
    sandbox_approval = true;
    rules = false;
    skill_approval = false;
    request_permissions = true;
    mcp_elicitations = false;
  };
  upstreamPolicyPath = "codex-rs/prompts/templates/guardian/policy.md";
  reviewerPolicyAddon = ./codex-auto-review-policy.md;
  githubDeveloperInstructions = "Для чтения данных GitHub сначала используй доступные инструменты GitHub MCP. К HTTP переходи, если MCP недоступен или не поддерживает нужную операцию.";
  packageSource =
    if cfg.package ? src then
      cfg.package.src
    else
      throw "codex.package must provide src for the auto-review policy";
  reviewerPolicy = pkgs.runCommand "codex-auto-review-policy.md" { } ''
    upstream=${lib.escapeShellArg "${packageSource}/${upstreamPolicyPath}"}
    if [ ! -f "$upstream" ]; then
      echo "codex.package.src does not contain ${upstreamPolicyPath}" >&2
      exit 1
    fi

    cat "$upstream" > "$out"
    printf '\n\n' >> "$out"
    cat ${reviewerPolicyAddon} >> "$out"
  '';
  moduleConfig = {
    approval_policy = approvalPolicy;
    approvals_reviewer = approvalsReviewer;
    default_permissions = permissionProfileName;
    projects."${config.devenv.root}".trust_level = "trusted";
    permissions.${permissionProfileName} = {
      description = "Project workspace with proxied network and protected Codex state";
      filesystem = {
        ":minimal" = "read";
        ":slash_tmp" = "write";
        ":workspace_roots"."." = "write";
        "/home/codex/**" = "write";
        "/var/lib/codex" =
          lib.genAttrs sandboxReadOnlyResourceNames (_: "read");
      };
      network = {
        enabled = true;
        mode = "limited";
      };
    };
    shell_environment_policy = {
      ignore_default_excludes = false;
      filters = {
        "*PASSWORD*" = "exclude";
        "AWS_*" = "exclude";
        "AZURE_*" = "exclude";
        "GH_*" = "exclude";
        "GITHUB_*" = "exclude";
        "GOOGLE_*" = "exclude";
        "OPENAI_*" = "exclude";
      };
    };
    features = {
      guardian_approval = true;
      network_proxy = true;
      request_permissions_tool = true;
    };
    mcp_servers = lib.optionalAttrs cfg.githubMcp.enable {
      github = {
        enabled = true;
        required = false;
        url = "https://api.githubcopilot.com/mcp/";
        bearer_token_env_var = "GITHUB_PAT_TOKEN";
        http_headers = {
          "X-MCP-Readonly" = "true";
          "X-MCP-Toolsets" = "repos,actions";
        };
        default_tools_approval_mode = "approve";
      };
    };
  } // lib.optionalAttrs cfg.githubMcp.enable {
    developer_instructions = lib.concatStringsSep "\n\n" (lib.filter
      (instruction: instruction != "")
      [ (cfg.extraConfig.developer_instructions or "") githubDeveloperInstructions ]);
  };
  effectiveConfig = lib.recursiveUpdate cfg.extraConfig moduleConfig
    // lib.getAttrs [ "approval_policy" "permissions" "shell_environment_policy" ] moduleConfig;
  resumeDefaultsJson = builtins.toJSON {
    excludeTurns = true;
    approvalPolicy = approvalPolicy;
    inherit approvalsReviewer;
    permissions = permissionProfileName;
  };
  codexConfig = toml.generate "codex-config.toml" effectiveConfig;
  codexRequirements = toml.generate "codex-requirements.toml" {
    guardian_policy_config = builtins.readFile reviewerPolicy;
    features.unified_exec_zsh_fork = false;
    experimental_network = {
      enabled = true;
      managed_allowed_domains_only = false;
    };
  };
  sandboxRunner = pkgs.writeShellScript "codex-outer-sandbox" ''
    set -euo pipefail
    umask 077

    if [ "$#" -lt 2 ]; then
      echo "usage: codex-outer-sandbox STATE_DIR COMMAND [ARG ...]" >&2
      exit 2
    fi

    stateDir="$(${pkgs.coreutils}/bin/realpath -e "$1")"
    shift
    workspaceRoot="$(${pkgs.coreutils}/bin/realpath -e \
      ${lib.escapeShellArg config.devenv.root})"
    case "$stateDir" in
      "$workspaceRoot"/*) ;;
      *) echo "Codex state must be inside $workspaceRoot" >&2; exit 2 ;;
    esac

    case "$PWD" in
      "$workspaceRoot"|"$workspaceRoot"/*) sandboxCwd="$PWD" ;;
      *) sandboxCwd="$workspaceRoot" ;;
    esac

    bwrapArgs=(
      --unshare-all
      --share-net
      --die-with-parent
      --dev /dev
      --proc /proc
    )

    addReadOnlyMount() {
      if [ -e "$1" ]; then
        bwrapArgs+=(--ro-bind "$1" "$1")
      fi
    }

    bwrapArgs+=(
      --ro-bind /nix/store /nix/store
      --ro-bind ${codexRequirements} /etc/codex/requirements.toml
      --bind ${lib.escapeShellArg config.devenv.root} ${lib.escapeShellArg config.devenv.root}
      --bind "$stateDir" ${sandboxCodexHome}
      --tmpfs "$stateDir"
      --perms 0700
      --tmpfs /home/codex
      --perms 1777
      --tmpfs /tmp
      --perms 0700
      --dir /tmp/codex-runtime
      --symlink ${pkgs.bash}/bin/bash /bin/sh
      --ro-bind ${pkgs.coreutils}/bin/env /usr/bin/env
    )

    addReadOnlyMount /etc/group
    addReadOnlyMount /etc/host.conf
    addReadOnlyMount /etc/hosts
    addReadOnlyMount /etc/localtime
    addReadOnlyMount /etc/nsswitch.conf
    addReadOnlyMount /etc/os-release
    addReadOnlyMount /etc/passwd
    addReadOnlyMount /etc/resolv.conf
    addReadOnlyMount /etc/services
    addReadOnlyMount /etc/ssl/certs/ca-certificates.crt
    addReadOnlyMount /etc/zshenv
    addReadOnlyMount /run/current-system
    addReadOnlyMount /nix/var/nix/daemon-socket/socket

    for caVariable in ${lib.escapeShellArgs caEnvironmentVariables}; do
      caSource="''${!caVariable:-}"
      if [ -n "$caSource" ]; then
        if [ ! -f "$caSource" ] || [ ! -r "$caSource" ]; then
          echo "Cannot read CA bundle specified by $caVariable: $caSource" >&2
          exit 1
        fi
        caTarget="/etc/ssl/certs/codex-inherited-$caVariable.pem"
        bwrapArgs+=(--ro-bind "$caSource" "$caTarget" --setenv "$caVariable" "$caTarget")
      fi
    done

    exec ${pkgs.bubblewrap}/bin/bwrap "''${bwrapArgs[@]}" \
      --setenv HOME /home/codex \
      --setenv CODEX_HOME ${sandboxCodexHome} \
      --setenv NIX_REMOTE daemon \
      --setenv XDG_DATA_HOME ${lib.escapeShellArg codexXdgDataHome} \
      --setenv XDG_RUNTIME_DIR /tmp/codex-runtime \
      --chdir "$sandboxCwd" \
      "$@"
  '';
  resumeProbe = pkgs.writeShellScript "codex-resume-probe" ''
    set -euo pipefail

    # This short-lived probe must not start background catalog or MCP requests.
    coproc APP_SERVER {
      ${cfg.package}/bin/codex --disable plugins \
        ${lib.concatMapStringsSep " "
          (name: "-c ${lib.escapeShellArg "mcp_servers.${name}.enabled=false"}")
          (builtins.attrNames (effectiveConfig.mcp_servers or { }))} \
        app-server --listen stdio:// 2>/tmp/app-server.stderr
    }
    serverPid="$APP_SERVER_PID"
    trap 'kill "$serverPid" 2>/dev/null || true' EXIT
    : > /tmp/app-server.stdout

    waitForResponse() {
      local filter="$1"
      shift
      for _ in $(${pkgs.coreutils}/bin/seq 1 100); do
        if IFS= read -r -t 0.1 line <&"''${APP_SERVER[0]}"; then
          printf '%s\n' "$line" >> /tmp/app-server.stdout
          if printf '%s\n' "$line" \
            | ${pkgs.jq}/bin/jq -e "$@" "$filter" >/dev/null; then
            return 0
          fi
        fi
      done
      ${pkgs.coreutils}/bin/cat /tmp/app-server.stdout /tmp/app-server.stderr >&2
      return 1
    }

    printf '%s\n' \
      '{"method":"initialize","id":1,"params":{"clientInfo":{"name":"codex_resume_test","title":"Codex Resume Test","version":"0"},"capabilities":{"experimentalApi":true}}}' \
      >&"''${APP_SERVER[1]}"
    if ! waitForResponse '.id == 1 and has("result")'; then
      echo "Codex app-server did not initialize" >&2
      exit 1
    fi

    printf '%s\n' \
      '{"method":"initialized","params":{}}' \
      '{"method":"configRequirements/read","id":2}' \
      >&"''${APP_SERVER[1]}"
    if ! waitForResponse \
      '.id == 2
        and (.result.requirements.featureRequirements.unified_exec_zsh_fork == false)
        and (.result.requirements.network.enabled == true)
        and .result.requirements.network.managedAllowedDomainsOnly == false'; then
      echo "Codex app-server did not load managed requirements" >&2
      exit 1
    fi

    ${pkgs.jq}/bin/jq -cn \
      --arg threadId "$TEST_THREAD_ID" \
      --argjson defaults ${lib.escapeShellArg resumeDefaultsJson} \
      '$defaults + {threadId: $threadId} | {method: "thread/resume", id: 3, params: .}' \
      >&"''${APP_SERVER[1]}"
    if ! waitForResponse \
      '.id == 3
        and .result.thread.id == $id
        and .result.thread.path == $path
        and .result.approvalPolicy == $defaults.approvalPolicy
        and .result.approvalsReviewer == $defaults.approvalsReviewer
        and .result.activePermissionProfile.id == $defaults.permissions' \
      --arg id "$TEST_THREAD_ID" \
      --arg path "$TEST_ROLLOUT_PATH" \
      --argjson defaults ${lib.escapeShellArg resumeDefaultsJson}; then
      echo "Codex app-server did not resume the synthetic thread" >&2
      exit 1
    fi

    exec {APP_SERVER[1]}>&-
    wait "$serverPid"
    trap - EXIT
  '';
  sandboxProbe = pkgs.writeShellScript "codex-sandbox-probe" ''
    set -euo pipefail

    test "$HOME" = /home/codex
    test "$CODEX_HOME" = ${sandboxCodexHome}
    test "$NIX_REMOTE" = daemon
    test "$XDG_DATA_HOME" = ${lib.escapeShellArg codexXdgDataHome}
    test "$XDG_RUNTIME_DIR" = /tmp/codex-runtime
    test "$PWD" = ${lib.escapeShellArg config.devenv.root}
    if [ "$TEST_HOST_HAS_OS_RELEASE" = 1 ]; then
      test -r /etc/os-release
      if (printf x >> /etc/os-release) 2>/dev/null; then
        echo "/etc/os-release is writable in outer sandbox" >&2
        exit 1
      fi
    else
      test ! -e /etc/os-release
    fi
    test ! -e "$TEST_HOST_SENTINEL"
    test ! -e "/proc/$TEST_HOST_PID"
    touch "$HOME/home-write-probe"
    touch "$XDG_RUNTIME_DIR/runtime-write-probe"
    mkdir -p "$XDG_DATA_HOME"
    xdgProbe="$(${pkgs.coreutils}/bin/mktemp "$XDG_DATA_HOME/codex-xdg-probe.XXXXXX")"
    ${pkgs.coreutils}/bin/rm "$xdgProbe"
    /usr/bin/env true
    "$TEST_SHEBANG_PROBE"
    "$TEST_SH_PROBE"
    ${pkgs.util-linux}/bin/unshare --user true
    ${pkgs.nix}/bin/nix store info --json \
      | ${pkgs.jq}/bin/jq -e '.trusted == false' >/dev/null
    printf '%s\n' ok > "$CODEX_HOME/persistent-probe"
  '';
in
{
  options.codex = {
    enable = lib.mkEnableOption "Codex CLI integration";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.codex;
      defaultText = lib.literalExpression "pkgs.codex";
      description = ''
        Codex CLI package used by the codex script. It must provide compatible
        source for reviewer policy generation.
      '';
    };

    githubMcp.enable = lib.mkEnableOption "the project read-only GitHub MCP";

    extraConfig = lib.mkOption {
      type = toml.type;
      default = { };
      description = "Additional Codex settings; module settings take precedence.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !((cfg.extraConfig.mcp_servers or { }) ? github);
        message = "codex.extraConfig.mcp_servers.github is reserved; use codex.githubMcp.enable";
      }
    ];

    scripts.codex-sandbox-check.exec = ''
      set -euo pipefail

      checkRoot="$(mktemp -d ${lib.escapeShellArg "${config.devenv.state}/codex-check.XXXXXX"})"
      hostSentinel="$(mktemp /tmp/codex-host-sentinel.XXXXXX)"
      outsideState="$(mktemp -d /tmp/codex-outside-state.XXXXXX)"
      sleep 300 &
      hostPid="$!"
      cleanup() {
        kill "$hostPid" 2>/dev/null || true
        rm -rf "$checkRoot" "$outsideState"
        rm -f "$hostSentinel"
      }
      trap cleanup EXIT
      testState="$checkRoot/state"
      mkdir -p "$testState/sessions"
      printf '%s\n' sensitive > "$testState/auth.json"
      printf '%s\n' sensitive > "$testState/history.jsonl"
      printf '%s\n' sensitive > "$testState/sessions/probe.jsonl"
      printf '%s\n' sensitive > "$testState/probe.sqlite"
      printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$checkRoot/env-probe"
      chmod +x "$checkRoot/env-probe"
      printf '%s\n' '#!/bin/sh' 'exit 0' > "$checkRoot/sh-probe"
      chmod +x "$checkRoot/sh-probe"
      ln -s ${codexConfig} "$testState/config.toml"
      ln -s "$outsideState" "$checkRoot/linked-state"

      if ${sandboxRunner} "$checkRoot/linked-state" ${pkgs.coreutils}/bin/true \
        2>/dev/null; then
        echo "outer sandbox accepted a state symlink outside the workspace" >&2
        exit 1
      fi

      (
        ${sandboxRunner} "$testState" ${pkgs.bash}/bin/bash -c \
          'touch "$CODEX_HOME/launcher-ready"; sleep 30' \
          >/dev/null 2>&1 &
        childPid="$!"
        echo "$childPid" > "$checkRoot/bwrap-pid"
        for _ in $(seq 1 100); do
          if [ -f "$testState/launcher-ready" ]; then
            exit 0
          fi
          sleep 0.02
        done
        kill "$childPid" 2>/dev/null || true
        exit 1
      )
      bwrapPid="$(cat "$checkRoot/bwrap-pid")"
      for _ in $(seq 1 100); do
        if ! kill -0 "$bwrapPid" 2>/dev/null \
          || [ "$(awk '{ print $3 }' "/proc/$bwrapPid/stat" 2>/dev/null)" = Z ]; then
          break
        fi
        sleep 0.02
      done
      if kill -0 "$bwrapPid" 2>/dev/null \
        && [ "$(awk '{ print $3 }' "/proc/$bwrapPid/stat" 2>/dev/null)" != Z ]; then
        kill "$bwrapPid"
        echo "outer sandbox survived its launcher" >&2
        exit 1
      fi

      kill -0 "$hostPid"
      if [ -e /etc/os-release ]; then
        hostHasOsRelease=1
      else
        hostHasOsRelease=0
      fi
      TEST_STATE_DIR="$testState" \
      TEST_HOST_HAS_OS_RELEASE="$hostHasOsRelease" \
      TEST_HOST_SENTINEL="$hostSentinel" \
      TEST_HOST_PID="$hostPid" \
      TEST_SHEBANG_PROBE="$checkRoot/env-probe" \
      TEST_SH_PROBE="$checkRoot/sh-probe" \
        ${sandboxRunner} "$testState" ${sandboxProbe}

      test -f "$testState/persistent-probe"
      test "$(cat "$testState/persistent-probe")" = ok
      test "$(stat -c %a "$testState/persistent-probe")" = 600

      cp ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt "$testState/inherited-ca.pem"
      caEnvironment=()
      for caVariable in ${lib.escapeShellArgs caEnvironmentVariables}; do
        caEnvironment+=("$caVariable=$testState/inherited-ca.pem")
      done
      env "''${caEnvironment[@]}" \
        ${sandboxRunner} "$testState" ${pkgs.bash}/bin/bash -c '
          for caVariable in ${lib.escapeShellArgs caEnvironmentVariables}; do
            caPath="''${!caVariable}"
            ${pkgs.diffutils}/bin/cmp ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt "$caPath"
            if (printf x >> "$caPath") 2>/dev/null; then
              echo "inherited CA bundle is writable: $caVariable" >&2
              exit 1
            fi
          done
        '

      logoutState="$checkRoot/logout-state"
      mkdir -p "$logoutState"
      ln -s ${codexConfig} "$logoutState/config.toml"
      printf '%s\n' sk-first-test-key \
        | ${sandboxRunner} "$logoutState" ${cfg.package}/bin/codex \
          login --with-api-key >/dev/null
      ${pkgs.jq}/bin/jq -e \
        '.auth_mode == "apikey" and .OPENAI_API_KEY == "sk-first-test-key"' \
        "$logoutState/auth.json" >/dev/null
      printf '%s\n' sk-second-test-key \
        | ${sandboxRunner} "$logoutState" ${cfg.package}/bin/codex \
          login --with-api-key >/dev/null
      ${pkgs.jq}/bin/jq -e \
        '.auth_mode == "apikey" and .OPENAI_API_KEY == "sk-second-test-key"' \
        "$logoutState/auth.json" >/dev/null
      ${sandboxRunner} "$logoutState" ${cfg.package}/bin/codex logout >/dev/null
      test ! -e "$logoutState/auth.json"

      resumeState="$checkRoot/resume-state"
      threadId="019da1a1-bed9-7a43-88a2-b49d43915021"
      rolloutRelativePath="sessions/2026/09/14/rollout-2026-09-14T00-00-00-$threadId.jsonl"
      rolloutPath="$resumeState/$rolloutRelativePath"
      mkdir -p "$(dirname "$rolloutPath")"
      ln -s ${codexConfig} "$resumeState/config.toml"
      printf '%s\n' \
        '{"timestamp":"2026-09-14T00:00:00Z","type":"session_meta","payload":{"id":"019da1a1-bed9-7a43-88a2-b49d43915021","session_id":"019da1a1-bed9-7a43-88a2-b49d43915021","timestamp":"2026-09-14T00:00:00Z","cwd":"${config.devenv.root}","originator":"codex","cli_version":"0.153.4","source":"cli","model_provider":"openai"}}' \
        '{"timestamp":"2026-09-14T00:00:00Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"synthetic migrated session"}]}}' \
        '{"timestamp":"2026-09-14T00:00:00Z","type":"event_msg","payload":{"type":"user_message","message":"synthetic migrated session","kind":"plain"}}' \
        '{"timestamp":"2026-09-14T00:00:00Z","type":"turn_context","payload":{"cwd":"${config.devenv.root}","approval_policy":"on-request","approvals_reviewer":"user","sandbox_policy":{"type":"read-only"},"active_permission_profile":{"id":":read-only"},"model":"gpt-5.1-codex-mini","summary":"auto"}}' \
        > "$rolloutPath"

      TEST_THREAD_ID="$threadId" \
      TEST_ROLLOUT_PATH="${sandboxCodexHome}/$rolloutRelativePath" \
        ${sandboxRunner} "$resumeState" ${resumeProbe}
      test -r "$resumeState/skills/.system/.codex-system-skills.marker"
      ${pkgs.findutils}/bin/find "$resumeState/skills/.system" \
        -type f -name SKILL.md -print -quit \
        | ${pkgs.gnugrep}/bin/grep -q .
      ${pkgs.findutils}/bin/find "$resumeState/proxy" \
        -maxdepth 1 -type f -name 'ca-bundle-*.pem' -print -quit \
        | ${pkgs.gnugrep}/bin/grep -q .

      printf '%s\n' sensitive > "$resumeState/auth.json"
      printf '%s\n' sensitive > "$resumeState/history.jsonl"
      printf '%s\n' sensitive > "$resumeState/probe.sqlite"

      CODEX_TEST_TOKEN=sensitive \
        PGPASSWORD=sensitive \
        ${sandboxRunner} "$resumeState" ${cfg.package}/bin/codex sandbox -- \
        ${pkgs.bash}/bin/bash -c '
          test -w /tmp
          test -w "$HOME"
          test "$XDG_DATA_HOME" = ${lib.escapeShellArg codexXdgDataHome}
          test -w "$XDG_DATA_HOME"
          test -w "$XDG_RUNTIME_DIR"
          touch "$HOME/inner-home-write-probe"
          xdgProbe="$(${pkgs.coreutils}/bin/mktemp "$XDG_DATA_HOME/codex-inner-xdg-probe.XXXXXX")"
          ${pkgs.coreutils}/bin/rm "$xdgProbe"
          touch "$XDG_RUNTIME_DIR/inner-runtime-write-probe"
          test ! -e /nix/var/nix/daemon-socket/socket
          if ${pkgs.python3}/bin/python -c \
            "import socket; socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)" \
            2>/dev/null; then
            echo "inner sandbox created an arbitrary Unix socket" >&2
            exit 1
          fi
          ${pkgs.findutils}/bin/find "$CODEX_HOME/proxy" \
            -maxdepth 1 -type f -name "ca-bundle-*.pem" -print -quit \
            | ${pkgs.gnugrep}/bin/grep -q .
          if touch "$CODEX_HOME/proxy/inner-write-probe" 2>/dev/null; then
            echo "inner sandbox wrote Codex proxy state" >&2
            exit 1
          fi
          test ! -r "$CODEX_HOME/auth.json"
          test ! -r "$CODEX_HOME/history.jsonl"
          test ! -r "$CODEX_HOME/sessions"
          test ! -r "$CODEX_HOME/probe.sqlite"
          test -r "$CODEX_HOME/skills/.system/.codex-system-skills.marker"
          test -z "''${CODEX_TEST_TOKEN:-}"
          test -z "''${PGPASSWORD:-}"
        '
      printf '%s\n' "codex outer sandbox check passed"
    '';

    scripts.codex-config-check.exec = ''
      set -euo pipefail

      upstream=${lib.escapeShellArg "${packageSource}/${upstreamPolicyPath}"}
      {
        ${pkgs.coreutils}/bin/cat "$upstream"
        printf '\n\n'
        ${pkgs.coreutils}/bin/cat ${reviewerPolicyAddon}
      } | ${pkgs.diffutils}/bin/cmp - ${reviewerPolicy}

      checkHome="$(${pkgs.coreutils}/bin/mktemp -d \
        ${lib.escapeShellArg "${config.devenv.state}/codex-config-check.XXXXXX"})"
      trap '${pkgs.coreutils}/bin/rm -rf "$checkHome"' EXIT
      ${pkgs.coreutils}/bin/ln -s ${codexConfig} "$checkHome/config.toml"
      ${sandboxRunner} "$checkHome" ${cfg.package}/bin/codex \
        app-server --strict-config </dev/null >/dev/null
      ${pkgs.python3}/bin/python - ${codexConfig} \
        ${lib.escapeShellArg (builtins.toJSON effectiveConfig)} <<'PY'
import json
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)
assert config == json.loads(sys.argv[2])
PY
      printf '%s\n' "codex config and auto-review policy check passed"
    '';

    scripts.codex.exec = ''
      set -euo pipefail

      if [ -L ${lib.escapeShellArg codexHome} ]; then
        echo "Codex state directory must not be a symlink" >&2
        exit 1
      fi
      ${pkgs.coreutils}/bin/install -d -m 700 ${lib.escapeShellArg codexHome}
      if [ -L ${lib.escapeShellArg "${codexHome}/auth.json"} ]; then
        ${pkgs.coreutils}/bin/rm ${lib.escapeShellArg "${codexHome}/auth.json"}
      fi
      ${pkgs.coreutils}/bin/ln -sfnT ${codexConfig} \
        ${lib.escapeShellArg "${codexHome}/config.toml"}

      codexArgs=()
      ${lib.optionalString cfg.githubMcp.enable ''
        if [ -z "''${GITHUB_PAT_TOKEN:-}" ]; then
          if githubToken="$(${pkgs.gh}/bin/gh auth token 2>/dev/null)" \
            && [ -n "$githubToken" ]; then
            export GITHUB_PAT_TOKEN="$githubToken"
          fi
          unset githubToken
        fi

        if [ -z "''${GITHUB_PAT_TOKEN:-}" ]; then
          codexArgs+=(-c mcp_servers.github.enabled=false)
        fi
      ''}

      exec ${sandboxRunner} ${lib.escapeShellArg codexHome} \
        ${cfg.package}/bin/codex "''${codexArgs[@]}" "$@"
    '';
  };
}
