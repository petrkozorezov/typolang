#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$project_root/modules/scripts/task-id.sh"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT
tasks_root="$fixture_root/tasks"; mkdir "$tasks_root"

id_for() { task_id_from_parts "$1" "$2"; }
id1="$(id_for 21340800 1)"; id2="$(id_for 21340800 2)"; id3="$(id_for 21340800 3)"; id4="$(id_for 21340800 4)"
id5="$(id_for 21340800 5)"; id6="$(id_for 21340800 6)"; id7="$(id_for 21340800 7)"; id8="$(id_for 21340800 8)"
id9="$(id_for 21340800 9)"; id10="$(id_for 21340800 10)"; id11="$(id_for 21340800 11)"
id12="$(id_for 21340800 12)"; id13="$(id_for 21340800 13)"; id14="$(id_for 21340800 14)"
id15="$(id_for 21340800 15)"
id16="$(id_for 21340800 16)"; id17="$(id_for 21340800 17)"; id18="$(id_for 21340800 18)"
id19="$(id_for 21340800 19)"; id20="$(id_for 21340800 20)"
id21="$(id_for 21340800 21)"; id22="$(id_for 21340800 22)"; id23="$(id_for 21340800 23)"
id24="$(id_for 21340800 24)"; id25="$(id_for 21340800 25)"; id26="$(id_for 21340800 26)"
id27="$(id_for 21340800 27)"; id28="$(id_for 21340800 28)"; id29="$(id_for 21340800 29)"

make_task() {
  local id="$1" slug="$2" title="$3" deps="${4:-}" tags="${5:-tooling}" size="${6:-m}" priority="${7:-normal}"
  local name="$id-$slug"; mkdir "$tasks_root/$name"
  {
    echo '---'; echo 'created: 2026-09-05'
    if [[ -z "$deps" ]]; then echo 'depends_on: []'; else echo 'depends_on:'; while IFS= read -r dep; do echo "  - $dep"; done <<< "$deps"; fi
    echo 'tags:'; IFS=',' read -r -a tag_items <<< "$tags"; for tag in "${tag_items[@]}"; do echo "  - $tag"; done
    echo "size: $size"; echo "priority: $priority"; echo '---'; echo; echo "# $title"
  } > "$tasks_root/$name/description.md"
  printf %s "$name"
}

run_list() { PROJECT_ROOT="$project_root" TASKS_ROOT="$tasks_root" bash "$project_root/modules/scripts/task-list.sh" "$@"; }
assert_contains() { [[ "$1" == *"$2"* ]] || { echo "missing: $2" >&2; exit 1; }; }
assert_not_contains() { [[ "$1" != *"$2"* ]] || { echo "unexpected: $2" >&2; exit 1; }; }

