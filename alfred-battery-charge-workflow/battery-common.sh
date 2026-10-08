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

# When enabled, the maintenance loop actively discharges (even while plugged in)
# down to the target instead of just waiting for a natural drain. Controlled by
# the BATTERY_FORCE_DISCHARGE workflow variable (Alfred checkbox: 1/0); also
# accepts true/false/yes/no/on/off. Defaults to enabled when unset. Normalized
# here to exactly "true" or "false" so callers can compare simply.
: "${BATTERY_FORCE_DISCHARGE:=true}"
case "${BATTERY_FORCE_DISCHARGE:l}" in
  false|0|no|off) BATTERY_FORCE_DISCHARGE=false ;;
  *)              BATTERY_FORCE_DISCHARGE=true  ;;
esac

battery_gui_domain() {
  printf 'gui/%s' "$(/usr/bin/id -u)"
}

# Write the launchd agent plist. The CLI rewrites this file (without the
# force-discharge flag) on every `battery maintain`, so we regenerate it here
# afterwards to keep our settings. Runs `maintain_synchronous recover`, which
# re-reads the saved target at login; the optional flag makes it discharge
# down to that target rather than idling at a higher charge.
write_battery_agent_plist() {
  local battery_cmd="$1"
  local logfile="$HOME/.battery/battery.log"
  local force_line=""

  if [[ "${BATTERY_FORCE_DISCHARGE}" == "true" ]]; then
    force_line=$'\t\t\t<string>--force-discharge</string>\n'
  fi

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
			<string>${battery_cmd}</string>
			<string>maintain_synchronous</string>
			<string>recover</string>
${force_line}		</array>
		<key>StandardOutPath</key>
		<string>${logfile}</string>
		<key>StandardErrorPath</key>
		<string>${logfile}</string>
		<key>RunAtLoad</key>
		<true/>
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
