from __future__ import annotations
import subprocess
from datetime import datetime, timezone


def _escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"')


def get_existing_reminder_names(list_name: str) -> set[str]:
    """Return the set of reminder names already in the list."""
    script = f'''
tell application "Reminders"
    set listNames to {{}}
    try
        set theList to list "{_escape(list_name)}"
        repeat with r in reminders of theList
            set end of listNames to name of r
        end repeat
    end try
    return listNames
end tell
'''
    result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if result.returncode != 0:
        return set()
    # AppleScript returns comma-separated values
    raw = result.stdout.strip()
    if not raw:
        return set()
    return set(item.strip() for item in raw.split(","))


def ensure_list_exists(list_name: str) -> None:
    """Create the Reminders list if it doesn't exist."""
    script = f'''
tell application "Reminders"
    if not (exists list "{_escape(list_name)}") then
        make new list with properties {{name:"{_escape(list_name)}"}}
    end if
end tell
'''
    subprocess.run(["osascript", "-e", script], check=True, capture_output=True)


def add_reminder(list_name: str, title: str, due_at: str | None, notes: str = "") -> None:
    """Add a single reminder to the specified list."""
    # Build date block separately to avoid locale-dependent string parsing
    date_block = ""
    if due_at:
        try:
            dt = datetime.fromisoformat(due_at.replace("Z", "+00:00")).astimezone()
            date_block = f"""
    set dueDate to current date
    set year of dueDate to {dt.year}
    set month of dueDate to {dt.month}
    set day of dueDate to {dt.day}
    set hours of dueDate to {dt.hour}
    set minutes of dueDate to {dt.minute}
    set seconds of dueDate to {dt.second}
    set due date of newReminder to dueDate"""
        except Exception:
            pass

    notes_block = ""
    if notes:
        escaped_notes = _escape(notes)
        notes_block = f'\n    set body of newReminder to "{escaped_notes}"'

    script = f'''
tell application "Reminders"
    set theList to list "{_escape(list_name)}"
    set newReminder to make new reminder at theList with properties {{name:"{_escape(title)}"}}
{date_block}{notes_block}
end tell
'''
    subprocess.run(["osascript", "-e", script], check=True, capture_output=True)


def sync_assignments(assignments: list[dict], list_name: str) -> dict:
    """Add new assignments to Reminders, skip duplicates. Returns stats."""
    ensure_list_exists(list_name)
    existing = get_existing_reminder_names(list_name)

    added = 0
    skipped = 0
    for a in assignments:
        if a["submitted"]:
            skipped += 1
            continue
        if a["title"] in existing:
            skipped += 1
            continue
        notes = a["course_name"]
        if a["url"]:
            notes += f"\n{a['url']}"
        add_reminder(list_name, a["title"], a["due_at"], notes)
        added += 1

    return {"added": added, "skipped": skipped}
