"""Shared strict acceptance checks; no environment or connector state."""
import hashlib
import json


class Rejected(RuntimeError):
    def __init__(self, message, state="INVALID"):
        super().__init__(message)
        self.state = state


def require(value, message, state="INVALID"):
    if not value:
        raise Rejected(message, state)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def require_before(signal, boundary, label):
    require(signal["sequence"] < boundary["sequence"], label + " arrived after its critical boundary", "FAIL")


def require_identity(actual, expected, label):
    require(actual == expected, "stale or changed " + label)


def unique(items, label):
    require(len(items) == 1, f"{label}: expected exactly one, received {len(items)}", "FAIL")
    return items[0]