closed="$(make_task "$id1" closed Closed '' tooling s normal)"; touch "$tasks_root/$closed/result.md"
open_task="$(make_task "$id2" open Open '' architecture xl low)"
planned_open="$(make_task "$id3" planned-open 'Planned open' '' architecture,feature l high)"; touch "$tasks_root/$planned_open/plan.md"
blocked="$(make_task "$id4" blocked Blocked "$open_task" tooling m critical)"; touch "$tasks_root/$blocked/plan.md"
premature="$(make_task "$id5" premature Premature "$open_task")"; touch "$tasks_root/$premature/plan.md" "$tasks_root/$premature/result.md"
missing="$(make_task "$id6" missing Missing "0000000001-absent")"
cycle_a_name="$id7-cycle-a"; cycle_b_name="$id8-cycle-b"
make_task "$id7" cycle-a 'Cycle A' "$cycle_b_name" >/dev/null; make_task "$id8" cycle-b 'Cycle B' "$cycle_a_name" >/dev/null
escaped="$(make_task "$id9" escaped 'A "quoted" \ title' '' tooling m normal)"
malformed="$(make_task "$id10" malformed Malformed)"; sed -i 's/size: m/size: huge/' "$tasks_root/$malformed/description.md"
duplicate_id="$id11"
make_task "$duplicate_id" duplicate-a 'Duplicate A' >/dev/null; make_task "$duplicate_id" duplicate-b 'Duplicate B' >/dev/null
unknown_tag="$(make_task "$id12" unknown-tag 'Unknown tag')"; sed -i 's/  - tooling/  - mystery/' "$tasks_root/$unknown_tag/description.md"
duplicate_tag="$(make_task "$id13" duplicate-tag 'Duplicate tag' '' tooling,tooling)"
missing_priority="$(make_task "$id14" missing-priority 'Missing priority')"; sed -i '/^priority:/d' "$tasks_root/$missing_priority/description.md"
empty_dependencies="$(make_task "$id15" empty-dependencies 'Empty dependencies')"; sed -i 's/depends_on: \[\]/depends_on:/' "$tasks_root/$empty_dependencies/description.md"
transitive="$(make_task "$id16" transitive 'Transitive blocked' "$blocked")"
invalid_dependent="$(make_task "$id17" invalid-dependent 'Invalid dependent' "$cycle_a_name")"
decision_without_plan="$(make_task "$id18" decision-without-plan 'Decision without plan')"; touch "$tasks_root/$decision_without_plan/decisions.md"
make_task "$id19" russian-short 'Короткий заголовок' '' architecture m normal >/dev/null
make_task "$id20" russian-long 'Существенно более длинный русский заголовок' '' architecture m normal >/dev/null
in_progress="$(make_task "$id21" in-progress 'In progress')"; touch "$tasks_root/$in_progress/plan.md" "$tasks_root/$in_progress/progress.md"
progress_blocked="$(make_task "$id22" progress-blocked 'Blocked in progress' "$open_task")"; touch "$tasks_root/$progress_blocked/plan.md" "$tasks_root/$progress_blocked/progress.md"
progress_without_plan="$(make_task "$id23" progress-without-plan 'Progress without plan')"; touch "$tasks_root/$progress_without_plan/progress.md"
closed_progress_without_plan="$(make_task "$id24" closed-progress-without-plan 'Closed progress without plan')"; touch "$tasks_root/$closed_progress_without_plan/progress.md" "$tasks_root/$closed_progress_without_plan/result.md"
missing_description="$id25-missing-description"; mkdir "$tasks_root/$missing_description"; touch "$tasks_root/$missing_description/progress.md"
closed_with_progress="$(make_task "$id26" closed-with-progress 'Closed with progress')"; touch "$tasks_root/$closed_with_progress/plan.md" "$tasks_root/$closed_with_progress/progress.md" "$tasks_root/$closed_with_progress/result.md"
historical_closed="$(make_task "$id27" historical-closed 'Historical closed')"; touch "$tasks_root/$historical_closed/plan.md" "$tasks_root/$historical_closed/result.md"
cancelled="$(make_task "$id28" cancelled Cancelled)"; touch "$tasks_root/$cancelled/result.md"
planned_with_decision="$(make_task "$id29" planned-with-decision 'Planned with decision')"; touch "$tasks_root/$planned_with_decision/plan.md" "$tasks_root/$planned_with_decision/decisions.md"
touch "$tasks_root/$planned_with_decision/implementation-report.md" # Historical name does not set in_progress.
declare -a lifecycle_names=() lifecycle_statuses=()
for mask in {0..15}; do
  combo="$(make_task "$(id_for 21340800 $((30 + mask)))" "lifecycle-$mask" "Lifecycle $mask")"
  (( mask & 1 )) && touch "$tasks_root/$combo/plan.md"
  (( mask & 2 )) && touch "$tasks_root/$combo/progress.md"
  (( mask & 4 )) && touch "$tasks_root/$combo/decisions.md"
  (( mask & 8 )) && touch "$tasks_root/$combo/result.md"
  lifecycle_names[$mask]="$combo"
  if (( (mask & 10) == 10 )); then
    lifecycle_statuses[$mask]=invalid
  elif (( mask & 8 )); then
    lifecycle_statuses[$mask]=closed
  elif (( mask & 2 )); then
    lifecycle_statuses[$mask]=in_progress
  else
    lifecycle_statuses[$mask]=open
  fi
