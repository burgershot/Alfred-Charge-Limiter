#!/bin/zsh
#
# Alfred Script Filter: list charge-limit choices and show the current state.

set -u

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/battery-common.sh"

BATTERY_CMD="$(resolve_battery_cmd 2>/dev/null || true)"
query="${1:-}"
query="${query//[^0-9]/}"
limits=(70 80 90 100)

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

emit_single() { # title subtitle  -> one informational, non-actionable item
  printf '{"items":[{"title":"%s","subtitle":"%s","valid":false}]}' \
    "$(json_escape "$1")" "$(json_escape "$2")"
}

if [[ -z "$BATTERY_CMD" || ! -x "$BATTERY_CMD" ]]; then
  emit_single "Battery CLI not found" "$(format_missing_battery_subtitle)"
  exit 0
fi

# status_csv: percentage,remaining,charging,discharging,maintain_percentage
status_csv="$("$BATTERY_CMD" status_csv 2>/dev/null || true)"
percentage=""
maintain=""
if [[ -n "$status_csv" ]]; then
  IFS=',' read -r percentage _remaining _charging _discharging maintain <<< "$status_csv"
fi
maintain="${maintain// /}"

if [[ -n "$maintain" && "$maintain" != "0" ]]; then
  state="Limiter on ${maintain}%"
else
  state="Limiter off (full charge)"
fi
status_suffix="Now ${percentage:-?}% · ${state}"

selected=()
for l in "${limits[@]}"; do
  if [[ -z "$query" || "$l" == "$query"* ]]; then
    selected+=("$l")
  fi
done

if (( ${#selected[@]} == 0 )); then
  emit_single "Use charge 70, 80, 90, or 100" "$status_suffix"
  exit 0
fi

printf '{"items":['
first=true
for l in "${selected[@]}"; do
  $first || printf ','
  first=false

  if [[ "$l" == 100 ]]; then
    sub="Turn the limiter off and allow a full charge. ${status_suffix}"
  else
    sub="Hold the battery at ${l}%. ${status_suffix}"
  fi

  printf '{"title":"Charge to %s%%","subtitle":"%s","arg":"%s","uid":"charge-%s"}' \
    "$l" "$(json_escape "$sub")" "$l" "$l"
done
printf ']}'
