"""Semantic checks for the finite PR10 legacy Operations source pair.

A result from this module is component-oracle evidence only. Native admission,
source/product identity, raw artifact custody and cleanup are separate obligations.
"""
from __future__ import annotations

import base64
import copy
from collections import Counter
from decimal import Decimal, ROUND_DOWN
from datetime import datetime, timezone
from typing import Any

NULL_VIEW = "00000000-0000-0000-0000-000000000000"
NO_VIEW_WARNING = (
    "RUM operation step command received without an active view. "
    "This may result in incomplete context information."
)

# (name, key, step, failure reason, message expected, command attribute)
RUM_STEPS = {
    "success": [("success", None, "start", None, True, ("start-attribute", "success")),
                ("success", None, "end", None, True, ("end-attribute", "success"))],
    "failure": [("failure", "request-1", "start", None, True, ("start-attribute", "failure")),
                ("failure", "request-1", "end", "error", True, ("failure-attribute", "retained"))],
    "profiling-options": [("sampled-out", None, "start", None, False, ("start-attribute", "sampled-out")),
                          ("sampled-out", None, "end", None, True, ("end-attribute", "sampled-out")),
                          ("no-options", None, "start", None, False, ("start-attribute", "no-options")),
                          ("no-options", None, "end", None, True, ("end-attribute", "no-options"))],
    "duplicate-and-orphan": [("repeat", "same-key", "start", None, True, ("start-attribute", "repeat")),
                             ("repeat", "same-key", "start", None, True, ("start-attribute", "repeat")),
                             ("repeat", "same-key", "end", None, True, ("end-attribute", "repeat")),
                             ("orphan", "missing-key", "end", None, True, ("end-attribute", "orphan"))],
    "legacy-key-collision": [("ab", "c", "start", None, True, ("start-attribute", "ab")),
                             ("a", "bc", "start", None, True, ("start-attribute", "a")),
                             ("ab", "c", "end", None, True, ("end-attribute", "ab")),
                             ("a", "bc", "end", None, True, ("end-attribute", "a"))],
    "deprecated-aliases": [("alias-success", None, "start", None, False, ("alias", "start")),
                           ("alias-success", None, "end", None, True, ("alias", "end")),
                           ("alias-failure", "key", "start", None, False, None),
                           ("alias-failure", "key", "end", "abandoned", True, None)],
    "off-view": [("source-less", None, "start", None, True, ("start-attribute", "source-less")),
                 ("source-less", None, "end", None, True, ("end-attribute", "source-less")),
                 ("background", None, "start", None, True, ("start-attribute", "background")),
                 ("background", None, "end", None, True, ("end-attribute", "background"))],
    "session-boundaries": [("before-stop", None, "start", None, True, ("start-attribute", "before-stop")),
                           ("before-stop", None, "end", None, True, ("end-attribute", "before-stop")),
                           ("after-stop", None, "start", None, True, ("start-attribute", "after-stop")),
                           ("after-stop", None, "end", None, True, ("end-attribute", "after-stop")),
                           ("after-expiry", None, "start", None, True, ("start-attribute", "after-expiry")),
                           ("after-expiry", None, "end", None, True, ("end-attribute", "after-expiry"))],
}
PROFILE_IDS = {
    "empty": [], "non-step": [], "completed": [["completed-start"]],
    "ongoing": [["ongoing-start"], ["ongoing-start"]],
    "continuous-non-step": [["continuous-ttid", "continuous-ttfd"]],
    "continuous-duration-events": [["continuous-hang", "continuous-long-task"]],
    "orphan-and-latest-start": [["latest-start"]],
    "original-snapshot": [["original-start", "original-non-step", "original-hang", "original-long-task"]],
    "consent-regrant": [["regrant-start"]], "quota-regrant": [["regrant-start"]],
    "mixed-ongoing": [["mixed-completed", "mixed-ongoing", "mixed-non-step", "mixed-hang", "mixed-long-task"],
                      ["mixed-ongoing"]],
}
PROFILE_LABELS = {
    "completed-start": "completed", "ongoing-start": "ongoing",
    "continuous-ttid": "ttid", "continuous-ttfd": "ttfd",
    "latest-start": "repeated", "original-start": "original-operation",
    "original-non-step": "original-non-step", "regrant-start": "regrant",
    "mixed-completed": "completed", "mixed-ongoing": "ongoing", "mixed-non-step": "non-step",
}
PROFILE_FAMILIES = {
    **{name: "completion" for name in ("empty", "non-step", "completed", "ongoing",
                                      "continuous-non-step", "continuous-duration-events")},
    "orphan-and-latest-start": "keying", "original-snapshot": "deferred-writer",
    "consent-regrant": "consent-and-quota", "quota-regrant": "consent-and-quota",
    "mixed-ongoing": "extension-and-cleanup",
}
# Whole raw inventories remain stored. Only declared measurements leave comparison.
VIEW_DIAGNOSTICS = {
    "time_spent", "loading_time", "first_byte", "dom_complete", "dom_content_loaded",
    "dom_interactive", "load_event", "first_contentful_paint", "largest_contentful_paint",
    "first_input_delay", "first_input_time", "cumulative_layout_shift",
    "cpu_ticks", "cpu_ticks_count", "cpu_time", "memory_average", "memory_max",
    "refresh_rate_average", "refresh_rate_min", "slow_rendered_ticks",
    "flutter_first_build_complete", "flutter_first_build_complete_ns",
}


