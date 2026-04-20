#!/bin/zsh

set -u

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/battery-common.sh"

BATTERY_CMD="$(resolve_battery_cmd 2>/dev/null || true)"
query="${1:-}"
query="${query//[^0-9]/}"
limits=(70 80 90 100)

if [[ ! -x "$BATTERY_CMD" ]]; then
  missing_subtitle="$(format_missing_battery_subtitle)"
  cat <<JSON
{"items":[{"title":"Battery CLI not found","subtitle":"$missing_subtitle","valid":false}]}
JSON
  exit 0
fi

status_csv="$("$BATTERY_CMD" status_csv 2>/dev/null || true)"
status_text="$("$BATTERY_CMD" status 2>/dev/null || true)"
percentage=""
remaining=""
charging=""
discharging=""
maintain_percentage=""
limiter_label="Limiter off"

if [[ -n "$status_csv" ]]; then
  IFS=',' read -r percentage remaining charging discharging maintain_percentage <<< "$status_csv"
fi

trimmed_limit="${maintain_percentage// /}"
status_suffix="Current battery ${percentage:-?}%"

if [[ "$status_text" == *"being maintained at"* ]] || { [[ -n "$trimmed_limit" ]] && [[ "${charging// /}" == "disabled" ]]; }; then
  limiter_label="Limiter on ${trimmed_limit:-?}%"
  status_suffix="${status_suffix}, limiter ${trimmed_limit:-?}%"
else
  status_suffix="${status_suffix}, full charge mode"
fi

selected=()
for limit in "${limits[@]}"; do
  if [[ -z "$query" || "$limit" == "$query"* ]]; then
    selected+=("$limit")
  fi
done

if [[ "${#selected[@]}" -eq 0 ]]; then
  cat <<JSON
{"items":[{"title":"Use charge 70, 80, 90, or 100","subtitle":"$limiter_label. $status_suffix","valid":false}]}
JSON
  exit 0
fi

printf '{"items":['
first=true

for limit in "${selected[@]}"; do
  comma=''
  if [[ "$first" == false ]]; then
    comma=','
  fi

  if [[ "$limit" == "100" ]]; then
    subtitle="$limiter_label. Disable the limiter and allow a full charge. $status_suffix"
  else
    subtitle="$limiter_label. Maintain the battery at $limit%. $status_suffix"
  fi

  printf '%s{"title":"Charge to %s%%","subtitle":"%s","arg":"%s","uid":"charge-%s"}' \
    "$comma" "$limit" "$subtitle" "$limit" "$limit"
  first=false
done

printf ']}'
