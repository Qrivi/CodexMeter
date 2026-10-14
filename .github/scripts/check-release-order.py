"""Prevent an older release retry from replacing newer Sparkle feeds."""

import re
import sys


def version(tag):
    match = re.fullmatch(r"v([0-9]+)\.([0-9]+)\.([0-9]+)", tag)
    return tuple(map(int, match.groups())) if match else None


candidate = version(sys.argv[1])
if candidate is None:
    sys.exit("Expected a stable v<major>.<minor>.<patch> release tag.")

published = (version(tag.strip()) for tag in sys.stdin)
latest = max((item for item in published if item is not None), default=(0, 0, 0))
if candidate < latest:
    sys.exit("A newer stable release is already published. Refusing to replace its update feeds.")

print("Release order is valid for publication.")