def _require(condition: bool, fault: str) -> None:
    if not condition:
        raise ValueError(fault)


def _operation_name(name: str, key: str | None) -> str:
    return f"\x60{name}\x60" + (f" (key \x60{key}\x60)" if key is not None else "")


def _duplicate(name: str, key: str) -> str:
    return (
        f"Operation {_operation_name(name, key)} has already been started. "
        "This may result in the backend terminating the previous instance with an \x60auto_restart\x60 failure. "
        "Note that the SDK only tracks operations locally and not across sessions."
    )


def _orphan(name: str, key: str | None) -> str:
    return (
        f"\x60end\x60 was called, but operation {_operation_name(name, key)} is currently not active. "
        "This may lead to a backend \x60instrumentation_error\x60. Make sure to call "
        "\x60startOperation(name:operationKey:attributes:options:)\x60 first. "
        "Note that the SDK only tracks operations locally and not across sessions."
    )


RUM_WARNINGS = {name: [] for name in RUM_STEPS}
RUM_WARNINGS.update({
    "duplicate-and-orphan": [_duplicate("repeat", "same-key"), _orphan("orphan", "missing-key")],
    "legacy-key-collision": [_duplicate("a", "bc"), _orphan("a", "bc")],
    "off-view": [NO_VIEW_WARNING, NO_VIEW_WARNING],
    "session-boundaries": [NO_VIEW_WARNING, _orphan("before-stop", None), NO_VIEW_WARNING, NO_VIEW_WARNING],
})


# The fixture stops Home, then the absent Successor, before capturing warnings.
# These are fixed command-clock values, not runtime performance thresholds.
FINAL_STOP_OFFSETS = {
    "success": 2, "failure": 1, "profiling-options": 4,
    "duplicate-and-orphan": 4, "legacy-key-collision": 4, "deprecated-aliases": 2,
}
for _name, _offset in FINAL_STOP_OFFSETS.items():
    _time = datetime.fromtimestamp(1_700_000_000 + _offset, timezone.utc).strftime("%Y-%m-%d %H:%M:%S +0000")
    RUM_WARNINGS[_name].append(
        "RUMStopViewCommand(target: DatadogRUM.RUMCommandTarget.processRepresentative, "
        f"time: {_time}, globalAttributes: [:], attributes: [:], "
        "canStartApplicationLaunchView: false, canStartBackgroundView: false, "
        "shouldRestartLastViewAfterSessionExpiration: false, shouldRestartLastViewAfterSessionStop: false, "
        "canStartBackgroundViewAfterSessionStop: false, isUserInteraction: false, "
        'identity: DatadogRUM.ViewIdentifier.key("successor"), missedEventType: nil) '
        "was detected, but no view is active. To track views automatically, configure\n"
        "`RUM.Configuration.uiKitViewsPredicate` or use `.trackRUMView()` modifier in SwiftUI. "
        "You can also track views manually\n"
        "with `RUMMonitor.shared().startView()` and `RUMMonitor.shared().stopView()`."
    )


