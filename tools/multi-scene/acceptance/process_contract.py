"""T12: real process producers follow one representative, with exact backend inventory."""
import json
import math
from pathlib import Path
from acceptance_common import canonical, require, require_before, require_identity, unique
from log_contract import valid_uuid

SCENARIO = "process-signals.representative.cross-scene-serial"
CONTRACT = "process-scenario-contract.json"
MINIMUM_TESTS = 192
GUARDS = ["process-configuration", "process-owner-a", "process-owner-b"]
def round_guards(suffix):
    return ["process-" + suffix + "-" + part for part in [
        "representative", "memory-boundary", "memory-acknowledged",
        "block-began", "block-ended", "signals-acknowledged"]]
GUARDS += round_guards("b") + ["process-a-retired", "process-a-activation-requested",
                                   "process-a-activation-acknowledged", "process-selection-boundary",
                                   "process-selection-acknowledged"]
GUARDS += round_guards("a") + ["process-inventory-verified", "process-batch-complete"]
PROJECT_KEYS = {
    "run_id", "session_id", "view_id", "name", "source", "container_present", "action_present",
    "event_id", "duration_ns", "error_source", "error_source_type", "error_type", "error_category",
    "is_crash", "action_type", "action_target", "view_long_task_count", "view_error_count",
    "view_action_count", "view_resource_count", "view_crash_count",
}


def owner(signal):
    context = signal.get("rumContext", {})
    value = dict(session_id=context.get("sessionID"), view_id=context.get("viewID"))
    require(all(valid_uuid(v) for v in value.values()), "malformed process owner", "FAIL")
    return value


def exact(actual, expected, message):
    require(canonical(actual) == canonical(expected), message, "FAIL")


