# Personal Reminder

A small, local Windows 10/11 reminder utility. It reads a JSON timetable,
registers daily Windows Scheduled Tasks, and displays native Windows toast
notifications. It has no server, database, or background process of its own.

## Architecture

```text
timetable.json → Windows Task Scheduler → .venv Python → reminder.py → Windows toast
```

Each enabled schedule entry has one task named `PersonalReminder-<Title>` with
spaces and punctuation removed from the title. The task starts the project
virtual environment's Python and exits after the notification is requested.
Scheduled tasks run in the current user's interactive session so Windows can
show the toast; the app does not need to remain open.

## Installation

Open PowerShell in the project folder. Create and activate a virtual environment:

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
```

Install the sole dependency:

```powershell
python -m pip install -r requirements.txt
```

## Test a notification

```powershell
python reminder.py --test
```

This displays **🔔 Test Reminder** with “Your reminder system is working.”
Use `python reminder.py --help` for CLI options.

## Edit the timetable

Edit `timetable.json` in a text editor. Keep the timezone as `Asia/Kolkata` on
this setup, and give each schedule entry a unique title, a 24-hour `HH:MM` time,
a message, and a boolean `enabled` value. `duration_minutes` is optional and,
when provided, must be a positive whole number. The duration is informational;
it does not control how long a toast stays visible.

To pause one reminder, set its `enabled` value to `false`. To change a reminder's
time, title, message, or enabled state, save the JSON and run setup again.

## Install or update scheduled tasks

```powershell
.\setup.ps1
```

Setup validates the JSON, then creates or updates the task for every enabled
entry and removes application tasks for disabled or removed entries. It is
safe to run repeatedly. The timetable timezone is `Asia/Kolkata`; Windows must
use **India Standard Time** so daily trigger times match the schedule. Setup
does not download executables or need the app to stay open.

If Windows was off at a reminder time, Task Scheduler may start missed tasks
when it becomes available. Scheduled invocations use a 15-minute catch-up
window: only reminders at the latest enabled scheduled time in that window are
missed entries are skipped instead of replayed in a burst. Manual
`--reminder "DSA"` calls are not subject to this window.

## Test the project

```powershell
.\test.ps1
```

The script reports whether Python and the virtual environment are available,
the dependency imports, the timetable validates, and both the test notification
and reminder lookup commands run successfully. Notification visibility still
depends on Windows notification settings.

## Logs

Notification requests, reminder titles, skipped stale scheduled starts, and
errors are written with local timestamps to `logs/reminder.log`. The log rotates
at 512 KB and keeps up to two previous files. The `logs/` folder is created on
the first logged event.

## Uninstall scheduled tasks

```powershell
.\uninstall.ps1
```

The uninstaller removes only Windows tasks whose names start with
`PersonalReminder-`. It leaves `timetable.json`, the virtual environment, and
logs in place.

## Troubleshooting

- **Virtual environment missing:** run the setup commands above from this
  project folder.
- **Missing `winotify`:** activate `.venv` and run
  `python -m pip install -r requirements.txt`.
- **No toast appears:** check Windows notification settings and ensure the
  current user is signed in. Scheduled tasks use the interactive user session.
- **Setup rejects the timezone:** set Windows to India Standard Time, matching
  `Asia/Kolkata`, before running `setup.ps1`.
- **Invalid timetable:** check the error for the entry number and correct its
  time, title, message, enabled flag, duration, or duplicate title.
- **Task did not notify after the computer was off:** only the latest enabled
  reminder within 15 minutes of its scheduled time is eligible for catch-up.