def _check_rum(scenario: dict[str, Any]) -> None:
    name = scenario["name"]
    raw = scenario["raw_events"]
    _require(isinstance(raw, list) and all(isinstance(row, dict) for row in raw), "raw-inventory")
    vitals = [row for row in raw if row.get("type") == "vital" and row.get("vital", {}).get("type") == "operation_step"]
    steps = RUM_STEPS[name]
    _require(len(vitals) == len(steps), "vital-count")
    _require(len({row["vital"]["id"] for row in vitals}) == len(vitals), "duplicate-vital-id")
    messages = scenario["messages"]
    _require(len(messages) == sum(step[4] for step in steps), "message-count")
    owners = []
    owner_names = [None if (name == "off-view" and i < 2) or (name == "session-boundaries" and 1 <= i <= 3)
                   else "Background" if name == "off-view"
                   else "Successor" if name == "session-boundaries" and i >= 4
                   else "Home" for i in range(len(steps))]
    for row, (operation, key, step, reason, _, attribute) in zip(vitals, steps):
        vital = row["vital"]
        _require((vital.get("name"), vital.get("operation_key"), vital.get("step_type"),
                  vital.get("failure_reason")) == (operation, key, step, reason), "vital-step-key-reason")
        _require(row["application"]["id"] == "legacy-trace-application", "application-owner")
        _require(bool(row["session"]["id"]), "session-owner")
        _require(bool(row["view"]["id"]), "view-owner")
        if attribute:
            _require(row.get("context", {}).get(attribute[0]) == attribute[1], "command-attributes")
        owners.append((row["session"]["id"], row["view"]["id"]))
    expected_message_vitals = [(row, owner_name) for row, owner_name, step in zip(vitals, owner_names, steps) if step[4]]
    for message, (row, owner_name) in zip(messages, expected_message_vitals):
        vital = row["vital"]
        _require(message.get("type") == "OperationMessage", "legacy-message-type")
        _require((message.get("id"), message.get("name"), message.get("key"), message.get("step"))
                 == (vital["id"], vital["name"], vital.get("operation_key"), vital["step_type"]), "message-vital-join")
        milliseconds = int(((Decimal(str(message["date"])) + Decimal(str(message["server_offset"]))) * 1000)
                           .to_integral_value(rounding=ROUND_DOWN))
        _require(row["date"] == milliseconds, "message-date-join")
        attrs = message["attributes"]
        _require(attrs.get("application.id") == row["application"]["id"], "message-application-owner")
        _require(attrs.get("session.id") == row["session"]["id"], "message-session-owner")
        if row["view"]["id"] == NULL_VIEW:
            _require("view.id" not in attrs and "view.name" not in attrs, "null-view-message-owner")
        else:
            _require(attrs.get("view.id") == [row["view"]["id"]], "message-view-owner")
            _require(attrs.get("view.name") == [owner_name], "message-view-name")
    callbacks = scenario["session_callbacks"]
    if name == "session-boundaries":
        s0, s1, s2 = owners[0][0], owners[1][0], owners[4][0]
        _require(len({s0, s1, s2}) == 3, "session-not-refreshed")
        _require([owner[0] for owner in owners] == [s0, s1, s1, s1, s2, s2], "session-step-owners")
        _require(callbacks == [s0, "nil", s1, s2, "nil"], "session-callbacks")
        _require(all(view == NULL_VIEW for _, view in owners[1:4]), "post-stop-view-owner")
        _require(owners[4][1] != NULL_VIEW and owners[4][1] == owners[5][1], "refreshed-view-owner")
    else:
        _require(len({session for session, _ in owners}) == 1, "unexpected-session-change")
        _require(callbacks == [owners[0][0], "nil"], "session-callbacks")
    if name == "off-view":
        _require([view for _, view in owners[:2]] == [NULL_VIEW, NULL_VIEW], "source-less-view-owner")
        _require(owners[2][1] != NULL_VIEW and owners[2][1] == owners[3][1], "background-view-owner")
    elif name != "session-boundaries":
        _require(len({view for _, view in owners}) == 1 and owners[0][1] != NULL_VIEW, "home-view-owner")
    views = [row for row in raw if row.get("type") == "view"]
    _require(any(row["view"].get("name") == "Home" for row in views), "home-view-missing")
    for (session, view), owner_name, vital in zip(owners, owner_names, vitals):
        if owner_name is None:
            _require(view == NULL_VIEW and vital["view"]["url"] == "", "null-view-wire-owner")
        else:
            _require(view != NULL_VIEW and any(
                row["session"]["id"] == session and row["view"]["id"] == view
                and row["view"].get("name") == owner_name
                and row["view"].get("url") == vital["view"].get("url") for row in views),
                "vital-view-inventory-join")
    _require(scenario["warnings"] == RUM_WARNINGS[name], "warning-inventory")
    _require(scenario["errors"] == [], "unexpected-errors")
    _require(scenario["provider_calls"] == 0, "owned-provider-reached")
    # The filtered projection is captured for convenience; raw rows decide acceptance.
    _require(len(scenario["events"]) == len(raw), "projection-inventory")
    projection_keys = {"type", "date", "application", "session", "view", "vital", "context", "action", "error"}
    _require(scenario["events"] == [{key: value for key, value in row.items() if key in projection_keys}
                                    for row in raw], "projection-receipt")


