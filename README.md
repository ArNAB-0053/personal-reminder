# Personal Reminder

A small, local Windows utility that displays reminder notifications from a JSON
timetable. It uses Windows toast notifications and Windows Task Scheduler; the
reminder process exits after each notification request.

## Features

- Show a test toast with `--test`.
- List enabled timetable entries with `--list`.
- Show a selected reminder with `--reminder "TITLE"`.
- Validate timetable entries and report useful input errors.
- Create or update one daily Windows Scheduled Task per enabled reminder.
- Remove obsolete application tasks when the timetable changes.
- Record notification requests and errors in a small rotating local log.

The utility is local-only. It has no server, database, web interface, or
always-running reminder process.

## Current Status

The current repository includes the notification worker, JSON timetable CLI,
Windows Scheduled Task setup and removal scripts, and local logging. This README
documents those checked-in capabilities; it does not describe additional
planned functionality.

## How It Works

```text
timetable.json → Windows Task Scheduler → reminder.py → Windows toast
```

When run directly, `reminder.py` handles one CLI command and exits. Scheduled
tasks run in the current user's interactive session so Windows can display the
toast. If Windows was off at the scheduled time, a task may start when Windows
becomes available; scheduled invocations only show reminders at the latest
enabled scheduled time within a 15-minute catch-up window.

## Requirements

- Windows 10 or Windows 11
- Python 3.14 or newer, as specified by `pyproject.toml` and `.python-version`
- [`uv`](https://docs.astral.sh/uv/) for environment and dependency management

The included timetable uses `Asia/Kolkata`. `setup.ps1` requires the Windows
time zone to be **India Standard Time** so scheduled times match the timetable.

## Installation

Install `uv`, open PowerShell in the project directory, then run:

```powershell
uv sync
```

`uv sync` creates or updates the project virtual environment in `.venv` and
installs the dependencies declared in `pyproject.toml` using `uv.lock`.

## Usage

Show the test notification:

```powershell
uv run python reminder.py --test
```

The toast title is **🔔 Test Reminder** and its message is “Your reminder
system is working.” Windows notification settings may affect whether it is
shown.

List enabled reminders:

```powershell
uv run python reminder.py --list
```

Show a reminder by its title:

```powershell
uv run python reminder.py --reminder "DSA"
```

Show available CLI options:

```powershell
uv run python reminder.py --help
```

## Edit the Timetable

The included `timetable.json` contains a **demo timetable** for example purposes. Before using the reminder system, edit this file and replace the demo reminders with your own schedule.

Each reminder requires:

* `time` — reminder time in 24-hour `HH:MM` format
* `title` — notification headline
* `message` — notification description
* `enabled` — whether the reminder is active

The optional `duration_minutes` value must be a positive whole number. It is informational and does not control how long the toast remains visible.

For example:

```json
{
  "time": "09:30",
  "title": "DSA",
  "message": "Start your DSA session.",
  "duration_minutes": 90,
  "enabled": true
}
```

Set `enabled` to `false` to disable a reminder.

After adding or changing reminders, run:

```powershell
.\setup.ps1
```

to apply the timetable to Windows Task Scheduler.

> **Note:** The timetable included in this repository is only a demo. Replace it with your own reminders and schedule before using the utility for your personal workflow.

Timetable values are treated as data; the application does not execute commands from the JSON file.

## Set Up Scheduled Tasks

Run from PowerShell in the project directory:

```powershell
.\setup.ps1
```

The script validates the timetable and creates or updates tasks named
`PersonalReminder-<Title>` for enabled reminders. It removes tasks for disabled
or deleted entries, so it is safe to run again after schedule changes. Tasks
use the project Python executable and working directory. The setup script runs
as the current user with limited privileges; it does not request elevation.

## Testing

Run the project checks with:

```powershell
.\test.ps1
```

The script checks the project Python environment, the `winotify` dependency,
timetable validation, the test notification command, and a lookup for an
enabled reminder. The notification checks request toasts; they cannot guarantee
that Windows settings allow them to appear.

Useful development checks:

```powershell
uv run python -m py_compile reminder.py
uv run python reminder.py --help
```

## Logs

Notification requests, reminder titles, skipped stale scheduled starts, and
errors are recorded with local timestamps in `logs/reminder.log`. The log
rotates at 512 KB and retains up to two previous files. The `logs/` directory
is created the first time a log entry is written.

## Uninstall Scheduled Tasks

To remove this utility's scheduled tasks, run:

```powershell
.\uninstall.ps1
```

It removes only task names beginning with `PersonalReminder-`. It does not
delete the timetable, source files, virtual environment, or logs.

## Project Structure

```text
personal-reminder/
├── reminder.py       # CLI, timetable loading, and toast notifications
├── timetable.json    # Local reminder schedule
├── setup.ps1         # Create/update Windows Scheduled Tasks
├── uninstall.ps1     # Remove this utility's Scheduled Tasks
├── test.ps1          # Environment, dependency, timetable, and CLI checks
├── pyproject.toml    # Project metadata and dependency declaration
├── uv.lock           # Locked dependency versions
├── requirements.txt  # Pip-compatible dependency list
├── .python-version   # Project Python version selection
├── .gitignore
├── README.md
├── .venv/            # Created and managed by uv sync
└── logs/             # Created when the application first logs an event
```

`.venv/` and `logs/` are ignored by Git. `main.py` is a standalone starter stub
and is not part of the reminder command flow. `logs/reminder.log` is generated
at runtime.

## Troubleshooting

- **`uv` is not recognized:** install `uv`, open a new PowerShell session, then
  retry `uv sync`.
- **Python version mismatch:** install Python 3.14 or newer, then run `uv sync`
  again.
- **Dependency import error:** run `uv sync` to install the locked dependencies.
- **No toast appears:** check Windows notification settings and ensure the
  current user is signed in. Scheduled tasks run in that user's interactive
  session.
- **Setup reports a time zone mismatch:** use Windows **India Standard Time**
  for the included `Asia/Kolkata` timetable.
- **A reminder is not found:** pass a title exactly as it appears in
  `timetable.json`; disabled reminders cannot be shown.
- **A scheduled reminder was missed:** only the latest enabled reminder within
  15 minutes of its scheduled time is eligible for catch-up.