done
mkdir "$tasks_root/not-a-task"
mkdir "$tasks_root/bad\"name"

output="$(run_list 2>"$fixture_root/warnings")"
[[ "$(sed -n '1p' <<< "$output" | tr -s ' ')" == 'ID STATUS PRIORITY SIZE TITLE' ]]
assert_not_contains "$output" "$id1"
assert_contains "$output" "$id2  open"
assert_contains "$output" "$id3  open"
assert_contains "$output" "$id21  in_progress"
assert_contains "$output" "$id22  blocked"
assert_contains "$output" "$id4  blocked"
assert_contains "$output" "$id16  blocked"
assert_contains "$output" "$id5  invalid"
assert_contains "$output" "$id17  invalid"
assert_contains "$output" "$id18  open"
assert_contains "$output" "$id23  in_progress"
assert_contains "$output" "$id24  invalid"
assert_contains "$output" "$id29  open"
assert_contains "$output" 'critical'
assert_contains "$output" 'high'
[[ "$(wc -l < "$fixture_root/warnings")" -eq 21 ]]
assert_not_contains "$(<"$fixture_root/warnings")" "$progress_without_plan"
assert_contains "$(<"$fixture_root/warnings")" "$closed_progress_without_plan"
all_statuses="$(run_list --status '' 2>/dev/null)"
for mask in {0..15}; do
  assert_contains "$all_statuses" "${lifecycle_names[$mask]%%-*}  ${lifecycle_statuses[$mask]}"
done
output="$(run_list --status invalid)"; assert_contains "$output" "$id24  invalid"
output="$(run_list --status in_progress)"; assert_contains "$output" "$id23"
touch "$tasks_root/$progress_without_plan/plan.md"
output="$(run_list --status in_progress)"; assert_contains "$output" "$id23"
touch "$tasks_root/$progress_without_plan/decisions.md"
output="$(run_list --status in_progress)"; assert_contains "$output" "$id23"
rm "$tasks_root/$progress_without_plan/plan.md"
output="$(run_list --status in_progress)"; assert_contains "$output" "$id23"
output="$(run_list --status closed)"; assert_contains "$output" "$id1"; assert_not_contains "$output" "$id26"; assert_contains "$output" "$id27"; assert_contains "$output" "$id28"; assert_not_contains "$output" "$id2"
output="$(run_list --status in_progress)"; assert_contains "$output" "$id21"; assert_not_contains "$output" "$id22"
output="$(run_list --status '!in_progress')"; assert_not_contains "$output" "$id21"
output="$(run_list --status '' --tag architecture --size 'l,xl' --priority '!low')"; assert_contains "$output" "$id3"; assert_not_contains "$output" "$id2"
output="$(run_list --status '' --priority 'critical,high')"; first="$(sed -n '2p' <<< "$output")"; assert_contains "$first" "$id4"
output="$(run_list --status '' --tag architecture --fields 'title,full-id,tags,created,id')"
[[ "$(sed -n '1p' <<< "$output" | tr -s ' ')" == 'TITLE FULL-ID TAGS CREATED ID' ]]
assert_contains "$output" "$planned_open"
assert_contains "$output" 'architecture,feature'
awk 'NR == 1 { created=index($0, "CREATED"); next } index($0, "2026-09-05") != created { exit 1 }' <<< "$output"
output="$(run_list --status '' --priority 'critical,high' --fields id)"
[[ "$(sed -n '1p' <<< "$output")" == ID ]]
[[ "$(sed -n '2p' <<< "$output")" == "$id4" ]]
output="$(run_list --status open --tag architecture --fields title,id)"
awk 'NR == 1 { id_column=index($0, "ID"); next } index($0, substr($0, length($0) - 9)) != id_column { exit 1 }' <<< "$output"
assert_contains "$output" 'Короткий заголовок'
assert_contains "$output" 'Существенно более длинный русский заголовок'

touch "$tasks_root/$open_task/result.md"
output="$(run_list --status in_progress)"; assert_contains "$output" "$id22"
rm "$tasks_root/$open_task/result.md"