PROFILE_IDS["default-background-stop"] = [["default-background-start"]]
PROFILE_LABELS["default-background-start"] = "default-background"
PROFILE_FAMILIES["default-background-stop"] = "completion"
ORIGINAL_ATTRIBUTES = {
    "application.id": "original-application", "session.id": "original-session",
    "view.id": ["original-view"], "fixture-attribute": "original",
}
LATER_ATTRIBUTES = {
    "application.id": "later-application", "session.id": "later-session",
    "view.id": ["later-view"], "fixture-attribute": "later",
}
BASE_DATE = 1_700_000_000

def _vital_input(identifier, name, step=None, key=None, seconds=0, duration=None,
                 later=False, ttid=False, consumed=False):
    return {"label": identifier, "kind": "TTIDMessage" if ttid else "OperationMessage",
            "consumed": consumed, "attributes": LATER_ATTRIBUTES if later else ORIGINAL_ATTRIBUTES,
            "vital": {"id": identifier, "name": name, "key": key, "step": step,
                      "date": BASE_DATE + seconds, "server_offset": 0, "duration": duration}}


def _context_input(label, state="active", consent="granted"):
    return {"label": label, "kind": "context", "consumed": False,
            "app_state": state, "consent": consent}


def _duration_input(identifier, task=False):
    return {"label": identifier, "kind": "LongTaskMessage" if task else "AppHangMessage",
            "consumed": True, "attributes": ORIGINAL_ATTRIBUTES,
            "duration_event": {"id": identifier, "type": "long_task" if task else "error",
                               "start_ns": 789 if task else 123, "duration_ns": 100 if task else 456}}