def validate_local(records, run_id):
    manifest = unique([r["manifest"] for r in records if r["type"] == "manifest"], "manifest")
    require(manifest.get("runID") == run_id and manifest.get("runMode") == "clean"
            and not manifest.get("validationErrors"), "stale or invalid clean manifest")
    require_identity(manifest.get("scenario"), json.loads(Path(__file__).with_name(CONTRACT).read_text()),
                     "process producer fixture")
    signals = [r["signal"] for r in records if r["type"] == "signal"]
    require(signals and all(s.get("schemaVersion") == 5 and s.get("runID") == run_id
                           and s.get("scenarioID") == SCENARIO for s in signals), "stale signal identity")
    require([s.get("sequence") for s in signals] == list(range(1, len(signals) + 1)), "signal sequence")
    require(all(type(s.get("timestampMilliseconds")) is int and s["timestampMilliseconds"] > 0
                for s in signals), "missing native clock")
    terminal = unique([r for r in records if r["type"] == "semantic-result"], "terminal")
    result = terminal.get("result", {})
    require(terminal.get("runID") == run_id and result.get("scenarioID") == SCENARIO, "stale terminal")
    exact({k: result.get(k) for k in ["state", "matchedExpectationCount", "issues"]},
          dict(state="PASS", matchedExpectationCount=46, issues=[]), "native oracle did not pass")
    assertions = [s for s in signals if s.get("kind") == "assertion"]
    exact([s.get("name") for s in assertions], GUARDS, "missing, duplicate or late process guard")
    require(all(s.get("result") == "PASS" and s.get("evidenceSource") == "internal-hook"
                for s in assertions), "unacknowledged process guard", "FAIL")
    require(not any(s.get("result") == "FAIL" for s in signals), "failed native assertion", "FAIL")
    guard = {s["name"]: s for s in assertions}
    batch = unique([s for s in signals if s.get("kind") == "step-started"
                    and s.get("stepKind") == "run-process-signal-batch"], "process batch")
    require_before(batch, assertions[0], "configuration before stimulus")
    exact(guard["process-configuration"].get("processSignal"), dict(
        longTaskThreshold=0.5, appHangThreshold=0.5, hasLongTaskObserver=True,
        hasAppHangMonitor=True, hasMemoryWarningMonitor=True), "actual producer configuration differs")
    snapshots = [s for s in signals if s.get("kind") == "rum-view-snapshot"]
    require(all(s.get("evidenceSource") == "rum-mapper" for s in snapshots), "view mapper source", "FAIL")
    owners, native = {}, {}
    for suffix, label in [("a", "scene-A"), ("b", "scene-B")]:
        claimed = guard["process-owner-" + suffix]
        owners[suffix] = owner(claimed)
        ready = unique([s for s in signals if s.get("kind") == "scene-ready"
                        and s.get("semanticContext", {}).get("logicalSceneID") == label], "native readiness")
        native[label] = ready.get("semanticContext", {}).get("nativeSceneID")
        require(isinstance(native[label], str) and bool(native[label]), "missing actual native scene")
        exact(claimed.get("sourceContext", {}).get("nativeSceneID"), native[label], "SDK/native scene mismatch")
        exact(claimed.get("sourceContext", {}).get("logicalSceneID"), label, "scene snapshot label mismatch")
        require(ready.get("evidenceSource") == "probe" and ready.get("scenePhase") == "ready"
                and ready.get("activationState") in ["foreground-active", "foreground-inactive", "background"],
                "actual scene readiness missing")
        require_before(ready, batch, "readiness before process batch")
        homes = [s for s in snapshots if s.get("semanticContext", {}).get("logicalSceneID") == label
                 and s["sequence"] < claimed["sequence"]]
        require(homes and all(owner(s) == owners[suffix] for s in homes), "independent Home owner missing", "FAIL")
        require(homes[-1].get("rumContext", {}).get("viewActive") is True, "Home ended before producer", "FAIL")
        require(all(s.get("semanticContext", {}).get("nativeSceneID") in [None, native[label]] for s in homes),
                "conflicting mapper native scene", "FAIL")
    require(len(set(native.values())) == 2 and owners["a"]["view_id"] != owners["b"]["view_id"]
            and owners["a"]["session_id"] == owners["b"]["session_id"], "scene/view alias or split session", "FAIL")
    session_id = owners["a"]["session_id"]
    sessions = [s for s in signals if s.get("kind") == "rum-session-started"]
    require(len(sessions) == 1 and sessions[0].get("rumContext", {}).get("sessionID") == session_id
            and sessions[0].get("rumContext", {}).get("sessionDiscarded") is False, "one sampled session required")
    initial_a = owners["a"]
    retired = guard["process-a-retired"]
    exact(owner(retired), initial_a, "retired A owner")
    ended = [s for s in snapshots if owner(s) == initial_a and s["sequence"] < retired["sequence"]]
    require(ended and ended[-1].get("rumContext", {}).get("viewActive") is False,
            "initial A not retired before activation", "FAIL")
    request = guard["process-a-activation-requested"]
    restored = guard["process-a-activation-acknowledged"]
    for boundary in [request, restored]:
        exact(boundary.get("sourceContext"), dict(
            logicalSceneID="scene-A", nativeSceneID=native["scene-A"], screen="home"), "reactivation native identity")
    owners["a"] = owner(restored)
    require(owners["a"]["session_id"] == session_id
            and owners["a"]["view_id"] not in [initial_a["view_id"], owners["b"]["view_id"]],
            "restored A reused ended/peer owner or changed session", "FAIL")
    activations = [s for s in signals if s.get("kind") == "scene-lifecycle"
                   and s.get("semanticContext", {}).get("logicalSceneID") == "scene-A"
                   and s.get("semanticContext", {}).get("nativeSceneID") == native["scene-A"]
                   and s.get("activationState") == "foreground-active"
                   and s.get("evidenceSource") == "probe"
                   and request["sequence"] < s["sequence"] < restored["sequence"]]
    require(activations, "fresh native activation missing before owner acknowledgement", "FAIL")
    fresh = [s for s in snapshots if owner(s) == owners["a"]]
    require(fresh and request["sequence"] < fresh[0]["sequence"] < restored["sequence"]
            and fresh[0].get("rumContext", {}).get("viewActive") is True
            and fresh[0].get("semanticContext", {}).get("logicalSceneID") == "scene-A",
            "fresh active mapper missing before owner acknowledgement", "FAIL")
    require(all(s.get("semanticContext", {}).get("nativeSceneID") in [None, native["scene-A"]] for s in fresh),
            "fresh mapper native scene mismatch", "FAIL")
    kinds = ["rum-long-task", "rum-error", "rum-action"]
    events = [s for s in signals if s.get("kind") in kinds]
    exact({k: sum(s["kind"] == k for s in events) for k in kinds},
          {"rum-long-task": 2, "rum-error": 4, "rum-action": 1}, "extra or missing process events")
    require(not any(s.get("kind") in ["rum-resource", "rum-trace", "rum-log", "rum-operation"] for s in signals),
            "unexpected telemetry", "FAIL")
    ids = [s.get("eventID") for s in events]
    require(all(valid_uuid(v) for v in ids) and len(set(ids)) == 7, "duplicate or malformed event IDs", "FAIL")
    expected = dict(views=[], errors=[], long_tasks=[], actions=[])
    intervals = {}
    for suffix in ["b", "a"]:
        start = guard["process-" + suffix + "-representative"]
        ack = guard["process-" + suffix + "-signals-acknowledged"]
        exact(owner(start), owners[suffix], "wrong representative before stimulus")
        exact(owner(ack), owners[suffix], "representative changed after process signal")
        require(not start.get("rumContext", {}).get("actionIDs"), "active action at process boundary", "FAIL")
        offset = start.get("processSignal", {}).get("serverTimeOffsetMilliseconds")
        require(type(offset) in [int, float] and math.isfinite(offset), "missing actual clock offset")
        memory_boundary = guard["process-" + suffix + "-memory-boundary"]
        memory_ack = guard["process-" + suffix + "-memory-acknowledged"]
        began = guard["process-" + suffix + "-block-began"]
        ended = guard["process-" + suffix + "-block-ended"]
        begin_ms, end_ms = began["timestampMilliseconds"], ended["timestampMilliseconds"]
        require(1400 <= end_ms - begin_ms < 5000, "actual blocking interval differs", "FAIL")
        round_events = [s for s in events if s["kind"] != "rum-action"
                        and start["sequence"] < s["sequence"] < ack["sequence"]]
        require(len(round_events) == 3, "missing or delayed process acknowledgement", "FAIL")
        for kind, typ, category, key in [
            ("rum-long-task", None, None, "long_tasks"),
            ("rum-error", "AppHang", "App Hang", "errors"),
            ("rum-error", "MemoryWarning", "Memory Warning", "errors"),
        ]:
            event = unique([s for s in round_events if s["kind"] == kind
                            and (kind == "rum-long-task" or s.get("error", {}).get("type") == typ)], "producer event")
            exact(owner(event), owners[suffix], "process signal broadcast or wrong owner")
            observation = event.get("processSignal", {})
            exact({k: observation.get(k) for k in ["nativeSource", "originalRunID", "hasAction", "hasContainer"]},
                  dict(nativeSource="ios", originalRunID=run_id, hasAction=False, hasContainer=False),
                  "malformed process payload or stale origin")
            require(not event.get("rumContext", {}).get("actionIDs"), "invented process action", "FAIL")
            require(event.get("evidenceSource") == "rum-mapper", "process mapper source")
            date = event.get("rumContext", {}).get("eventDateMilliseconds")
            require(type(date) is int, "missing measured event date")
            local_date = date - offset
            duration = observation.get("durationNanoseconds")
            if typ == "MemoryWarning":
                require_before(memory_boundary, event, "memory notification boundary")
                require_before(event, memory_ack, "memory acknowledgement")
                require(duration is None and memory_boundary["timestampMilliseconds"] - 50 <= local_date
                        <= memory_ack["timestampMilliseconds"] + 50, "memory notification date/duration", "FAIL")
            else:
                require_before(began, event, "event predates main-thread block")
                require(type(duration) is int and 500_000_000 <= duration < 5_000_000_000,
                        "measured duration outside frozen threshold", "FAIL")
                event_end = local_date + duration / 1_000_000
                require(begin_ms - 600 <= local_date <= begin_ms + 600
                        and end_ms - 100 <= event_end <= end_ms + 600,
                        "producer duration not bound to actual block", "FAIL")
            row = dict(owners[suffix], event_id=event["eventID"], run_id=run_id, source="ios",
                       container_present=False, action_present=False, duration_ns=duration)
            if kind == "rum-error":
                error = event.get("error", {})
                exact({k: error.get(k) for k in ["id", "type", "category", "source", "isCrash"]},
                      dict(id=event["eventID"], type=typ, category=category, source="source", isCrash=False),
                      "process error category or fatality differs")
                row.update(error_type=typ, error_category=category, error_source="source",
                           error_source_type="ios", is_crash=False)
            expected[key].append(row)
        intervals[suffix] = dict(begin_ms=begin_ms, end_ms=end_ms, clock_offset_ms=offset)
    action = unique([s for s in events if s["kind"] == "rum-action"], "selection action")
    require_before(guard["process-selection-boundary"], action, "selection boundary")
    require_before(action, guard["process-selection-acknowledged"], "selection acknowledgement")
    exact(owner(action), owners["a"], "selection action owner")
    exact({k: action.get("action", {}).get(k) for k in ["id", "type", "target"]},
          dict(id=action["eventID"], type="custom", target="process-select-a"), "selection Action payload")
    require(action.get("evidenceSource") == "rum-mapper", "selection mapper source")
    expected["actions"] = [dict(owners["a"], event_id=action["eventID"], run_id=run_id,
                                source="ios", action_type="custom", action_target="process-select-a")]
    latest = {}
    for snapshot in snapshots:
        value = owner(snapshot)
        require(value["session_id"] == session_id, "unexpected view session", "FAIL")
        latest[value["view_id"]] = snapshot
    require(len(latest) == 4, "extra or missing view", "FAIL")
    require(sorted(s["rumContext"].get("viewName", "") for s in latest.values()) ==
            ["ApplicationLaunch", "ProbeHomeView", "ProbeHomeView", "ProbeHomeView"], "view inventory changed", "FAIL")
    for view_id, snapshot in latest.items():
        process = snapshot.get("processSignal", {})
        count = int(view_id in [c["view_id"] for c in owners.values()])
        counters = dict(viewLongTaskCount=count, viewErrorCount=2 * count,
                        viewActionCount=int(view_id == owners["a"]["view_id"]), viewResourceCount=0, viewCrashCount=0)
        exact({k: process.get(k) for k in counters}, counters, "broadcast or lost view counts")
        require(process.get("nativeSource") == "ios", "unexpected view source", "FAIL")
        require(process.get("originalRunID") == run_id or not count and process.get("originalRunID") is None,
                "stale Home run", "FAIL")
        require_before(snapshot, guard["process-inventory-verified"], "final count witness")
        expected["views"].append(dict(
            owner(snapshot), name=snapshot["rumContext"]["viewName"], run_id=process.get("originalRunID"),
            source="ios", view_long_task_count=count, view_error_count=2 * count,
            view_action_count=int(view_id == owners["a"]["view_id"]), view_resource_count=0, view_crash_count=0))
    return dict(assertions=46, signal_count=len(signals), session_id=session_id, owners=owners,
                native_scenes=native, initial_a=initial_a, intervals=intervals, **expected,
                simultaneous_visibility_claimed=False, real_memory_pressure_claimed=False,
                fatal_watchdog_termination_claimed=False)


