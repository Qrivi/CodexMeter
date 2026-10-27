"""Assemble per-release Markdown for Sparkle's update dialog."""

import argparse
from pathlib import Path
import re


HISTORY_URL = "https://github.com/Qrivi/CodexMeter/releases"
HISTORY_LINK = f"[View full release history on GitHub]({HISTORY_URL})"


def version_number(value):
    match = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", value)
    if not match:
        raise ValueError("Expected a stable version such as v1.3.1")
    return tuple(map(int, match.groups()))


def combined_notes(notes_directory, latest, after=None):
    latest_number = version_number(latest)
    installed_number = version_number(after) if after else None
    latest_file = notes_directory / f"v{'.'.join(map(str, latest_number))}.md"
    if not latest_file.is_file() or not latest_file.read_text(encoding="utf-8").strip():
        raise ValueError(f"Missing non-empty release notes for {latest}")

    releases = []
    for path in notes_directory.glob("v*.md"):
        try:
            number = version_number(path.stem)
        except ValueError:
            continue
        if number > latest_number or (installed_number is not None and number <= installed_number):
            continue
        body = path.read_text(encoding="utf-8").strip()
        if not body:
            raise ValueError(f"Empty release notes: {path.name}")
        # The version heading already groups the highlights in the combined view.
        body = re.sub(r"(?m)^## Highlights\s*\n", "", body).strip()
        version = ".".join(map(str, number))
        releases.append((number, f"# Version {version}\n\n{body}"))

    sections = [body for _, body in sorted(releases, reverse=True)]
    return "\n\n".join([*sections, HISTORY_LINK]) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("latest")
    parser.add_argument("output", type=Path)
    parser.add_argument("--after", help="Only include newer versions, for a preview")
    parser.add_argument("--notes-directory", type=Path,
                        default=Path(__file__).resolve().parents[1] / "release-notes")
    args = parser.parse_args()
    try:
        content = combined_notes(args.notes_directory, args.latest, args.after)
    except ValueError as error:
        parser.error(str(error))
    args.output.write_text(content, encoding="utf-8")


if __name__ == "__main__":
    main()
