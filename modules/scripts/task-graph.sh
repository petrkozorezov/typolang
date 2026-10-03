#!/usr/bin/env bash
set -euo pipefail

task_tool_root="${PROJECT_ROOT:-@ROOT@}"
source "$task_tool_root/modules/scripts/task-common.sh"
source "$task_tool_root/modules/scripts/task-id.sh"

task_parse_cli graph "$@"
task_load_all "${TASKS_ROOT:-$task_tool_root/tasks}"
task_compute_statuses
task_warn_invalid

output_dir="$(dirname "$task_output")"
[[ -d "$output_dir" ]] || { echo "output directory does not exist: $output_dir" >&2; exit 1; }
dot_file="$(mktemp "${TMPDIR:-/tmp}/task-graph.XXXXXX.dot")"
svg_file="$(mktemp "$output_dir/.task-graph.XXXXXX.svg")"
trap 'rm -f "$dot_file" "$svg_file"' EXIT

declare -A selected=()
{
  echo 'digraph tasks {'
  echo '  rankdir="LR";'
  echo '  node [shape="box", style="filled", fontname="sans-serif"];'
  for task_name in "${task_names[@]}"; do
    task_matches_filters "$task_name" || continue
    selected[$task_name]=1
    node_id="$(task_dot_escape "$task_name")"
    label="$(task_dot_escape "${task_name%%-*}")\\n$(task_dot_escape "${task_title[$task_name]}")\\n$(task_dot_escape "${task_priority[$task_name]}/${task_size[$task_name]} [${task_tags[$task_name]//$'\n'/, }]")\\n$(task_dot_escape "${task_status[$task_name]}")"
    printf '  "%s" [label="%s", fillcolor="%s"];\n' \
      "$node_id" "$label" "$(task_status_color "${task_status[$task_name]}")"
  done
  for task_name in "${task_names[@]}"; do
    [[ -v 'selected[$task_name]' ]] || continue
    while IFS= read -r dependency; do
      [[ -n "$dependency" && -v 'selected[$dependency]' ]] || continue
      printf '  "%s" -> "%s";\n' "$(task_dot_escape "$task_name")" "$(task_dot_escape "$dependency")"
    done <<< "${task_dependencies[$task_name]}"
  done
  echo '}'
} > "$dot_file"

"${GRAPHVIZ_DOT:-@DOT@}" -Tsvg "$dot_file" -o "$svg_file"
mv -f "$svg_file" "$task_output"