def validate_views(local, rows, allow_pending=False, previous=None):
    require(isinstance(rows, list) and len(rows) == 4, "incomplete or extra backend views", "FAIL")
    require(len({r.get("view_id") for r in rows}) == 4, "duplicate backend views", "FAIL")
    pending = False
    for expected in local["views"]:
        row = unique([r for r in rows if r.get("view_id") == expected["view_id"]], "backend view identity")
        require(set(row) == PROJECT_KEYS, "malformed backend projection", "FAIL")
        prior = next((r for r in previous or [] if r.get("view_id") == expected["view_id"]), None)
        for field, value in expected.items():
            actual = row.get(field)
            counter = field.startswith("view_") and field.endswith("_count")
            optional = field in ["view_crash_count", "view_long_task_count"]
            if optional and actual is None and (value == 0 or allow_pending):
                actual = 0
            if allow_pending and counter:
                require(type(actual) is int and 0 <= actual <= value, "malformed or excessive view counter", "FAIL")
                if prior:
                    before = prior.get(field)
                    if optional and before is None:
                        before = 0
                    require(type(before) is int and actual >= before, "backend view counter regressed", "FAIL")
                pending |= actual != value
            else:
                exact(actual, value, "backend views/" + field + " differs")
    return pending


def settled_views(local, fetch, pause):
    previous = None
    for attempt in range(3):
        rows = fetch()
        if not validate_views(local, rows, allow_pending=True, previous=previous):
            validate_views(local, rows)
            return rows, attempt + 1
        previous = rows
        if attempt < 2:
            pause(10)
    require(False, "backend final view counters did not converge after three fresh reads", "FAIL")