BACKGROUND = _context_input("background", "background")
PROFILE_INPUTS = {
    "empty": [BACKGROUND],
    "non-step": [_vital_input("ttid", "ttid", duration=100, ttid=True, consumed=True),
                 _vital_input("ttfd", "ttfd", consumed=True), BACKGROUND],
    "completed": [_vital_input("completed-start", "completed", "start", "request"),
                  _vital_input("completed-end", "completed", "end", "request", seconds=6)],
    "ongoing": [_vital_input("ongoing-start", "ongoing", "start"), BACKGROUND, BACKGROUND],
    "default-background-stop": [_vital_input("default-background-start", "default-background", "start"),
                                BACKGROUND, BACKGROUND],
    "continuous-non-step": [_vital_input("continuous-ttid", "ttid", duration=100, ttid=True, consumed=True),
                            _vital_input("continuous-ttfd", "ttfd", consumed=True), BACKGROUND],
    "continuous-duration-events": [_duration_input("continuous-hang"),
                                   _duration_input("continuous-long-task", task=True), BACKGROUND],
    "orphan-and-latest-start": [
        _vital_input("orphan-end", "orphan", "end", later=True),
        _vital_input("first-start", "repeated", "start", "same-key"),
        _vital_input("latest-start", "repeated", "start", "same-key", seconds=1),
        _vital_input("latest-end", "repeated", "end", "same-key", seconds=7)],
    "original-snapshot": [
        _vital_input("original-start", "original-operation", "start"),
        _vital_input("original-non-step", "original-non-step"),
        _duration_input("original-hang"), _duration_input("original-long-task", task=True), BACKGROUND,
        _vital_input("later-non-step", "later-non-step", later=True), _context_input("later-context")],
    "consent-regrant": [
        _context_input("consent-not-granted", consent="notGranted"),
        _vital_input("rejected-start", "rejected", "start"),
        _context_input("consent-granted"), _vital_input("regrant-start", "regrant", "start"),
        _vital_input("regrant-end", "regrant", "end", seconds=6)],
    "quota-regrant": [_vital_input("rejected-start", "rejected", "start"),
                      _vital_input("regrant-start", "regrant", "start"),
                      _vital_input("regrant-end", "regrant", "end", seconds=6)],
    "mixed-ongoing": [_vital_input("mixed-completed", "completed", "start"),
                      _vital_input("mixed-ongoing", "ongoing", "start"),
                      _vital_input("mixed-non-step", "non-step"), _duration_input("mixed-hang"),
                      _duration_input("mixed-long-task", task=True),
                      _vital_input("mixed-end", "completed", "end", seconds=6),
                      BACKGROUND, BACKGROUND, _context_input("past-cutoff")],
}
for _inputs in PROFILE_INPUTS.values():
    _inputs.insert(0, _context_input("initial-context"))

EXPECTED_ATTACHMENT_ROWS = {}
for _inputs in PROFILE_INPUTS.values():
    for _input in _inputs:
        if "duration_event" in _input:
            EXPECTED_ATTACHMENT_ROWS[_input["label"]] = _input["duration_event"]
        elif "vital" in _input:
            _vital = _input["vital"]
            if _vital["step"] == "end":
                continue
            _row = {"id": _vital["id"], "type": "vital", "name": _vital["name"],
                    "start_ns": int((Decimal(str(_vital["date"])) + Decimal(str(_vital["server_offset"]))) * 1_000_000_000)}
            if _vital["duration"] is not None:
                _row["duration_ns"] = _vital["duration"]
            EXPECTED_ATTACHMENT_ROWS[_vital["id"]] = _row
for _identifier in ("completed-start", "latest-start", "regrant-start", "mixed-completed"):
    EXPECTED_ATTACHMENT_ROWS[_identifier]["duration_ns"] = 6_000_000_000


