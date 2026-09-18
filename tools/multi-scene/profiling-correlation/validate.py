#!/usr/bin/env python3
"""Validate EXP-187 native receipts and an actual rum-mobile-events attachment."""
import argparse
import json
import math
import re
from pathlib import Path
from uuid import UUID

VIEW_NAMES = ["EXP187.StartA", "EXP187.StartB", "EXP187.Finish"]
LAUNCH_VIEW = "ApplicationLaunch"
BOUNDARIES = [
    "assert:1", "assert:2", "command:view:A", "assert:3",
    "command:start:A", "assert:4", "command:view:B", "assert:5",
    "command:start:B", "assert:6", "command:view:C", "assert:7",
    "command:end:B", "assert:8", "command:end:A", "assert:9", "assert:10",
    "command:stop:C", "assert:11", "assert:12",
]
OPERATION_COUNTS = [0, 0, 0, 1, 1, 2, 2, 3, 4, 4, 4, 4]
VITAL_FIELDS = {"id", "type", "name", "start_ns", "duration_ns"}


def require(value, message):
    if not value:
        raise ValueError(message)


def uuid(value):
    require(isinstance(value, str), "UUID must be a string")
    try:
        UUID(value)
    except (ValueError, AttributeError):
        raise ValueError("invalid UUID") from None
    return value


def integer(value, name):
    require(type(value) is int, name + " must be an integer")
    return value


def seconds_to_nanoseconds(seconds):
    # Match Swift Double.rounded() (nearest, ties away from zero), then Int64 saturation.
    value = float(seconds) * 1_000_000_000
    require(math.isfinite(value), "nonfinite nanosecond clock")
    fraction, integral = math.modf(value)
    rounded = int(integral)
    if abs(fraction) >= 0.5:
        rounded += 1 if fraction > 0 else -1
    return min(max(rounded, -(2 ** 63)), 2 ** 63 - 1)


def validate_native(receipt, run_id, revision, allow_simulator=False):
    require(run_id.startswith("exp187-"), "invalid run prefix")
    uuid(run_id[7:])
    require(re.fullmatch("[a-f0-9]{40}", revision), "invalid source revision")
    require(receipt["schemaVersion"] == 2 and receipt["experiment"] == "EXP-187", "wrong receipt schema")
    require(receipt["runID"] == run_id and receipt["sourceRevision"] == revision, "stale run/source identity")
    require(receipt["nativeStatus"] == "PASS", "native fixture did not pass")
    require(receipt["configuration"] == {"applicationLaunchSampleRate": 0, "continuousSampleRate": 100},
            "fixture requires continuous profiling at 100 percent")
    allowed = {"PHYSICAL_DEVICE"}
    if allow_simulator:
        allowed.add("SIMULATOR_MECHANICS_ONLY")
    require(receipt["platform"] in allowed, "physical device evidence required")
    require(integer(receipt["processID"], "processID") > 0, "invalid native process identity")
    require(receipt["backendStatus"] == "NOT_VERIFIED", "native receipt cannot certify backend")
    require(receipt["boundaries"] == BOUNDARIES, "missing, repeated or late critical boundary")
    checkpoints = receipt["checkpoints"]
    require(len(checkpoints) == 12, "expected 12 native assertions")
    for index, checkpoint in enumerate(checkpoints, 1):
        require(checkpoint["number"] == index and checkpoint["passed"] is True, "failed or reordered assertion")
        require(checkpoint["boundary"] == BOUNDARIES.index("assert:" + str(index)) + 1, "assertion boundary mismatch")
        require(checkpoint["operationCount"] == OPERATION_COUNTS[index - 1], "assertion missed critical Operation inventory")
        if index >= 3:
            require(checkpoint["profilingRunning"] is True, "profiler not ready before critical Operation boundary")

    observations = receipt["observations"]
    require(observations["ttidCount"] == 1, "missing or repeated launch readiness")
    require(observations["profilingRunning"] is True, "profiler stopped before receipt completion")
    views = observations["views"]
    require(len(views) == 4 and sorted(v["name"] for v in views) == sorted(VIEW_NAMES + [LAUNCH_VIEW]),
            "expected three fixture views and one built-in launch view")
    require(len({uuid(v["id"]) for v in views}) == 4, "collapsed view occurrences")
    require(all(v["active"] is False for v in views), "view not ended")
    sessions = {uuid(v["sessionID"]) for v in views}
    require(len(sessions) == 1, "views split across sessions")
    by_name = {v["name"]: v for v in views}
    operations = observations["operations"]
    require(len(operations) == 4, "wrong Operation inventory")
    require(len({uuid(op["vital"]["id"]) for op in operations}) == 4, "duplicate step ID")
    order = [("A", "start", VIEW_NAMES[0]), ("B", "start", VIEW_NAMES[1]),
             ("B", "end", VIEW_NAMES[2]), ("A", "end", VIEW_NAMES[2])]
    for op, (key, step, view) in zip(operations, order):
        require(op["operationKey"] == run_id + "/" + key and op["step"] == step, "wrong key/step order")
        require(op["viewID"] == by_name[view]["id"] and op["viewName"] == view, "wrong Operation owner")
        require(op["sessionID"] in sessions, "wrong Operation session")
        require(op["profilingRunning"] is True, "Operation observed before profiler readiness")
        require(op["vital"]["type"] == "vital" and op["vital"]["name"] == "exp187.parallel", "wrong Operation name/type")
        integer(op["vital"]["start_ns"], "start_ns")
        require(type(op["referenceTime"]) in (int, float) and type(op["serverTimeOffset"]) in (int, float), "missing observed native clock")
        require(math.isfinite(op["referenceTime"]) and math.isfinite(op["serverTimeOffset"]), "nonfinite observed native clock")
        expected_start = seconds_to_nanoseconds(op["referenceTime"] + op["serverTimeOffset"] + 978307200)
        require(op["vital"]["start_ns"] == expected_start, "clock/serialized timestamp mismatch")

    expected = []
    for start, end in [(operations[0], operations[3]), (operations[1], operations[2])]:
        vital = dict(start["vital"])
        vital["duration_ns"] = seconds_to_nanoseconds(end["referenceTime"] - start["referenceTime"])
        require(set(vital) == VITAL_FIELDS and vital["duration_ns"] > 0, "invalid expected duration/schema")
        expected.append(vital)
    require(expected[0]["duration_ns"] > expected[1]["duration_ns"], "independent durations collapsed or swapped")
    require(receipt["expectedProfileVitals"] == expected, "receipt expectation differs from actual messages")
    return expected


