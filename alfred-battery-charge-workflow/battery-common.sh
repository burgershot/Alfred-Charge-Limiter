#!/bin/zsh
#
# Shared helpers for the Battery Charge Alfred workflow.
#
# Design: the charge limit is enforced by a single launchd user agent
# (com.battery.app) so it survives reboots WITHOUT needing the Battery
# menu-bar app running. set-charge.sh makes that agent the one and only
# maintenance loop to avoid competing loops fighting over the SMC.

# --- Locate the `battery` CLI -------------------------------------------------

resolve_battery_cmd() {
  local -a candidates

  if [[ -n "${BATTERY_CMD:-}" ]]; then
    candidates+=("$BATTERY_CMD")
  fi

  candidates+=(
    "/usr/local/co.palokaj.battery/battery"
    "/opt/homebrew/bin/battery"
    "/usr/local/bin/battery"
  )

  if command -v battery >/dev/null 2>&1; then
    candidates+=("$(command -v battery)")
  fi

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

format_missing_battery_subtitle() {
  printf '%s' "Install the 'battery' CLI first. Checked BATTERY_CMD, /usr/local/co.palokaj.battery/battery, /opt/homebrew/bin/battery, and /usr/local/bin/battery."
}

# --- launchd agent management -------------------------------------------------

BATTERY_AGENT_LABEL="com.battery.app"
BATTERY_AGENT_PLIST="$HOME/Library/LaunchAgents/battery.plist"

battery_gui_domain() {
  printf 'gui/%s' "$(/usr/bin/id -u)"
}

# Path to our adapter-based maintainer. It is copied to a STABLE location
# (~/.battery) by set-charge.sh so the launchd agent never depends on the
# Alfred workflow folder, whose path changes if the workflow is reinstalled.
BATTERY_MAINTAIN_SCRIPT="$HOME/.battery/charge-maintain.sh"

# Write the launchd agent plist so it runs our maintainer (charge-maintain.sh)
# rather than the CLI's `maintain_synchronous`, which cannot stop charging on
# Macs without the CH0B/CHTE SMC keys. The maintainer re-reads the saved target
# itself and holds the battery there using the adapter/discharge lever.
#
# RESUME_BELOW controls how far below the target it drains before topping back
# up (the sawtooth depth). KeepAlive{SuccessfulExit=false} restarts the loop if
# it is killed (e.g. on wake from sleep) so enforcement resumes automatically;
# it is NOT restarted on a clean exit 0 (no saved target), avoiding a tight
# respawn loop when the limiter is off.
write_battery_agent_plist() {
  local logfile="$HOME/.battery/battery.log"
  local resume_below="${BATTERY_RESUME_BELOW:-5}"

  mkdir -p "${BATTERY_AGENT_PLIST:h}"
  cat > "$BATTERY_AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
	<dict>
		<key>Label</key>
		<string>com.battery.app</string>
		<key>ProgramArguments</key>
		<array>
			<string>/bin/zsh</string>
			<string>${BATTERY_MAINTAIN_SCRIPT}</string>
		</array>
		<key>EnvironmentVariables</key>
		<dict>
			<key>BATTERY_RESUME_BELOW</key>
			<string>${resume_below}</string>
		</dict>
		<key>StandardOutPath</key>
		<string>${logfile}</string>
		<key>StandardErrorPath</key>
		<string>${logfile}</string>
		<key>RunAtLoad</key>
		<true/>
		<key>KeepAlive</key>
		<dict>
			<key>SuccessfulExit</key>
			<false/>
		</dict>
	</dict>
</plist>
PLIST
}

# (Re)start the launchd agent so it becomes the single maintenance loop.
# Boots the agent out first so a freshly written plist is reloaded (launchctl
# caches the definition at bootstrap time). Both bootout and bootstrap are
# asynchronous, so we wait for bootout to finish and poll for the service to
# come up. Idempotent. Returns 0 if the agent is running afterwards.
reload_battery_agent() {
  local domain svc i
  domain="$(battery_gui_domain)"
  svc="$domain/$BATTERY_AGENT_LABEL"

  [[ -f "$BATTERY_AGENT_PLIST" ]] || return 1

  # If already loaded, boot it out and wait until it is really gone — otherwise
  # the following bootstrap races the (async) bootout and silently fails.
  if /bin/launchctl print "$svc" >/dev/null 2>&1; then
    /bin/launchctl bootout "$svc" 2>/dev/null
    for i in {1..30}; do
      /bin/launchctl print "$svc" >/dev/null 2>&1 || break
      /bin/sleep 0.1
    done
  fi

  /bin/launchctl enable "$svc" 2>/dev/null
  /bin/launchctl bootstrap "$domain" "$BATTERY_AGENT_PLIST" 2>/dev/null
  # bootstrap with RunAtLoad starts it; kickstart is a belt-and-suspenders retry.
  /bin/launchctl kickstart "$svc" 2>/dev/null

  # Wait for the service to register before reporting success.
  for i in {1..30}; do
    /bin/launchctl print "$svc" >/dev/null 2>&1 && return 0
    /bin/sleep 0.1
  done
  return 1
}

# Stop and unload the launchd agent, and keep it from auto-loading at next
# login. Used when disabling the limiter (full charge).
stop_battery_agent() {
  local domain
  domain="$(battery_gui_domain)"

  /bin/launchctl bootout "$domain/$BATTERY_AGENT_LABEL" 2>/dev/null
  /bin/launchctl disable "$domain/$BATTERY_AGENT_LABEL" 2>/dev/null
  return 0
}
