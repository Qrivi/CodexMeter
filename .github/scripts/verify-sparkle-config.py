"""Fail before notarization if the exported app cannot start its updater."""

import base64
from pathlib import Path
import plistlib
import sys


try:
    info = plistlib.loads(Path(sys.argv[1]).read_bytes())
    public_key = info["SUPublicEDKey"]
    if not isinstance(public_key, str) or len(base64.b64decode(public_key, validate=True)) != 32:
        raise ValueError("Invalid public key")
except (OSError, KeyError, ValueError, TypeError, plistlib.InvalidFileException):
    print("The exported app must contain a valid 32-byte SUPublicEDKey.", file=sys.stderr)
    sys.exit(1)

print("Exported Sparkle public key is valid.")
