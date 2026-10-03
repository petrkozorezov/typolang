#!/usr/bin/env bash
set -euo pipefail

task_tool_root="${PROJECT_ROOT:-@ROOT@}"
source "$task_tool_root/modules/scripts/task-common.sh"
source "$task_tool_root/modules/scripts/task-id.sh"

task_parse_cli list "$@"
task_load_all "${TASKS_ROOT:-$task_tool_root/tasks}"
task_compute_statuses
task_warn_invalid

task_list_field_value() {
  local field="$1" name="$2"
  case "$field" in
    id) printf %s "${name%%-*}" ;;
    full-id) printf %s "$name" ;;
    status) printf %s "${task_status[$name]}" ;;
    priority) printf %s "${task_priority[$name]}" ;;
    size) printf %s "${task_size[$name]}" ;;
    tags) printf %s "${task_tags[$name]//$'\n'/,}" ;;
    created) printf %s "${task_created[$name]}" ;;
    title) printf %s "${task_title[$name]}" ;;
  esac
}

declare -A field_headers=(
  [id]=ID
  [full-id]=FULL-ID
  [status]=STATUS
  [priority]=PRIORITY
  [size]=SIZE
  [tags]=TAGS
  [created]=CREATED
  [title]=TITLE
)
declare -A field_widths=()
rows=()
selected_names=()
for field in "${task_fields[@]}"; do
  field_widths[$field]=${#field_headers[$field]}
done
for task_name in "${task_names[@]}"; do
  task_matches_filters "$task_name" || continue
  rows+=("$(task_priority_rank "${task_priority[$task_name]}")"$'\t'"${task_name%%-*}"$'\t'"$task_name")
done
while IFS=$'\t' read -r _ _ task_name; do
  [[ -n "$task_name" ]] || continue
  selected_names+=("$task_name")
  for field in "${task_fields[@]}"; do
    value="$(task_list_field_value "$field" "$task_name")"
    (( ${#value} <= field_widths[$field] )) || field_widths[$field]=${#value}
  done
done < <(printf '%s\n' "${rows[@]}" | LC_ALL=C sort -t $'\t' -k1,1n -k2,2)

last_index=$((${#task_fields[@]} - 1))
for index in "${!task_fields[@]}"; do
  field="${task_fields[$index]}"
  if (( index == last_index )); then
    printf '%s\n' "${field_headers[$field]}"
  else
    value="${field_headers[$field]}"
    printf '%s' "$value"
    printf '%*s' "$((field_widths[$field] - ${#value} + 2))" ''
  fi
done
for task_name in "${selected_names[@]}"; do
  for index in "${!task_fields[@]}"; do
    field="${task_fields[$index]}"
    value="$(task_list_field_value "$field" "$task_name")"
    if (( index == last_index )); then
      printf '%s\n' "$value"
    else
      printf '%s' "$value"
      printf '%*s' "$((field_widths[$field] - ${#value} + 2))" ''
    fi
  done
done
