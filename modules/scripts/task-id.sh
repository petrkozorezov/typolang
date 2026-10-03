# shellcheck shell=bash
# Shared sortable task ID encoding, decoding, and generation.
# ID = base62((seconds since 2026-01-01 UTC << 27) | random 27-bit suffix).
# Fixed 10-character width and LC_ALL=C preserve chronological sorting;
# collisions are retried locally and checked again after branch integration.

TASK_ID_EPOCH=1767225600
TASK_ID_TIMESTAMP_LIMIT=4294967296
TASK_ID_SUFFIX_LIMIT=134217728
TASK_ID_VALUE_LIMIT=576460752303423488
TASK_ID_WIDTH=10
TASK_ID_ALPHABET=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz

task_is_decimal() {
  [[ "$1" =~ ^(0|[1-9][0-9]*)$ ]]
}

task_decimal_below() {
  local value="$1" limit="$2" LC_ALL=C
  task_is_decimal "$value" || return 1
  (( ${#value} < ${#limit} )) || { (( ${#value} == ${#limit} )) && [[ "$value" < "$limit" ]]; }
}

task_base62_encode() {
  local value="$1" result='' remainder padding
  task_decimal_below "$value" "$TASK_ID_VALUE_LIMIT" || return 1
  while (( value > 0 )); do
    remainder=$((value % 62))
    result="${TASK_ID_ALPHABET:remainder:1}$result"
    value=$((value / 62))
  done
  printf -v padding '%*s' "$((TASK_ID_WIDTH - ${#result}))" ''
  printf '%s%s\n' "${padding// /0}" "$result"
}

task_base62_decode() {
  local id="$1" value=0 index digit char
  [[ ${#id} -eq TASK_ID_WIDTH && "$id" =~ ^[0-9A-Za-z]+$ ]] || return 1
  for ((index = 0; index < TASK_ID_WIDTH; index++)); do
    char="${id:index:1}"
    digit="${TASK_ID_ALPHABET%%"$char"*}"
    [[ ${#digit} -lt 62 ]] || return 1
    value=$((value * 62 + ${#digit}))
    (( value < TASK_ID_VALUE_LIMIT )) || return 1
  done
  printf '%d\n' "$value"
}

task_id_from_parts() {
  local timestamp="$1" suffix="$2"
  task_decimal_below "$timestamp" "$TASK_ID_TIMESTAMP_LIMIT" || return 1
  task_decimal_below "$suffix" "$TASK_ID_SUFFIX_LIMIT" || return 1
  task_base62_encode "$((timestamp * TASK_ID_SUFFIX_LIMIT + suffix))"
}

task_id_parts() {
  local value
  value="$(task_base62_decode "$1")" || return 1
  printf '%d\t%d\n' "$((value / TASK_ID_SUFFIX_LIMIT))" "$((value % TASK_ID_SUFFIX_LIMIT))"
}

task_id_created_date() {
  local parts timestamp
  parts="$(task_id_parts "$1")" || return 1
  timestamp="${parts%%$'\t'*}"
  date -u -d "@$((TASK_ID_EPOCH + timestamp))" +%F
}

task_current_unix_seconds() {
  if [[ -n "${TASK_ID_NOW:-}" ]]; then printf '%s\n' "$TASK_ID_NOW"; else date -u +%s; fi
}

task_random_suffix() {
  local bytes
  bytes="$(od -An -N4 -tu1 <&3)" || return 1
  read -r -a bytes <<< "$bytes"
  [[ ${#bytes[@]} -eq 4 ]] || return 1
  printf '%d\n' "$(( (bytes[0] * 16777216 + bytes[1] * 65536 + bytes[2] * 256 + bytes[3]) & (TASK_ID_SUFFIX_LIMIT - 1) ))"
}
