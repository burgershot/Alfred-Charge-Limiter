# Alfred Charge Limiter

An Alfred workflow for controlling the macOS battery charge limiter from a single `charge` keyword.

It currently offers quick actions for:

- `70%`
- `80%`
- `90%`
- `100%`

The workflow is built around the [`battery`](https://github.com/actuallymentor/battery) command-line tool.
It now tries a few common install locations so it is more useful outside one specific machine:

- `BATTERY_CMD` if you set it manually
- `/usr/local/co.palokaj.battery/battery`
- `/opt/homebrew/bin/battery`
- `/usr/local/bin/battery`
- `battery` from your shell `PATH`

## Disclaimer

This project is **fully vibe-coded**.

That means:

- the workflow logic, packaging, and repo structure were produced with heavy AI assistance
- the code was iterated experimentally until it worked in the target environment
- it has **not** been developed with the same rigor as a production-grade, widely-tested open source utility
- it may contain rough edges, portability issues, fragile Alfred-specific assumptions, or implementation mistakes

If you use, fork, or publish this project, please do so with that context in mind.

You should assume:

- the code is useful, but not polished
- the implementation is environment-specific
- further manual review is recommended before trusting changes blindly

## What Is In This Repo

- `Alfred Charge Limiter.alfredworkflow`: importable Alfred workflow package
- `alfred-battery-charge-workflow/info.plist`: Alfred workflow definition
- `alfred-battery-charge-workflow/charge-filter.sh`: Alfred Script Filter suggestions
- `alfred-battery-charge-workflow/set-charge.sh`: action runner that calls the battery CLI
- `alfred-battery-charge-workflow/battery-common.sh`: shared battery CLI discovery helpers

## Usage

1. Install and configure the `battery` tool separately.
2. Import `Alfred Charge Limiter.alfredworkflow` into Alfred.
3. Type `charge` in Alfred.
4. Pick one of the suggested targets: `70`, `80`, `90`, or `100`.

## Notes

- `100%` disables the limiter and allows a full charge.
- `70%`, `80%`, and `90%` start the matching maintenance target.
- The workflow currently uses standard macOS notifications for feedback.
- The workflow icon is bundled with the package.
- If the workflow cannot find the `battery` CLI, Alfred shows a setup hint instead of silently failing.

## License

No license has been added yet. By default, that means all rights are reserved until the author chooses a license explicitly.
