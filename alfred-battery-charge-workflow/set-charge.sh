#!/bin/zsh
#
# Apply a battery charge limit (or turn the limiter off).
# Called by the Alfred action with a single argument: 70, 80, 90, 100,
# or one of off/disable/full/stop.
#
# Reliability model:
#   * `battery maintain N` sets the target, writes the launchd plist, and
#     starts a maintenance loop. We run it in the FOREGROUND (no fragile
#     `nohup ... &`) so the setup fully completes before this script exits.
#   * We then hand the live loop to the launchd agent and kill the duplicate
#     loop `maintain` spawned, so exactly one loop runs and it keeps working
#     across reboots without the Battery menu-bar app.

set -u

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/battery-common.sh"

BATTERY_CMD="$(resolve_battery_cmd 2>/dev/null || true)"
LOG_FILE="/tmp/battery-charge-alfred.log"
CONFIG_DIR="$HOME/.battery"

timestamp() { /bin/date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '%s %s\n' "$(timestamp)" "$1" >> "$LOG_FILE"; }
# The message is printed to stdout so the connected Alfred "Post Notification"
# output shows it with the workflow's battery icon. Diagnostics stay in the log.
# Exactly one notify() runs per invocation, so stdout holds a single message.
notify() { printf '%s' "$1"; }
# Exit 0 even on user-facing errors so Alfred still posts the notification.
fail() { log "ERROR: $1"; notify "$1"; exit 0; }

raw="${1:-}"
target="${raw:l}"          # lowercase
target="${target//%/}"     # strip a trailing %
digits="${target//[^0-9]/}"

log "invoked with: '$raw' (normalized='$target', digits='$digits')"

if [[ -z "$BATTERY_CMD" || ! -x "$BATTERY_CMD" ]]; then
  fail "Battery CLI not found. Install it first."
fi

# Decide whether this means "turn the limiter off" or "maintain at N%".
disable=false
case "$target" in
  off|disable|disabled|full|stop|100)
    disable=true
    ;;
  *)
    if [[ -z "$digits" ]]; then
      fail "Use charge 70, 80, 90, or 100."
    fi
    if (( digits < 1 || digits > 100 )); then
      fail "Pick a value between 1 and 100."
    fi
    (( digits == 100 )) && disable=true
    ;;
esac

if $disable; then
  log "disabling limiter (full charge)"
  "$BATTERY_CMD" maintain stop >> "$LOG_FILE" 2>&1 || true
  stop_battery_agent
  # Clear the saved target so a login `recover` doesn't re-enable the limiter.
  rm -f "$CONFIG_DIR/maintain.percentage" "$CONFIG_DIR/maintain.voltage" 2>/dev/null
  notify "Limiter off — allowing a full charge."
  log "limiter disabled"
  exit 0
fi

level="$digits"
log "setting limiter to ${level}% (force_discharge=${BATTERY_FORCE_DISCHARGE})"

# Saves the target and writes the launchd plist. We pass no flag here so this
# transient loop only disables charging (no stray discharge child); the agent
# below is what actually force-discharges down to the target.
if ! "$BATTERY_CMD" maintain "$level" >> "$LOG_FILE" 2>&1; then
  fail "Failed to set limiter to ${level}%. See $LOG_FILE."
fi

# Make the launchd agent the single maintenance loop: regenerate the plist
# (adding --force-discharge), reload it, then drop the transient loop the CLI
# just started. The agent persists across reboots with no app running.
detached_pid="$(cat "$CONFIG_DIR/battery.pid" 2>/dev/null || true)"
write_battery_agent_plist "$BATTERY_CMD"
if reload_battery_agent; then
  log "launchd agent active; removing transient loop ${detached_pid:-none}"
  if [[ -n "$detached_pid" ]]; then
    kill "$detached_pid" 2>/dev/null || true
  fi
else
  log "launchd agent unavailable; keeping the foreground maintenance loop"
fi

if [[ "${BATTERY_FORCE_DISCHARGE}" == "true" ]]; then
  notify "Limiter on — discharging to ${level}%."
else
  notify "Limiter on — holding at ${level}%."
fi
log "limiter set to ${level}%"
