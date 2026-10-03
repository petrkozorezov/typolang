# shellcheck shell=bash
# Shared task loading, validation, status, and filter logic.

TASK_TAGS=(benchmark ci tooling bug feature research architecture performance reliability automation)
TASK_SIZES=(s m l xl)
TASK_PRIORITIES=(critical high normal low)
TASK_STATUSES=(open in_progress blocked closed invalid)
TASK_LIST_FIELDS=(id full-id status priority size tags created title)

task_in_values() {
  local value="$1" candidate
  shift
  for candidate in "$@"; do
    [[ "$value" == "$candidate" ]] && return 0
  done
  return 1
}

task_usage() {
  case "$1" in
    new) echo 'usage: task-new --tags TAG,... --size SIZE --priority PRIORITY short-kebab-case-description' >&2 ;;
    graph) echo 'usage: task-graph [--output FILE] [--status EXPR] [--tag EXPR] [--size EXPR] [--priority EXPR]' >&2 ;;
    check) echo 'usage: task-check [--staged]' >&2 ;;
    *) echo 'usage: task-list [--fields FIELD,...] [--status EXPR] [--tag EXPR] [--size EXPR] [--priority EXPR]' >&2 ;;
  esac
}

task_help() {
  local IFS=,
  task_usage "$1" 2>&1
  case "$1" in
    check)
      cat <<'EOF'
Checks all tasks: metadata, dependencies, and lifecycle files. Invalid tasks fail.
By default reads the working tree, including untracked and ignored task files.
--staged checks the Git index and leftover .work paths of indexed tasks on disk.
Does not change the index or working tree. Blocked tasks are allowed.
EOF
      ;;
    new)
      cat <<'EOF'
Creates tasks/<10-character-base62-id>-<slug>/description.md.
The slug is lowercase kebab-case. Creation within one checkout is sequential.
EOF
      printf '%s\n' "--tags: comma-separated unique values from ${TASK_TAGS[*]}" \
        "--size values: ${TASK_SIZES[*]}" \
        "--priority: ${TASK_PRIORITIES[*]}"
      ;;
    list|graph)
      printf '%s\n' "Default status filter: !closed. Valid statuses: ${TASK_STATUSES[*]}." \
        "--tag values: ${TASK_TAGS[*]}" \
        "--size values: ${TASK_SIZES[*]}. --priority values: ${TASK_PRIORITIES[*]}."
      cat <<'EOF'
Filters accept comma-separated values. Positive values match any; !value excludes.
Different filters combine. An empty expression disables that filter.
Duplicate options and empty or repeated fields are invalid.
EOF
      if [[ "$1" == list ]]; then
        printf '%s\n' "--fields values: ${TASK_LIST_FIELDS[*]}." \
          'Default fields: id,status,priority,size,title. Sorted by priority, then ID.'
      else
        echo '--output FILE writes SVG atomically; default: tasks.svg.'
      fi
      ;;
  esac
}