def _check_profile(scenario: dict[str, Any]) -> None:
    name = scenario["name"]
    _require(scenario["family"] == PROFILE_FAMILIES[name], "profile-family")
    profiles = scenario["profiles"]
    _require(len(profiles) == len(PROFILE_IDS[name]), "profile-count")
    _require(isinstance(scenario["inputs"], list) and bool(scenario["inputs"]), "input-receipts")
    expected_inputs = PROFILE_INPUTS[name]
    _require(len(scenario["inputs"]) == len(expected_inputs), "message-input-inventory")
    for actual_input, expected_input in zip(scenario["inputs"], expected_inputs):
        actual = dict(actual_input)
        if expected_input["kind"] == "context":
            version = actual.pop("version")
            _require(isinstance(version, str) and bool(version), "context-version")
            if expected_input["label"] == "later-context":
                _require(version == "later-version", "later-context-version")
        _require(actual == expected_input, "message-input-fields")
    _require(scenario["configured_background_eligibility"] == (name in ("ongoing", "mixed-ongoing")),
             "background-conditions")
    _require(bool(scenario["checkpoints"]), "state-checkpoints")
    final = scenario["checkpoints"][-1]
    _require(final["label"] == "terminal" and final["pending"] == 0, "deferred-write-pending")
    _require(final["written"] == len(profiles), "writer-inventory")
    for profile, expected_ids in zip(profiles, PROFILE_IDS[name]):
        rows = profile["rum_events"]
        groups = [row.get("type") for row in rows]
        _require(all(group in ("vital", "error", "long_task") for group in groups), "attachment-type")
        ranks = {"vital": 0, "error": 1, "long_task": 2}
        _require([ranks[group] for group in groups] == sorted(ranks[group] for group in groups),
                 "attachment-group-order")
        ids = [row["id"] for row in rows]
        _require(Counter(ids) == Counter(expected_ids), "profile-attachment-ids")
        _require(len(set(ids)) == len(ids), "duplicate-attachment-id")
        for row in rows:
            _require(row == EXPECTED_ATTACHMENT_ROWS[row["id"]], "attachment-fields")
        try:
            pprof = base64.b64decode(profile["pprof_base64"], validate=True)
        except (ValueError, TypeError) as error:
            raise ValueError("pprof-encoding") from error
        _require(bool(pprof), "pprof-empty")
        event = profile["event"]
        _require(event["family"] == "ios" and event["runtime"] == "ios" and event["version"] == "4", "profile-format")
        _require(event["attachments"] == ["profile.pprof", "rum-mobile-events.json"], "profile-attachment-names")
        _require(event.get("application.id") == "original-application", "profile-application-owner")
        _require(event.get("session.id") == "original-session", "profile-session-owner")
        _require(event.get("view.id") == ["original-view"], "profile-view-owner")
        _require(event.get("fixture-attribute") == "original", "profile-snapshot-attributes")
        vitals = [row for row in rows if row.get("type") == "vital"]
        _require(all(row.get("name") == PROFILE_LABELS.get(row["id"]) for row in vitals), "profile-vital-label")
        if vitals:
            _require(event.get("vital.id") == [row["id"] for row in vitals], "profile-vital-id-join")
            _require(event.get("vital.label") == [row["name"] for row in vitals], "profile-vital-label-join")
        else:
            _require("vital.id" not in event and "vital.label" not in event, "unexpected-vital-attributes")
        hangs = [row["id"] for row in rows if row.get("type") == "error"]
        tasks = [row["id"] for row in rows if row.get("type") == "long_task"]
        _require(event.get("error.id") == hangs and event.get("long_task.id") == tasks, "duration-event-joins")
        if name == "original-snapshot":
            _require("version:later-version" in event["tags_profiler"].split(","), "deferred-current-context")
    if name == "original-snapshot":
        checkpoints = {row["label"]: row for row in scenario["checkpoints"]}
        before = checkpoints["before-mutation"]
        later = checkpoints["before-release"]
        _require(before["pending"] == later["pending"] == 1 and before["written"] == later["written"] == 0,
                 "deferred-boundary")
        _require(before["attributes"].get("fixture-attribute") == "original"
                 and later["attributes"].get("fixture-attribute") == "later", "mutation-not-observed")
    if name in ("consent-regrant", "quota-regrant"):
        refused = next(row for row in scenario["checkpoints"] if row["label"] == "refused")
        _require(refused["pending"] == refused["written"] == 0 and refused["attributes"] == {}, "refusal-state")
    _require(scenario["quota_inputs"] == (["quotaKO", "pending"] if name == "quota-regrant" else []),
             "quota-driver-inputs")