def validate_attachment(expected, attachment):
    require(isinstance(attachment, list) and len(attachment) == 2, "expected two profile Operation starts")
    require(all(isinstance(v, dict) and set(v) == VITAL_FIELDS for v in attachment), "attachment schema mismatch")
    require(len({v["id"] for v in attachment}) == 2, "duplicate attachment ID")
    for vital in attachment:
        integer(vital["start_ns"], "start_ns")
        integer(vital["duration_ns"], "duration_ns")
    require(sorted(attachment, key=lambda v: v["id"]) == sorted(expected, key=lambda v: v["id"]),
            "profile attachment differs from exact observed start identities/times")



def rum_page(response):
    match = re.search(r"<JSON_DATA>(.*?)</JSON_DATA>", response, re.S)
    count = re.search(r"<count>([0-9]+)</count>", response)
    require(match is not None and count is not None, "missing RUM response envelope")
    return int(count[1]), json.loads(match[1]) if match[1].strip() else []


def validate_rum_backend(receipt, response, counts_response, end_response):
    from collections import Counter
    total, rows = rum_page(response)
    end_total, end_rows = rum_page(end_response)
    require(total == 12 and len(rows) == total and end_total == total and not end_rows,
            "incomplete RUM session or pagination")
    require(len({r["id"] for r in rows}) == total, "duplicate backend event")
    match = re.search(r"<TSV_DATA>(.*?)</TSV_DATA>", counts_response, re.S)
    require(match is not None, "missing independent backend count")
    lines = match[1].strip().splitlines()
    require(lines[0] == "@type\tcount" and len(lines) == 5, "wrong backend count schema")
    counts = dict((kind, int(count)) for kind, count in (line.split("\t") for line in lines[1:]))
    require(counts == {"vital": 5, "view": 4, "operation": 2, "session": 1}, "unexpected backend inventory")
    events = [r["attributes"]["custom"] for r in rows]
    require(dict(Counter(e["type"] for e in events)) == counts, "count/page mismatch")
    observations = receipt["observations"]
    session = observations["operations"][0]["sessionID"]
    require(all(e["session"]["id"] == session and e["context"]["multiscene"]["run_id"] == receipt["runID"]
                for e in events), "stale backend run or session")
    views = {e["view"]["id"]: e["view"] for e in events if e["type"] == "view"}
    require(len(views) == 4, "duplicate backend view")
    for view in observations["views"]:
        actual = views[view["id"]]
        require(actual["name"] == view["name"] and actual["is_active"] is False, "wrong backend view occurrence")
        require(all(actual[field]["count"] == 0 for field in ["action", "resource", "error", "crash", "long_task"]),
                "unexpected telemetry count")
    steps = {e["vital"]["id"]: e for e in events if e["type"] == "vital" and e["vital"]["type"] == "operation_step"}
    require(set(steps) == {op["vital"]["id"] for op in observations["operations"]}, "wrong backend step identities")
    for op in observations["operations"]:
        event = steps[op["vital"]["id"]]
        vital = event["vital"]
        require((vital["name"], vital["operation_key"], vital["step_type"], event["view"]["id"]) ==
                (op["vital"]["name"], op["operationKey"], op["step"], op["viewID"]), "wrong backend Operation owner/key/step")
    operations = [e for e in events if e["type"] == "operation"]
    require(len({e["operation"]["operation_key"] for e in operations}) == 2, "collapsed backend Operations")
    for event in operations:
        op = event["operation"]
        starts = [x for x in observations["operations"] if x["operationKey"] == op["operation_key"] and x["step"] == "start"]
        ends = [x for x in observations["operations"] if x["operationKey"] == op["operation_key"] and x["step"] == "end"]
        require(len(starts) == len(ends) == 1, "unmatched backend Operation")
        require(op["name"] == "exp187.parallel" and op["status"] == "success" and
                event["vital"]["id"] == starts[0]["vital"]["id"] and
                op["start_view"]["id"] == starts[0]["viewID"] and op["end_view"]["id"] == ends[0]["viewID"],
                "wrong backend aggregate start/end ownership")
    launches = [e for e in events if e["type"] == "vital" and e["vital"]["type"] == "app_launch"]
    require(len(launches) == 1 and launches[0]["vital"]["name"] == "time_to_initial_display", "unexpected built-in vital")
    return {"state": "PASS", "counts": counts, "unique_events": total, "pagination_exhausted": True,
            "session_id": session, "exact_operation_step_ids": sorted(steps),
            "profiler_statuses": sorted({e["_dd"]["profiling"]["status"] for e in steps.values()}),
            "all_operation_steps_have_profile": all(e["profiling"]["has_profile"] is True for e in steps.values())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--source-revision", required=True)
    parser.add_argument("--allow-simulator", action="store_true", help="Fixture mechanics only; cannot close T14")
    parser.add_argument("--attachment", type=Path, help="Actual exported rum-mobile-events.json")
    parser.add_argument("--rum-response", type=Path, help="Full-session detailed MCP response, unmodified")
    parser.add_argument("--rum-counts", type=Path, help="Independent full-session aggregate MCP response")
    parser.add_argument("--rum-end-response", type=Path, help="Unmodified exhausted page response")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = {"experiment": "EXP-187", "gate": "T14", "gate_status": "INCONCLUSIVE",
              "native_validation": "NOT_RUN", "attachment_validation": "NOT_PROVIDED", "rum_validation": "NOT_PROVIDED",
              "remaining": ["complete backend RUM/profile inventory", "nonempty physical native wall-time stack samples",
                            "profile label/correlation evidence", "frozen build/install identity"]}
    try:
        receipt = json.loads(args.receipt.read_text())
        expected = validate_native(receipt, args.run_id, args.source_revision, args.allow_simulator)
        result["native_validation"] = "PASS"
        if any([args.rum_response, args.rum_counts, args.rum_end_response]):
            require(all([args.rum_response, args.rum_counts, args.rum_end_response]), "all three RUM responses required")
            result["rum_validation"] = validate_rum_backend(
                receipt, args.rum_response.read_text(), args.rum_counts.read_text(), args.rum_end_response.read_text())
        if args.attachment:
            validate_attachment(expected, json.loads(args.attachment.read_text()))
            result["attachment_validation"] = "PASS"
    except (ValueError, KeyError, TypeError, OverflowError, OSError) as error:
        result["gate_status"] = "FAIL"
        result["validation_error"] = str(error)
    with args.output.open("x") as output:
        output.write(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))
    raise SystemExit(1 if result["gate_status"] == "FAIL" else 0)


if __name__ == "__main__":
    main()
