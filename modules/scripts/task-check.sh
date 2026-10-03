#!/usr/bin/env bash
set -euo pipefail

task_tool_root="${PROJECT_ROOT:-@ROOT@}"
source "$task_tool_root/modules/scripts/task-common.sh"
source "$task_tool_root/modules/scripts/task-id.sh"

if [[ $# -eq 1 && "$1" == --help ]]; then task_help check; exit 0; fi
if (( $# > 1 )) || [[ $# -eq 1 && "$1" != --staged ]]; then
  task_usage check
  exit 1
fi

if [[ "${1:-}" == --staged ]]; then
  repository_root="$(git rev-parse --show-toplevel)"
  snapshot="$(mktemp -d)"
  trap 'rm -rf "$snapshot"' EXIT
  git -C "$repository_root" ls-files -z -- tasks |
    git -C "$repository_root" checkout-index --stdin -z --prefix="$snapshot/"
  task_load_all "$snapshot/tasks" "$repository_root/tasks"
else
  task_load_all "${TASKS_ROOT:-$task_tool_root/tasks}"
fi

task_compute_statuses
task_warn_invalid
for task_name in "${task_names[@]}"; do
  [[ "${task_status[$task_name]}" != invalid ]] || exit 1
done