task_parse_new_cli() {
  if [[ $# -eq 1 && "$1" == --help ]]; then task_help new; exit 0; fi
  local tags='' size='' priority='' seen_tags=false seen_size=false seen_priority=false item
  while (( $# > 1 )); do
    case "$1" in
      --tags)
        [[ "$seen_tags" == false && $# -ge 2 ]] || { task_usage new; return 1; }
        seen_tags=true; tags="$2"
        ;;
      --size)
        [[ "$seen_size" == false && $# -ge 2 ]] || { task_usage new; return 1; }
        seen_size=true; size="$2"
        ;;
      --priority)
        [[ "$seen_priority" == false && $# -ge 2 ]] || { task_usage new; return 1; }
        seen_priority=true; priority="$2"
        ;;
      *) task_usage new; return 1 ;;
    esac
    shift 2
  done
  [[ $# -eq 1 && "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && -n "$tags" ]] || { task_usage new; return 1; }
  task_in_values "$size" "${TASK_SIZES[@]}" || { echo "unknown size: $size" >&2; task_usage new; return 1; }
  task_in_values "$priority" "${TASK_PRIORITIES[@]}" || { echo "unknown priority: $priority" >&2; task_usage new; return 1; }
  if [[ "$tags" == *$'\n'* || "$tags" == ,* || "$tags" == *, || "$tags" == *,,* ]]; then
    echo 'tags expression contains an empty or multiline item' >&2
    task_usage new
    return 1
  fi
  declare -g -a task_new_tags=()
  declare -A seen=()
  IFS=',' read -r -a task_new_tags <<< "$tags"
  for item in "${task_new_tags[@]}"; do
    [[ -n "$item" ]] || { echo 'tags expression contains an empty item' >&2; return 1; }
    task_in_values "$item" "${TASK_TAGS[@]}" || { echo "unknown tag: $item" >&2; return 1; }
    [[ ! -v 'seen[$item]' ]] || { echo "duplicate tag: $item" >&2; return 1; }
    seen[$item]=1
  done
  task_new_slug="$1"
  task_new_size="$size"
  task_new_priority="$priority"
}

task_parse_expr() {
  local kind="$1" expr="$2" allowed_name="$3" item value
  declare -n allowed="$allowed_name"
  declare -gA "task_positive_${kind}=()" "task_negative_${kind}=()"
  declare -n positive="task_positive_${kind}" negative="task_negative_${kind}"
  [[ -n "$expr" ]] || return 0
  if [[ "$expr" == *$'\n'* || "$expr" == ,* || "$expr" == *, || "$expr" == *,,* ]]; then
    echo "$kind expression contains an empty or multiline item" >&2
    return 1
  fi
  IFS=',' read -r -a items <<< "$expr"
  for item in "${items[@]}"; do
    [[ -n "$item" ]] || { echo "$kind expression contains an empty item" >&2; return 1; }
    value="${item#!}"
    task_in_values "$value" "${allowed[@]}" || { echo "unknown $kind: $value" >&2; return 1; }
    if [[ "$item" == \!* ]]; then
      negative[$value]=1
    else
      positive[$value]=1
    fi
  done
}

task_parse_fields() {
  local expr="$1" field
  declare -g -a task_fields=()
  declare -A seen=()
  if [[ -z "$expr" || "$expr" == *$'\n'* || "$expr" == ,* || "$expr" == *, || "$expr" == *,,* ]]; then
    echo 'fields expression is empty or multiline or contains an empty item' >&2
    return 1
  fi
  IFS=',' read -r -a task_fields <<< "$expr"
  for field in "${task_fields[@]}"; do
    task_in_values "$field" "${TASK_LIST_FIELDS[@]}" || { echo "unknown field: $field" >&2; return 1; }
    [[ ! -v 'seen[$field]' ]] || { echo "duplicate field: $field" >&2; return 1; }
    seen[$field]=1
  done
}

task_parse_cli() {
  local command="$1" key
  shift
  if [[ $# -eq 1 && "$1" == --help ]]; then task_help "$command"; exit 0; fi
  declare -A expressions=([status]='!closed' [tag]='' [size]='' [priority]='') seen=()
  local fields_expr='id,status,priority,size,title'
  task_output=''
  while (( $# > 0 )); do
    case "$1" in
      --status|--tag|--size|--priority)
        key="${1#--}"
        [[ ! -v 'seen[$key]' && $# -ge 2 ]] || { task_usage "$command"; return 1; }
        seen[$key]=1; expressions[$key]="$2"; shift 2
        ;;
      --output)
        [[ "$command" == graph && ! -v 'seen[output]' && $# -ge 2 && -n "$2" ]] || { task_usage "$command"; return 1; }
        seen[output]=1; task_output="$2"; shift 2
        ;;
      --fields)
        [[ "$command" == list && ! -v 'seen[fields]' && $# -ge 2 ]] || { task_usage "$command"; return 1; }
        seen[fields]=1; fields_expr="$2"; shift 2
        ;;
      *)
        echo "unexpected argument: $1" >&2
        task_usage "$command"
        return 1
        ;;
    esac
  done
  [[ "$command" != graph || -n "$task_output" ]] || task_output=tasks.svg
  task_parse_expr status "${expressions[status]}" TASK_STATUSES || { task_usage "$command"; return 1; }
  task_parse_expr tag "${expressions[tag]}" TASK_TAGS || { task_usage "$command"; return 1; }
  task_parse_expr size "${expressions[size]}" TASK_SIZES || { task_usage "$command"; return 1; }
  task_parse_expr priority "${expressions[priority]}" TASK_PRIORITIES || { task_usage "$command"; return 1; }
  if [[ "$command" == list ]]; then
    task_parse_fields "$fields_expr" || { task_usage "$command"; return 1; }
  fi
}

task_matches_scalar() {
  local kind="$1" value="$2"
  declare -n positive="task_positive_${kind}" negative="task_negative_${kind}"
  [[ ! -v 'negative[$value]' ]] && { (( ${#positive[@]} == 0 )) || [[ -v 'positive[$value]' ]]; }
}

task_matches_tags() {
  local tags="$1" tag matched=false
  while IFS= read -r tag; do
    [[ -n "$tag" ]] || continue
    [[ ! -v 'task_negative_tag[$tag]' ]] || return 1
    [[ -v 'task_positive_tag[$tag]' ]] && matched=true
  done <<< "$tags"
  (( ${#task_positive_tag[@]} == 0 )) || [[ "$matched" == true ]]
}

task_matches_filters() {
  local name="$1"
  task_matches_scalar status "${task_status[$name]}" &&
    task_matches_scalar size "${task_size[$name]}" &&
    task_matches_scalar priority "${task_priority[$name]}" &&
    task_matches_tags "${task_tags[$name]}"
}

task_read_metadata() {
  awk '
    NR == 1 {
      if ($0 != "---") exit 2
      header=1
      next
    }
    header && $0 == "---" {
      if (block && block_items == 0) exit 2
      end=1
      exit
    }
    header && /^[a-z_]+:/ {
      if (block && block_items == 0) exit 2
      key=$0
      sub(/:.*/, "", key)
      if (seen[key]++) exit 2
      value=$0
      sub(/^[^:]+:[[:space:]]*/, "", value)
      if (key == "created" || key == "size" || key == "priority") {
        if (value == "") exit 2
        print key "\t" value
        block=""
        next
      }
      if (key == "depends_on" || key == "tags") {
        if (value == "[]") {
          print key "_present\t1"
          block=""
          next
        }
        if (value != "") exit 2
        print key "_present\t1"
        block=key
        block_items=0
        next
      }
      exit 2
    }
    header && block && /^[[:space:]]+-[[:space:]]+/ {
      value=$0
      sub(/^[[:space:]]+-[[:space:]]+/, "", value)
      if (value == "") exit 2
      block_items++
      print block "\t" value
      next
    }
    header && /^[[:space:]]*$/ { next }
    header { exit 2 }
    END { if (!end) exit 2 }
  ' "$1"
}

task_load_all() {
  local tasks_root="$1" workspace_root="${2:-$1}" path name metadata kind value dependency id expected_date tag
  declare -ga task_names=()
  declare -gA task_path=() task_created=() task_title=() task_dependencies=()
  declare -gA task_tags=() task_size=() task_priority=() task_ids=()
  declare -gA task_has_progress=() task_has_result=()
  declare -gA task_invalid_reason=() task_status=()
  shopt -s nullglob
  for path in "$tasks_root"/*; do
    [[ -d "$path" ]] || continue
    name="${path##*/}"
    id="${name%%-*}"
    task_names+=("$name")
    task_path[$name]="$path"
    task_created[$name]='-'
    task_title[$name]='-'
    task_dependencies[$name]=''
    task_tags[$name]=''
    task_size[$name]='-'
    task_priority[$name]='-'
    [[ -f "$path/progress.md" ]] && task_has_progress[$name]=1
    [[ -f "$path/result.md" ]] && task_has_result[$name]=1
    if [[ -v 'task_has_progress[$name]' && -v 'task_has_result[$name]' ]]; then
      task_invalid_reason[$name]='progress.md and result.md are mutually exclusive'
    fi
    # The index cannot represent empty or ignored scratch directories left on disk.
    if [[ -e "$path/.work" || -L "$path/.work" || -e "$workspace_root/$name/.work" || -L "$workspace_root/$name/.work" ]]; then
      if [[ ! -v 'task_has_progress[$name]' || -v 'task_has_result[$name]' ]]; then
        task_invalid_reason[$name]='.work requires progress.md without result.md'
      fi
    fi
    if [[ ! "$name" =~ ^[0-9A-Za-z]{10}-[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
      task_invalid_reason[$name]='invalid task directory name'
    elif ! task_base62_decode "$id" >/dev/null; then
      task_invalid_reason[$name]='invalid task ID'
    elif [[ -v 'task_ids[$id]' ]]; then
      task_invalid_reason[$name]="duplicate task ID: $id"
      task_invalid_reason[${task_ids[$id]}]="duplicate task ID: $id"
    else
      task_ids[$id]="$name"
    fi
    if [[ ! -f "$path/description.md" ]]; then
      [[ -n "${task_invalid_reason[$name]:-}" ]] || task_invalid_reason[$name]='missing description.md'
      continue
    fi
    task_title[$name]="$(awk '/^# / { sub(/^# /, ""); print; exit }' "$path/description.md")"
    [[ -n "${task_title[$name]}" ]] || task_title[$name]='-'
    if ! metadata="$(task_read_metadata "$path/description.md")"; then
      task_invalid_reason[$name]='malformed description metadata'
      continue
    fi
    declare -A present=() seen_deps=() seen_tags=()
    while IFS=$'\t' read -r kind value; do
      case "$kind" in
        created) task_created[$name]="$value"; present[created]=1 ;;
        size) task_size[$name]="$value"; present[size]=1 ;;
        priority) task_priority[$name]="$value"; present[priority]=1 ;;
        depends_on_present) present[depends_on]=1 ;;
        tags_present) present[tags]=1 ;;
        depends_on)
          dependency="$value"
          if [[ ! "$dependency" =~ ^[0-9A-Za-z]{10}-[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
            task_invalid_reason[$name]="invalid depends_on entry: $dependency"
          elif [[ "$dependency" == "$name" ]]; then
            task_invalid_reason[$name]='dependency cycle'
          elif [[ -v 'seen_deps[$dependency]' ]]; then
            task_invalid_reason[$name]="duplicate dependency: $dependency"
          else
            seen_deps[$dependency]=1
            task_dependencies[$name]+="${task_dependencies[$name]:+$'\n'}$dependency"
          fi
          ;;
        tags)
          tag="$value"
          if ! task_in_values "$tag" "${TASK_TAGS[@]}"; then
            task_invalid_reason[$name]="unknown tag: $tag"
          elif [[ -v 'seen_tags[$tag]' ]]; then
            task_invalid_reason[$name]="duplicate tag: $tag"
          else
            seen_tags[$tag]=1
            task_tags[$name]+="${task_tags[$name]:+$'\n'}$tag"
          fi
          ;;
      esac
    done <<< "$metadata"
    for kind in created depends_on tags size priority; do
      [[ -v 'present[$kind]' || -n "${task_invalid_reason[$name]:-}" ]] || task_invalid_reason[$name]="missing metadata field: $kind"
    done
    [[ -n "${task_invalid_reason[$name]:-}" || -n "${task_tags[$name]}" ]] || task_invalid_reason[$name]='tags must not be empty'
    [[ -n "${task_invalid_reason[$name]:-}" ]] || task_in_values "${task_size[$name]}" "${TASK_SIZES[@]}" || task_invalid_reason[$name]="unknown size: ${task_size[$name]}"
    [[ -n "${task_invalid_reason[$name]:-}" ]] || task_in_values "${task_priority[$name]}" "${TASK_PRIORITIES[@]}" || task_invalid_reason[$name]="unknown priority: ${task_priority[$name]}"
    if [[ -z "${task_invalid_reason[$name]:-}" ]] && expected_date="$(task_id_created_date "$id" 2>/dev/null)" && [[ "$expected_date" != "${task_created[$name]}" ]]; then
      task_invalid_reason[$name]="created does not match task ID: expected $expected_date"
    fi
    unset present seen_deps seen_tags
  done
  shopt -u nullglob
  for name in "${task_names[@]}"; do
    [[ -z "${task_invalid_reason[$name]:-}" ]] || continue
    while IFS= read -r dependency; do
      [[ -z "$dependency" || -v 'task_path[$dependency]' ]] || { task_invalid_reason[$name]="missing dependency: $dependency"; break; }
    done <<< "${task_dependencies[$name]}"
  done
}

task_mark_cycles_from() {
  local name="$1" dependency member in_cycle=false
  task_visit[$name]=gray
  task_stack+=("$name")
  while IFS= read -r dependency; do
    [[ -n "$dependency" && -v 'task_path[$dependency]' ]] || continue
    if [[ "${task_visit[$dependency]:-}" == gray ]]; then
      in_cycle=false
      for member in "${task_stack[@]}"; do
        [[ "$member" == "$dependency" ]] && in_cycle=true
        [[ "$in_cycle" == true ]] && task_invalid_reason[$member]='dependency cycle'
      done
    elif [[ -z "${task_visit[$dependency]:-}" ]]; then
      task_mark_cycles_from "$dependency"
    fi
  done <<< "${task_dependencies[$name]}"
  unset 'task_stack[${#task_stack[@]}-1]'
  task_visit[$name]=black
}

task_compute_statuses() {
  local name dependency changed
  declare -gA task_visit=()
  declare -ga task_stack=()
  for name in "${task_names[@]}"; do
    [[ -n "${task_visit[$name]:-}" ]] || task_mark_cycles_from "$name"
  done

  changed=true
  while [[ "$changed" == true ]]; do
    changed=false
    for name in "${task_names[@]}"; do
      [[ -z "${task_invalid_reason[$name]:-}" ]] || continue
      while IFS= read -r dependency; do
        [[ -n "$dependency" ]] || continue
        if [[ -n "${task_invalid_reason[$dependency]:-}" ]]; then
          task_invalid_reason[$name]="invalid dependency: $dependency"
          changed=true
          break
        elif [[ -v 'task_has_result[$name]' && ! -v 'task_has_result[$dependency]' ]]; then
          task_invalid_reason[$name]="result.md exists before dependency is closed: $dependency"
          changed=true
          break
        fi
      done <<< "${task_dependencies[$name]}"
    done
  done

  for name in "${task_names[@]}"; do
    if [[ -n "${task_invalid_reason[$name]:-}" ]]; then
      task_status[$name]=invalid
    elif [[ -v 'task_has_result[$name]' ]]; then
      task_status[$name]=closed
    else
      task_status[$name]="$( [[ -v 'task_has_progress[$name]' ]] && echo in_progress || echo open )"
      while IFS= read -r dependency; do
        [[ -z "$dependency" || -v 'task_has_result[$dependency]' ]] || { task_status[$name]=blocked; break; }
      done <<< "${task_dependencies[$name]}"
    fi
  done
}

task_warn_invalid() {
  local name
  for name in "${task_names[@]}"; do
    [[ "${task_status[$name]}" != invalid ]] || printf 'warning: task %s is invalid: %s\n' "$name" "${task_invalid_reason[$name]}" >&2
  done
}

task_dot_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf %s "$value"
}

task_status_color() {
  case "$1" in
    open) echo '#dbeafe' ;;
    in_progress) echo '#ede9fe' ;;
    blocked) echo '#fed7aa' ;;
    closed) echo '#dcfce7' ;;
    invalid) echo '#fecaca' ;;
  esac
}

task_priority_rank() {
  case "$1" in
    critical) echo 0 ;;
    high) echo 1 ;;
    normal) echo 2 ;;
    low) echo 3 ;;
    *) echo 9 ;;
  esac
}