for args in '--status nope' '--status draft' '--status active' '--tag nope' '--size huge' '--priority urgent' '--status' '--tag architecture --tag tooling' 'draft'; do
  if eval "run_list $args" >/dev/null 2>"$fixture_root/error"; then echo "expected CLI failure: $args" >&2; exit 1; fi
  assert_contains "$(<"$fixture_root/error")" 'usage:'
done
for args in '--fields nope' '--fields id,id' '--fields ,' '--fields id,' '--fields id --fields title'; do
  if eval "run_list $args" >/dev/null 2>"$fixture_root/error"; then echo "expected fields failure: $args" >&2; exit 1; fi
done
if run_list --fields $'id\ntitle' >/dev/null 2>"$fixture_root/error"; then echo 'expected multiline fields failure' >&2; exit 1; fi
if PROJECT_ROOT="$project_root" TASKS_ROOT="$tasks_root" bash "$project_root/modules/scripts/task-graph.sh" --fields id >/dev/null 2>"$fixture_root/error"; then echo 'expected graph fields failure' >&2; exit 1; fi
for command in task-new task-list task-graph; do
  help="$(PROJECT_ROOT="$project_root" bash "$project_root/modules/scripts/$command.sh" --help)"
  assert_contains "$help" "usage: $command"
  assert_contains "$help" 'tooling'
  assert_contains "$help" 's,m,l,xl'
done
for args in '--tag architecture,' '--priority high,'; do
  if eval "run_list $args" >/dev/null 2>"$fixture_root/error"; then echo "expected trailing comma failure: $args" >&2; exit 1; fi
done
if run_list --tag $'architecture\nfeature' >/dev/null 2>"$fixture_root/error"; then echo 'expected multiline filter failure' >&2; exit 1; fi

