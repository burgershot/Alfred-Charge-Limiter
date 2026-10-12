#!/bin/zsh
#
# Adapter-based charge maintainer (the com.battery.app launchd agent).
#
# Why this exists: on some Macs (e.g. newer Apple Silicon / recent macOS) the
# SMC charge-inhibit keys the `battery` CLI relies on (CH0B/CH0C and the newer
# CHTE) are simply not present — `smc -k CHTE -r` and `smc -k CH0C -r` both
# return "no data". On those machines the CLI's own maintain loop can NEVER
# stop charging: its disable_charging() writes to keys that don't exist, so the
# battery quietly climbs to 100% while the loop logs nothing useful.
#
# The one lever that DOES work on this hardware is the adapter/discharge key,
# CHIE: writing 08 makes the Mac ignore the adapter and run off the battery
# (draining), and writing 00 restores normal charging. Since there is no way to
# "freeze" at a level, we hold around the target with a shallow hysteresis
# sawtooth: discharge when at/above the target, charge again once we drop
# RESUME_BELOW percent under it. All the SMC writes used here are whitelisted
# NOPASSWD in /etc/sudoers.d/battery (FORCE_DISCHARGE_ON/OFF and LED_CONTROL),
# so this runs unattended in the background.

set -u

CONFIG_DIR="$HOME/.battery"
TARGET_FILE="$CONFIG_DIR/maintain.percentage"
LOG="$CONFIG_DIR/battery.log"
INTERVAL="${BATTERY_MAINTAIN_INTERVAL:-30}"      # seconds between checks
RESUME_BELOW="${BATTERY_RESUME_BELOW:-5}"        # resume charging this far below target

# Locate the smc binary (installed beside the battery CLI).
SMC=""
for c in "${BATTERY_SMC:-}" /usr/local/co.palokaj.battery/smc /opt/homebrew/co.palokaj.battery/smc; do
  [[ -n "$c" && -x "$c" ]] && { SMC="$c"; break; }
done

log() { print -r -- "$(date '+%m/%d/%y-%H:%M:%S') [limiter] $1" >> "$LOG"; }

get_pct() { pmset -g batt | tail -n1 | awk '{print $3}' | tr -d '%;'; }

# CHIE byte: 08 = discharging (adapter off), 00 = charging allowed.
chie_is_discharging() {
  [[ "$(sudo "$SMC" -k CHIE -r 2>/dev/null)" == *"bytes 08"* ]]
}
start_discharge() {   # at/above target -> drain back down
  chie_is_discharging && return
  sudo "$SMC" -k CHIE -w 08 >/dev/null 2>&1
  sudo "$SMC" -k ACLC -w 04 >/dev/null 2>&1   # MagSafe LED orange
  log "at/above target -> discharging"
}
allow_charge() {      # below the resume point -> charge back up
  chie_is_discharging || return
  sudo "$SMC" -k CHIE -w 00 >/dev/null 2>&1
  sudo "$SMC" -k ACLC -w 03 >/dev/null 2>&1   # MagSafe LED green
  log "below resume point -> charging"
}
clear_hold() {        # stop forcing discharge (limiter off / shutting down)
  chie_is_discharging || return
  sudo "$SMC" -k CHIE -w 00 >/dev/null 2>&1
  sudo "$SMC" -k ACLC -w 00 >/dev/null 2>&1
}

if [[ -z "$SMC" ]]; then
  log "ERROR: smc binary not found; cannot maintain charge"
  exit 0
fi

log "maintainer started (interval=${INTERVAL}s, resume ${RESUME_BELOW}% below target)"

while true; do
  target="$(cat "$TARGET_FILE" 2>/dev/null)"

  # No valid target means the limiter is off: release any forced discharge and
  # exit cleanly. KeepAlive (SuccessfulExit=false) will NOT respawn us on a
  # clean exit, so this avoids a tight restart loop when disabled.
  if [[ -z "$target" || "$target" != <-> ]] || (( target < 1 || target > 100 )); then
    clear_hold
    log "no valid target; limiter off, exiting"
    exit 0
  fi

  pct="$(get_pct)"
  if [[ -z "$pct" || "$pct" != <-> ]]; then
    sleep "$INTERVAL"
    continue
  fi

  low=$(( target - RESUME_BELOW ))
  if (( pct >= target )); then
    start_discharge
  elif (( pct <= low )); then
    allow_charge
  fi
  # In the (low, target) band we keep the current direction (hysteresis),
  # which is what keeps it from flapping every cycle.

  sleep "$INTERVAL"
done
