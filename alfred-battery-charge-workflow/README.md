# Battery Charge Alfred Workflow

Control the macOS battery charge limiter from Alfred.

Type the keyword `charge`, then pick an action:

- `charge 70` – hold the battery at 70%
- `charge 80` – hold the battery at 80%
- `charge 90` – hold the battery at 90%
- `charge 100` – turn the limiter off and allow a full charge

The filter subtitle always shows the current level and limiter state, e.g.
`Now 100% · Limiter on 80%`.

## How it works

The workflow drives the [`battery`](https://github.com/actuallymentor/battery) CLI
(installed at `/usr/local/co.palokaj.battery/battery`, with a symlink at
`/usr/local/bin/battery`).

For reliability it enforces the limit through a **single launchd user agent**
(`com.battery.app`, `~/Library/LaunchAgents/battery.plist`) instead of a loose
background process:

- `set-charge.sh` sets the target with `battery maintain N`, then hands the live
  maintenance loop to the launchd agent and kills the duplicate loop the CLI
  spawns. Result: exactly one loop, managed by launchd, that survives reboots.
- Turning the limiter off (`charge 100`) stops the loop, unloads the agent, and
  clears the saved target so it does not re-enable itself after a reboot.

### Active discharge

By default the limiter **actively discharges** down to the target even while
plugged in (via the CLI's `--force-discharge`), so going from 100% to 80%
actually drains rather than waiting for a slow natural drop. The launchd agent
carries this flag too, so the behavior persists across reboots.

Caveat: `--force-discharge` does not play well with clamshell mode (lid closed,
driving an external display). To disable active discharge and only stop charging
above the target, export `BATTERY_FORCE_DISCHARGE=false` in the Alfred action's
environment (Alfred → workflow → the Run Script action).

### No menu-bar app required

You do **not** need the Battery menu-bar app running. In fact, keeping it open
causes a second maintenance loop that fights the workflow's loop over the SMC —
the main source of the old unreliability. Quit the Battery app and let this
workflow + the launchd agent manage charging on their own. The limit resumes
automatically at login via the agent.

## Files

- `charge-filter.sh` – Alfred Script Filter: lists choices and current status.
- `set-charge.sh` – applies the chosen limit (or turns it off).
- `battery-common.sh` – shared helpers (locate the CLI, manage the launchd agent).
- `info.plist` – the Alfred workflow definition.

Actions are logged to `/tmp/battery-charge-alfred.log`; the CLI logs to
`~/.battery/battery.log`.