def validate_trace(trace: dict[str, Any]) -> None:
    _require(trace.get("schema_version") == 1 and trace.get("terminal") is True, "terminal-inventory")
    family = trace.get("family")
    _require(family in ("legacy-operations", "legacy-profiling"), "trace-family")
    _require(type(trace.get("pid")) is int and trace["pid"] > 0, "actual-process")
    _require(isinstance(trace.get("loaded_images"), list) and bool(trace["loaded_images"]), "loaded-images")
    expected = list(RUM_STEPS) if family == "legacy-operations" else list(PROFILE_IDS)
    scenarios = trace["scenarios"]
    # Preserve the fixture's original declared journey order, not dictionary grouping.
    if family == "legacy-profiling":
        expected = ["empty", "non-step", "completed", "ongoing", "default-background-stop", "continuous-non-step",
                    "continuous-duration-events", "orphan-and-latest-start", "original-snapshot",
                    "consent-regrant", "quota-regrant", "mixed-ongoing"]
    _require([row["name"] for row in scenarios] == expected, "scenario-inventory")
    for scenario in scenarios:
        _require(scenario.get("terminal") is True, "scenario-terminal")
        (_check_rum if family == "legacy-operations" else _check_profile)(scenario)


def _canonical(trace: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(trace)
    # Paths/PIDs remain bound by native custody, not cross-process semantic equality.
    result.pop("pid")
    result.pop("loaded_images")
    for scenario in result["scenarios"]:
        if result["family"] == "legacy-operations":
            scenario.pop("events")
            for row in scenario["raw_events"]:
                if row.get("type") == "view":
                    view = row["view"]
                    for key in VIEW_DIAGNOSTICS:
                        view.pop(key, None)
        else:
            for profile in scenario["profiles"]:
                profile.pop("pprof_base64")
                event = profile["event"]
                event.pop("start")
                event.pop("end")
                # Only dictionaries' vital array order is unspecified. Joined labels
                # were checked against the original raw array before normalization.
                vitals = [row for row in profile["rum_events"] if row["type"] == "vital"]
                other = [row for row in profile["rum_events"] if row["type"] != "vital"]
                vitals.sort(key=lambda row: row["id"])
                profile["rum_events"] = vitals + other
                if vitals:
                    event["vital.id"] = [row["id"] for row in vitals]
                    event["vital.label"] = [row["name"] for row in vitals]
    return result


def compare(parent: dict[str, Any], current: dict[str, Any]) -> dict[str, Any]:
    try:
        validate_trace(parent)
        validate_trace(current)
        _require(parent["family"] == current["family"], "pair-family")
        equal = _canonical(parent) == _canonical(current)
        return {"verdict": "PASS" if equal else "FAIL",
                "faults": [] if equal else ["semantic-source-pair-difference"],
                "scope": "FINITE_COMPONENT_ORACLE_ONLY",
                "gates_closed": []}
    except (ValueError, KeyError, TypeError, StopIteration, AttributeError, ArithmeticError) as error:
        fault = str(error) if isinstance(error, ValueError) else f"schema-{type(error).__name__}"
        return {"verdict": "INCOMPLETE" if fault in ("terminal-inventory", "scenario-terminal") else "FAIL",
                "faults": [fault], "scope": "FINITE_COMPONENT_ORACLE_ONLY", "gates_closed": []}
