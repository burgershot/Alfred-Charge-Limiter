#!/bin/zsh
#
# Apply a battery charge limit (or turn the limiter off).
# Called by the Alfred action with a single argument: 70, 80, 90, 100,
# or one of off/disable/full/stop.
#
# Model: we don't use the CLI's maintain loop (it can't hold the limit on this
# hardware — see charge-maintain.sh). We save the target, install our own
# adapter-based maintainer to a stable path, and run it as a launchd agent that
# survives reboots with no menu-bar app. The agent holds the battery between
# (target - BATTERY_RESUME_BELOW)% and target% with a shallow discharge/charge
# sawtooth; BATTERY_RESUME_BELOW is an Alfred workflow variable (default 5).

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
  # Clear the saved target first so the maintainer, if it wakes during teardown,
  # sees "off" and releases the adapter instead of re-asserting discharge.
  rm -f "$CONFIG_DIR/maintain.percentage" "$CONFIG_DIR/maintain.voltage" 2>/dev/null
  stop_battery_agent
  "$BATTERY_CMD" maintain stop >> "$LOG_FILE" 2>&1 || true
  # Release any forced discharge (CHIE -> 00) so the battery can charge again.
  "$BATTERY_CMD" adapter on >> "$LOG_FILE" 2>&1 || true
  notify "Limiter off — allowing a full charge."
  log "limiter disabled"
  exit 0
fi

level="$digits"

# How far below the target the battery may drain before charging resumes (the
# sawtooth depth). Alfred passes this as the BATTERY_RESUME_BELOW workflow
# variable; keep digits only, default 5, and clamp so the low end stays >= 1%.
resume="${BATTERY_RESUME_BELOW:-5}"
resume="${resume//[^0-9]/}"
[[ -z "$resume" ]] && resume=5
(( resume < 1 )) && resume=1
(( resume > level - 1 )) && resume=$(( level - 1 ))
export BATTERY_RESUME_BELOW="$resume"
low=$(( level - resume ))

log "setting limiter to ${level}% (range ${low}-${level}%, resume_below=${resume})"

# Stop any loop the CLI may have left running (its maintain loop cannot hold the
# limit on this hardware — see charge-maintain.sh — so we don't use it).
"$BATTERY_CMD" maintain stop >> "$LOG_FILE" 2>&1 || true
if [[ -n "$(cat "$CONFIG_DIR/battery.pid" 2>/dev/null)" ]]; then
  kill "$(cat "$CONFIG_DIR/battery.pid" 2>/dev/null)" 2>/dev/null || true
fi

# Persist the target where our maintainer reads it, and install the maintainer
# to a stable location so the launchd agent never points into the Alfred
# workflow folder (whose path changes if the workflow is reinstalled).
mkdir -p "$CONFIG_DIR"
print -r -- "$level" > "$CONFIG_DIR/maintain.percentage"
/usr/bin/install -m 0755 "$SCRIPT_DIR/charge-maintain.sh" "$BATTERY_MAINTAIN_SCRIPT"

# (Re)start the launchd agent running our adapter-based maintainer.
write_battery_agent_plist
if reload_battery_agent; then
  log "launchd maintainer active for ${level}%"
else
  log "ERROR: launchd maintainer failed to start"
  fail "Set ${level}%, but the background maintainer did not start. See $LOG_FILE."
fi

notify "Limiter on — holding between ${low}% and ${level}%."
log "limiter set to ${level}% (range ${low}-${level}%)"
