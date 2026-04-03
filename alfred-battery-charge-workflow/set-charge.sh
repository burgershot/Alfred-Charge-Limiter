#!/bin/zsh

set -euo pipefail

BATTERY_CMD="/usr/local/co.palokaj.battery/battery"
raw_target="${1:-}"
target="${raw_target:l}"
target="${target//%/}"
digits="${target//[^0-9]/}"
LOG_FILE="/tmp/battery-charge-alfred.log"

timestamp() {
  /bin/date '+%Y-%m-%d %H:%M:%S'
}

log() {
  printf '%s %s\n' "$(timestamp)" "$1" >> "$LOG_FILE"
}

notify() {
  (
    /usr/bin/osascript -e "display notification \"$1\" with title \"Battery Charge\"" >/dev/null 2>&1 || true
  ) &
}

detect_state() {
  local status_text
  status_text="$("$BATTERY_CMD" status 2>&1 || true)"
  log "status output: $status_text"

  if [[ "$status_text" == *"being maintained at"* ]]; then
    local limit
    limit="$(printf '%s' "$status_text" | /usr/bin/sed -n 's/.*being maintained at \([0-9][0-9]*\)%.*/\1/p' | /usr/bin/head -n 1)"
    if [[ -n "$limit" ]]; then
      printf 'Limiter on (%s%%)' "$limit"
    else
      printf 'Limiter on'
    fi
    return 0
  fi

  if [[ "$status_text" == *"smc charging enabled"* ]]; then
    printf 'Limiter off'
    return 0
  fi

  printf 'State unclear'
}

run_and_notify() {
  local mode="$1"

  if [[ "$mode" == "100" ]]; then
    log "command: maintain stop"
    "$BATTERY_CMD" maintain stop >> "$LOG_FILE" 2>&1
    notify "Limiter off"
  else
    log "command: maintain $mode"
    /usr/bin/nohup "$BATTERY_CMD" maintain "$mode" >> "$LOG_FILE" 2>&1 &
    notify "Limiter on (${mode}%)"
  fi
}

if [[ ! -x "$BATTERY_CMD" ]]; then
  log "battery cli missing"
  notify "Battery CLI is missing. Open battery.app and install its background components first."
  exit 1
fi

log "raw target: $raw_target"
log "normalized target: $target"
log "digits: $digits"

case "$target" in
  100|*100*|off|disable|disabled|full)
    run_and_notify 100
    ;;
  70|*70*)
    run_and_notify 70
    ;;
  80|*80*)
    run_and_notify 80
    ;;
  90|*90*)
    run_and_notify 90
    ;;
  *)
    case "$digits" in
      70)
        run_and_notify 70
        ;;
      80)
        run_and_notify 80
        ;;
      90)
        run_and_notify 90
        ;;
      100)
        run_and_notify 100
        ;;
      *)
        log "unrecognized argument"
        notify "Use charge 70, 80, 90, or 100."
        exit 1
        ;;
    esac
    ;;
esac
