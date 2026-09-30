"""Read a local timetable and display native Windows toast notifications."""

import argparse
import json
import logging
from logging.handlers import RotatingFileHandler
import re
import sys
from datetime import datetime, time
from pathlib import Path
from typing import Any


TIMETABLE_PATH = Path(__file__).with_name("timetable.json")
LOG_PATH = Path(__file__).with_name("logs") / "reminder.log"
TIME_PATTERN = re.compile(r"^(?:[01]\d|2[0-3]):[0-5]\d$")
CATCH_UP_MINUTES = 15


def get_logger() -> logging.Logger:
    logger = logging.getLogger("personal_reminder")
    if not logger.handlers:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        handler = RotatingFileHandler(LOG_PATH, maxBytes=512_000, backupCount=2, encoding="utf-8")
        handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
        logger.propagate = False
    return logger


def log_event(level: int, message: str, *values: object) -> None:
    try:
        get_logger().log(level, message, *values)
    except OSError as error:
        print(f"Warning: could not write reminder log: {error}", file=sys.stderr)


class TimetableError(ValueError):
    """Raised when the timetable file is missing or invalid."""


def _load_timetable(path: Path) -> list[dict[str, Any]]:
    try:
        with path.open(encoding="utf-8") as timetable_file:
            data = json.load(timetable_file)
    except FileNotFoundError as error:
        raise TimetableError(f"Timetable file not found: {path}") from error
    except json.JSONDecodeError as error:
        raise TimetableError(
            f"Invalid JSON in {path} at line {error.lineno}, column {error.colno}: {error.msg}"
        ) from error
    except OSError as error:
        raise TimetableError(f"Could not read timetable file {path}: {error}") from error
    except UnicodeDecodeError as error:
        raise TimetableError(f"Timetable file is not valid UTF-8: {path}") from error

    if not isinstance(data, dict):
        raise TimetableError("Timetable must contain a JSON object at the top level.")
    if "schedule" not in data or not isinstance(data["schedule"], list):
        raise TimetableError("Timetable must contain a 'schedule' array.")

    schedule = data["schedule"]
    seen_titles: set[str] = set()
    for index, reminder in enumerate(schedule, start=1):
        prefix = f"Reminder {index}"
        if not isinstance(reminder, dict):
            raise TimetableError(f"{prefix} must be a JSON object.")

        time_value = reminder.get("time")
        if not isinstance(time_value, str) or not TIME_PATTERN.fullmatch(time_value):
            raise TimetableError(f"{prefix}: 'time' must use 24-hour HH:MM format (for example, 09:30).")

        title = reminder.get("title")
        if not isinstance(title, str) or not title.strip():
            raise TimetableError(f"{prefix}: 'title' must be a non-empty string.")
        title_key = title.strip().casefold()
        if title_key in seen_titles:
            raise TimetableError(f"{prefix}: duplicate reminder title {title!r}.")
        seen_titles.add(title_key)

        message = reminder.get("message")
        if not isinstance(message, str) or not message.strip():
            raise TimetableError(f"{prefix} ({title}): 'message' must be a non-empty string.")

        if not isinstance(reminder.get("enabled"), bool):
            raise TimetableError(f"{prefix} ({title}): 'enabled' must be true or false.")

        if "duration_minutes" in reminder:
            duration = reminder["duration_minutes"]
            if isinstance(duration, bool) or not isinstance(duration, int) or duration <= 0:
                raise TimetableError(
                    f"{prefix} ({title}): 'duration_minutes' must be a positive whole number."
                )

    return schedule


def load_timetable(path: Path = TIMETABLE_PATH) -> list[dict[str, Any]]:
    """Load and validate the timetable JSON, returning its reminder entries."""
    try:
        return _load_timetable(path)
    except TimetableError as error:
        log_event(logging.ERROR, "Timetable error: %s", error)
        raise


def show_notification(title: str, message: str) -> None:
    """Display one native Windows toast notification."""
    if sys.platform != "win32":
        raise RuntimeError("Windows toast notifications are available only on Windows.")

    from winotify import Notification

    Notification(
        app_id="Personal Reminder",
        title=title,
        msg=message,
        duration="short",
    ).show()


def is_latest_missed_reminder(schedule: list[dict[str, Any]], title: str) -> bool:
    """Allow only the latest enabled reminder missed within the catch-up window."""
    now = datetime.now()
    now_time = now.time().replace(second=0, microsecond=0)
    due = [
        (time.fromisoformat(entry["time"]), entry)
        for entry in schedule
        if entry["enabled"] and time.fromisoformat(entry["time"]) <= now_time
    ]
    if not due:
        return False

    latest_time = max(reminder_time for reminder_time, _ in due)
    age_minutes = (now.hour * 60 + now.minute) - (latest_time.hour * 60 + latest_time.minute)
    latest_titles = {
        entry["title"].strip().casefold()
        for reminder_time, entry in due
        if reminder_time == latest_time
    }
    return age_minutes <= CATCH_UP_MINUTES and title.strip().casefold() in latest_titles


def main() -> int:
    parser = argparse.ArgumentParser(description="List reminders or show a native Windows notification.")
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument("--list", action="store_true", help="list enabled reminders")
    actions.add_argument("--reminder", metavar="TITLE", help="show the notification matching TITLE")
    actions.add_argument("--test", action="store_true", help="show a test notification")
    parser.add_argument("--scheduled", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()

    if args.scheduled and args.reminder is None:
        parser.error("--scheduled can only be used with --reminder.")

    if args.test:
        try:
            show_notification("🔔 Test Reminder", "Your reminder system is working.")
        except Exception as error:
            log_event(logging.ERROR, "Notification failed title=%r: %s", "🔔 Test Reminder", error)
            parser.error(f"Could not show test notification: {error}")
        log_event(logging.INFO, "Notification requested title=%r", "🔔 Test Reminder")
        return 0

    if not args.list and args.reminder is None:
        parser.print_help()
        return 0

    try:
        schedule = load_timetable()
    except TimetableError as error:
        parser.error(str(error))

    if args.list:
        enabled = [reminder for reminder in schedule if reminder["enabled"]]
        if not enabled:
            print("No enabled reminders.")
        else:
            for reminder in enabled:
                duration = reminder.get("duration_minutes")
                duration_text = f" ({duration} min)" if duration is not None else ""
                print(f"{reminder['time']}  {reminder['title']}{duration_text}\n  {reminder['message']}")
        return 0

    requested_title = args.reminder.strip().casefold()
    reminder = next(
        (entry for entry in schedule if entry["title"].strip().casefold() == requested_title),
        None,
    )
    if reminder is None:
        log_event(logging.ERROR, "Reminder lookup failed title=%r", args.reminder)
        parser.error(f"No reminder titled {args.reminder!r} was found in {TIMETABLE_PATH}.")
    if not reminder["enabled"]:
        log_event(logging.ERROR, "Reminder is disabled title=%r", reminder["title"])
        parser.error(f"Reminder {reminder['title']!r} is disabled.")

    if args.scheduled and not is_latest_missed_reminder(schedule, reminder["title"]):
        log_event(logging.INFO, "Skipped stale scheduled reminder title=%r", reminder["title"])
        return 0

    try:
        show_notification(reminder["title"], reminder["message"])
    except Exception as error:
        log_event(logging.ERROR, "Notification failed title=%r: %s", reminder["title"], error)
        parser.error(f"Could not show reminder {reminder['title']!r}: {error}")
    log_event(logging.INFO, "Notification requested title=%r", reminder["title"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
