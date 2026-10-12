# Battery Charge Alfred Workflow

Control the macOS battery charge limiter from Alfred.

Type the keyword `charge`, then pick an action:

- `charge 70` – hold the battery around 70%
- `charge 80` – hold the battery around 80%
- `charge 90` – hold the battery around 90%
- `charge 100` – turn the limiter off and allow a full charge

The filter subtitle always shows the current level and limiter state, e.g.
`Now 100% · Limiter on 80%`. After you choose an action, a native Alfred
notification (with the workflow's battery icon) confirms the result.

## How it works

The workflow drives the [`battery`](https://github.com/actuallymentor/battery) CLI
(installed at `/usr/local/co.palokaj.battery/battery`, with a symlink at
`/usr/local/bin/battery`) and its bundled `smc` helper.

The limit is enforced by a **single launchd user agent** (`com.battery.app`,
`~/Library/LaunchAgents/battery.plist`) that runs `charge-maintain.sh` every 30s.
This survives reboots and needs **no** menu-bar app running.

- `set-charge.sh` saves the target to `~/.battery/maintain.percentage`, installs
  `charge-maintain.sh` to `~/.battery/` (a stable path, independent of the Alfred
  folder), writes the plist, and (re)starts the agent.
- Turning the limiter off (`charge 100`) clears the saved target, stops the
  agent, and releases the adapter so the battery can charge normally again.

### Why it holds the limit with the power adapter

Most charge limiters "freeze" charging via SMC keys (`CH0B`/`CH0C`, or the newer
`CHTE`). **On some Macs those keys don't exist** — `smc -k CHTE -r` returns
`no data` — so the CLI's own `maintain` loop can never actually stop charging
and the battery quietly climbs to 100%.

On that hardware the only working lever is the **power adapter** (`CHIE`): the
Mac can be told to run off the battery (draining) or to accept the adapter
(charging). `charge-maintain.sh` uses this to hold the battery around the target
with a shallow hysteresis sawtooth: it discharges when at/above the target and
charges again once the level drops `BATTERY_RESUME_BELOW` percent under it
(default 5, so a target of 80 floats between ~75% and 80%). There is no true
"hold" lever on this hardware, so some gentle cycling near the target is
expected — and far healthier than sitting pinned at 100%.

### Keep the Mac awake on AC

The maintainer is a user-space loop, so it only enforces while the Mac is awake.
During sleep (including Power Nap / standby maintenance wakes) charging proceeds
unchecked. `caffeinate` is not enough — it only blocks *idle* sleep. To hold the
limit reliably while plugged in, disable sleep on AC:

```
sudo pmset -c disablesleep 1 standby 0 powernap 0
```

(Revert with `sudo pmset -c disablesleep 0 standby 1 powernap 1`.) This only
affects behavior while on the charger; on battery the Mac sleeps normally.

### No menu-bar app required

You do **not** need the Battery menu-bar app running. In fact, keeping it open
causes a second maintenance loop that fights this one over the SMC. Quit the
Battery app and let this workflow + the launchd agent manage charging. The limit
resumes automatically at login via the agent.

## Files

- `charge-filter.sh` – Alfred Script Filter: lists choices and current status.
- `set-charge.sh` – applies the chosen limit (or turns it off).
- `charge-maintain.sh` – the adapter-based maintainer run by the launchd agent.
- `battery-common.sh` – shared helpers (locate the CLI, manage the launchd agent).
- `info.plist` – the Alfred workflow definition.

Actions are logged to `/tmp/battery-charge-alfred.log`; the maintainer logs to
`~/.battery/battery.log`.
