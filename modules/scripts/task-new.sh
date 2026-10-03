#!/usr/bin/env bash
set -euo pipefail

tasks_root="${TASKS_ROOT:-@ROOT@/tasks}"
task_tool_root="${PROJECT_ROOT:-@ROOT@}"
source "$task_tool_root/modules/scripts/task-common.sh"
source "$task_tool_root/modules/scripts/task-id.sh"

task_parse_new_cli "$@"
unix_seconds="$(task_current_unix_seconds)" || { echo 'failed to read current time' >&2; exit 1; }
task_decimal_below "$unix_seconds" "$((TASK_ID_EPOCH + TASK_ID_TIMESTAMP_LIMIT))" || { echo 'current time is outside the task ID range' >&2; exit 1; }
(( unix_seconds >= TASK_ID_EPOCH )) || { echo 'current time is outside the task ID range' >&2; exit 1; }
timestamp=$((unix_seconds - TASK_ID_EPOCH))
exec 3<"${TASK_ID_RANDOM_SOURCE:-/dev/urandom}" || { echo 'failed to open task ID randomness source' >&2; exit 1; }

declare -A occupied=()
for path in "$tasks_root"/*-*; do
  [[ -d "$path" ]] || continue
  name="${path##*/}"
  occupied["${name%%-*}"]=1
done

task_id=''
for ((attempt = 1; attempt <= 16; attempt++)); do
  suffix="$(task_random_suffix)" || { echo 'failed to read task ID randomness' >&2; exit 1; }
  task_id="$(task_id_from_parts "$timestamp" "$suffix")" || { echo 'failed to encode task ID' >&2; exit 1; }
  [[ -v 'occupied[$task_id]' ]] || break
  task_id=''
done
[[ -n "$task_id" ]] || { echo 'failed to generate a unique task ID after 16 attempts' >&2; exit 1; }

task_name="$task_id-$task_new_slug"
task_path="$tasks_root/$task_name"
mkdir "$task_path"

cat > "$task_path/description.md" <<EOF
---
created: $(date -u -d "@$unix_seconds" +%F)
depends_on: []
tags:
$(printf '  - %s\n' "${task_new_tags[@]}")
size: $task_new_size
priority: $task_new_priority
---

# Description

Describe what is needed and why.
EOF

echo "Created tasks/$task_name"