# Independent codec checks, including width, alphabet, range, and transitions.
for value in 0 1 61 62 3843 3844 576460752303423487; do
  encoded="$(task_base62_encode "$value")"; [[ ${#encoded} -eq 10 ]]; [[ "$(task_base62_decode "$encoded")" == "$value" ]]
done
[[ "$(task_base62_encode 61)" == 000000000z ]]; [[ "$(task_base62_encode 62)" == 0000000010 ]]
for invalid in '' 000000000 00000000000 000000000- zzzzzzzzzz; do ! task_base62_decode "$invalid" >/dev/null 2>&1; done
! task_base62_encode 576460752303423488 >/dev/null 2>&1
! task_base62_encode 18446744073709551616 >/dev/null 2>&1
! task_base62_encode 999999999999999999999999999999999999999999 >/dev/null 2>&1
[[ "$(task_id_from_parts 0 0)" < "$(task_id_from_parts 0 1)" ]]; [[ "$(task_id_from_parts 0 134217727)" < "$(task_id_from_parts 1 0)" ]]
! task_id_from_parts 4294967296 0 >/dev/null 2>&1; ! task_id_from_parts 0 134217728 >/dev/null 2>&1
! task_id_from_parts 18446744073709551616 0 >/dev/null 2>&1
[[ "$(task_id_created_date "$(task_id_from_parts 0 0)")" == 2026-01-01 ]]

# task-new uses one timestamp, retries a colliding suffix, and writes complete metadata.
new_root="$fixture_root/new-tasks"; mkdir "$new_root"
now=1788566400; timestamp=$((now - TASK_ID_EPOCH)); collision_id="$(task_id_from_parts "$timestamp" 1)"
make_new_existing="$new_root/$collision_id-existing"; mkdir "$make_new_existing"
printf '\0\0\0\1\0\0\0\2' > "$fixture_root/random"
TASK_ID_NOW="$now" TASK_ID_RANDOM_SOURCE="$fixture_root/random" PROJECT_ROOT="$project_root" TASKS_ROOT="$new_root" \
  bash "$project_root/modules/scripts/task-new.sh" --tags architecture,feature --size m --priority high generated > "$fixture_root/new-output"
generated_id="$(task_id_from_parts "$timestamp" 2)"; generated="$new_root/$generated_id-generated/description.md"
[[ -f "$generated" ]]; assert_contains "$(<"$generated")" 'created: 2026-09-05'; assert_contains "$(<"$generated")" 'priority: high'
for args in 'generated' '--tags architecture --size m --priority high Bad' '--tags architecture,architecture --size m --priority high generated'; do
  if eval "TASK_ID_NOW=$now TASK_ID_RANDOM_SOURCE=$fixture_root/random PROJECT_ROOT=$project_root TASKS_ROOT=$new_root bash $project_root/modules/scripts/task-new.sh $args" >/dev/null 2>&1; then echo "expected task-new failure: $args" >&2; exit 1; fi
done
if TASK_ID_NOW="$now" TASK_ID_RANDOM_SOURCE="$fixture_root/random" PROJECT_ROOT="$project_root" TASKS_ROOT="$new_root" bash "$project_root/modules/scripts/task-new.sh" --tags 'architecture,' --size m --priority high trailing >/dev/null 2>&1; then exit 1; fi
if TASK_ID_NOW="$now" TASK_ID_RANDOM_SOURCE="$fixture_root/random" PROJECT_ROOT="$project_root" TASKS_ROOT="$new_root" bash "$project_root/modules/scripts/task-new.sh" --tags $'architecture\nfeature' --size m --priority high multiline >/dev/null 2>&1; then exit 1; fi
printf '\0\0\0\1' > "$fixture_root/short-random"
if TASK_ID_NOW="$now" TASK_ID_RANDOM_SOURCE="$fixture_root/short-random" PROJECT_ROOT="$project_root" TASKS_ROOT="$new_root" bash "$project_root/modules/scripts/task-new.sh" --tags tooling --size s --priority normal short >/dev/null 2>&1; then exit 1; fi
yes_bytes="$fixture_root/collisions"; : > "$yes_bytes"; for _ in {1..16}; do printf '\0\0\0\1' >> "$yes_bytes"; done
if TASK_ID_NOW="$now" TASK_ID_RANDOM_SOURCE="$yes_bytes" PROJECT_ROOT="$project_root" TASKS_ROOT="$new_root" bash "$project_root/modules/scripts/task-new.sh" --tags tooling --size s --priority normal exhausted >/dev/null 2>"$fixture_root/exhausted-error"; then exit 1; fi
assert_contains "$(<"$fixture_root/exhausted-error")" 'after 16 attempts'; [[ ! -e "$new_root/$collision_id-exhausted" ]]
if TASK_ID_NOW=18446744073709551616 TASK_ID_RANDOM_SOURCE="$fixture_root/random" PROJECT_ROOT="$project_root" TASKS_ROOT="$new_root" bash "$project_root/modules/scripts/task-new.sh" --tags tooling --size s --priority normal overflow >/dev/null 2>"$fixture_root/time-error"; then exit 1; fi
assert_contains "$(<"$fixture_root/time-error")" 'outside the task ID range'; [[ "$(find "$new_root" -mindepth 1 -maxdepth 1 -type d -name '*-overflow' | wc -l)" -eq 0 ]]

# A delivery check reads an isolated index export, never mixed worktree state.
staged_repo="$fixture_root/staged-repo"; mkdir -p "$staged_repo/tasks"
git -C "$staged_repo" init --quiet
worktree_tasks="$tasks_root"; tasks_root="$staged_repo/tasks"
staged_task="$(make_task "$(id_for 21340800 50)" staged 'Staged snapshot')"
dependency="$(make_task "$(id_for 21340800 51)" dependency Dependency)"
dependent="$(make_task "$(id_for 21340800 52)" dependent Dependent "$dependency")"
tasks_root="$worktree_tasks"
git -C "$staged_repo" add .
git -C "$staged_repo" -c user.name=Test -c user.email=test@example.invalid commit --quiet -m base

run_staged_list() {
  local snapshot
  snapshot="$(mktemp -d "$fixture_root/staged-snapshot.XXXXXX")"
  git -C "$staged_repo" checkout-index --all --prefix="$snapshot/"
  PROJECT_ROOT="$project_root" TASKS_ROOT="$snapshot/tasks" bash "$project_root/modules/scripts/task-list.sh" "$@"
  rm -rf "$snapshot"
}

touch "$staged_repo/tasks/$staged_task/progress.md"
git -C "$staged_repo" add "tasks/$staged_task/progress.md"
printf 'staged progress\n' > "$staged_repo/tasks/$staged_task/progress.md"
! git -C "$staged_repo" diff --quiet -- "tasks/$staged_task/progress.md"
output="$(run_staged_list --status in_progress)"; assert_contains "$output" "${staged_task%%-*}  in_progress"

touch "$staged_repo/tasks/$staged_task/result.md"
git -C "$staged_repo" add "tasks/$staged_task/result.md"
git -C "$staged_repo" rm --cached --force --quiet "tasks/$staged_task/progress.md"
rm "$staged_repo/tasks/$staged_task/result.md"
output="$(run_staged_list --status closed)"; assert_contains "$output" "${staged_task%%-*}  closed"
git -C "$staged_repo" reset --quiet -- "tasks/$staged_task/result.md" "tasks/$staged_task/progress.md"
touch "$staged_repo/tasks/$staged_task/result.md"
output="$(run_staged_list --status open)"; assert_contains "$output" "${staged_task%%-*}  open"

touch "$staged_repo/tasks/$dependency/result.md"
output="$(run_staged_list --status blocked)"; assert_contains "$output" "${dependent%%-*}  blocked"
git -C "$staged_repo" add "tasks/$dependency/result.md"
rm "$staged_repo/tasks/$dependency/result.md"
output="$(run_staged_list --status open)"; assert_contains "$output" "${dependent%%-*}  open"
output="$(PROJECT_ROOT="$project_root" TASKS_ROOT="$staged_repo/tasks" bash "$project_root/modules/scripts/task-list.sh" --status blocked)"
assert_contains "$output" "${dependent%%-*}  blocked"

sed -i "s/$dependency/0000000001-absent/" "$staged_repo/tasks/$dependent/description.md"
git -C "$staged_repo" add "tasks/$dependent/description.md"
output="$(run_staged_list --status invalid 2>/dev/null)"; assert_contains "$output" "${dependent%%-*}  invalid"

status_before="$(git -C "$staged_repo" status --short)"
run_staged_list --status '' >/dev/null
[[ "$(git -C "$staged_repo" status --short)" == "$status_before" ]]

if command -v dot >/dev/null; then
  graph="$fixture_root/graph.svg"
  PROJECT_ROOT="$project_root" TASKS_ROOT="$tasks_root" GRAPHVIZ_DOT="$(command -v dot)" bash "$project_root/modules/scripts/task-graph.sh" --output "$graph" --status 'open,blocked' --tag tooling 2>/dev/null
  assert_contains "$(<"$graph")" "$id4"; assert_contains "$(<"$graph")" 'critical/m'; assert_contains "$(<"$graph")" '&quot;quoted&quot;'
  PROJECT_ROOT="$project_root" TASKS_ROOT="$tasks_root" GRAPHVIZ_DOT="$(command -v dot)" bash "$project_root/modules/scripts/task-graph.sh" --output "$graph" --status in_progress 2>/dev/null
  assert_contains "$(<"$graph")" "$id21"; assert_contains "$(<"$graph")" '#ede9fe'
  PROJECT_ROOT="$project_root" TASKS_ROOT="$tasks_root" GRAPHVIZ_DOT="$(command -v dot)" bash "$project_root/modules/scripts/task-graph.sh" --output "$graph" --status invalid 2>/dev/null
  assert_contains "$(<"$graph")" 'bad&quot;name'
  fake_dot="$fixture_root/failing-dot"; printf '#!/usr/bin/env bash\nprintf partial > "$4"\nexit 1\n' > "$fake_dot"; chmod +x "$fake_dot"; printf original > "$graph"
  if PROJECT_ROOT="$project_root" TASKS_ROOT="$tasks_root" GRAPHVIZ_DOT="$fake_dot" bash "$project_root/modules/scripts/task-graph.sh" --output "$graph" >/dev/null 2>&1; then exit 1; fi
  [[ "$(<"$graph")" == original ]]
fi

echo 'task tooling tests passed'