def validate_backend(local, run_id, views, errors, tasks, actions, resources, crashes):
    require(resources == [] and type(crashes) is int and crashes == 0, "unexpected Resource/crash", "FAIL")
    validate_views(local, views)
    for kind, rows, count in [("errors", errors, 4), ("long_tasks", tasks, 2), ("actions", actions, 1)]:
        require(isinstance(rows, list) and len(rows) == count, "incomplete or extra backend " + kind, "FAIL")
        key = "view_id" if kind == "views" else "event_id"
        require(len({r.get(key) for r in rows}) == count, "duplicate backend " + kind, "FAIL")
        for expected in local[kind]:
            row = unique([r for r in rows if r.get(key) == expected[key]], "backend " + kind + " identity")
            require(set(row) == PROJECT_KEYS, "malformed backend projection", "FAIL")
            for field, value in expected.items():
                actual = row.get(field)
                if field in ["view_crash_count", "view_long_task_count"] and actual is None and value == 0:
                    actual = 0  # These optional zero counters are omitted by the SDK.
                exact(actual, value, "backend " + kind + "/" + field + " differs")
    require(all(row.get("run_id") == run_id for rows in [errors, tasks, actions] for row in rows),
            "backend restored origin", "FAIL")
    return dict(state="PASS", view_count=4, error_count=4, long_task_count=2, action_count=1,
                resource_count=0, crash_count=0, process_fallback_verified=True)
