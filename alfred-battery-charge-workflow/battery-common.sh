#!/bin/zsh

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
