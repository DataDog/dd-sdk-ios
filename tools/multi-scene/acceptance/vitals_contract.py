"""T13: actual shared readers remain associated with exact native view intervals."""
import json
import math
from pathlib import Path
from acceptance_common import canonical, require, require_before, require_identity, unique
from log_contract import valid_uuid

SCENARIO = "vitals.shared-process.cross-scene-serial"
CONTRACT = "vitals-scenario-contract.json"
MINIMUM_TESTS = 196
PHYSICAL_SCENARIO = "vitals.shared-process.single-scene-physical"
PHYSICAL_CONTRACT = "physical-vitals-scenario-contract.json"
PHYSICAL_GUARDS = [
    "vitals-configuration", "vitals-a-owner", "vitals-a-sampling-began",
    "vitals-a-samples-acknowledged", "vitals-stop-boundary",
    "vitals-final-a", "vitals-inventory-verified", "vitals-a-complete",
]
GUARDS = [
    "vitals-configuration", "vitals-a-owner", "vitals-a-sampling-began",
    "vitals-a-samples-acknowledged", "vitals-a-complete",
    "vitals-b-owner", "vitals-a-retired", "vitals-b-sampling-began",
    "vitals-b-samples-acknowledged", "vitals-stop-boundary",
    "vitals-final-a", "vitals-final-b", "vitals-inventory-verified", "vitals-b-complete",
]
ZERO = dict(actions=0, resources=0, errors=0, longTasks=0, crashes=0)
CONFIGURATION = {key: True for key in [
    "cpu", "memory", "refreshRate", "renderLoop", "slowFrames", "longTasksDisabled",
    "appHangsDisabled", "memoryWarningsDisabled", "timeseriesDefaultDisabled",
]}
METRICS = ["cpuTicks", "cpuRate", "memoryAverage", "memoryMax", "refreshRateAverage",
           "refreshRateMin", "timeSpentNanoseconds", "slowFrames", "slowFramesRate"]
FLOATS = set(METRICS) - {"timeSpentNanoseconds", "slowFrames"}
PROJECT_KEYS = {"run_id", "session_id", "view_id", "name", "source", "is_active",
                "container_present", "counters", "metrics", "slow_frames_present"}


def exact(actual, expected, label):
    require(canonical(actual) == canonical(expected), label, "FAIL")


def owner(signal):
    context = signal.get("rumContext", {})
    value = dict(session_id=context.get("sessionID"), view_id=context.get("viewID"))
    require(all(valid_uuid(v) for v in value.values()), "malformed vitals owner", "FAIL")
    return value


def close(actual, expected):
    return (type(actual) in [int, float] and type(expected) in [int, float]
            and math.isfinite(actual) and math.isfinite(expected)
            and abs(actual - expected) <= max(1e-6, abs(expected) * 1e-9))


def validate_metrics(value, complete=False):
    require(isinstance(value, dict) and set(value) == set(METRICS), "metric projection shape", "FAIL")
    time = value["timeSpentNanoseconds"]
    require(type(time) is int and time > 0, "invalid measured view interval", "FAIL")
    for field in FLOATS:
        number = value[field]
        require(number is None or type(number) in [int, float] and math.isfinite(number) and number >= 0,
                "nonfinite, negative or mistyped metric " + field, "FAIL")
    for low, high in [("memoryAverage", "memoryMax"), ("refreshRateMin", "refreshRateAverage")]:
        a, b = value[low], value[high]
        require((a is None) == (b is None), "partial sampled metric pair", "FAIL")
        require(a is None or 0 < a <= b, "invalid sampled metric range", "FAIL")
    cpu, rate = value["cpuTicks"], value["cpuRate"]
    if time <= 1_000_000_000:
        require(rate is None, "invented CPU rate for short view", "FAIL")
    elif cpu is not None:
        require(close(rate, cpu / (time / 1_000_000_000)), "CPU rate detached from view interval", "FAIL")
    else:
        require(rate is None, "CPU rate without samples", "FAIL")
    frames = value["slowFrames"]
    require(frames is None or isinstance(frames, list), "slow frame collection type", "FAIL")
    for frame in frames or []:
        require(isinstance(frame, dict) and set(frame) == {"start", "duration"}
                and type(frame["start"]) is int and type(frame["duration"]) is int
                and frame["duration"] > 0, "invalid actual slow frame", "FAIL")
    if complete:
        require(time > 1_000_000_000 and all(value[k] is not None and value[k] > 0 for k in
                ["cpuTicks", "cpuRate", "memoryAverage", "memoryMax", "refreshRateAverage", "refreshRateMin"]),
                "Home did not collect multiple actual samples", "FAIL")


def metrics(signal):
    value = {key: signal.get("vitals", {}).get(key) for key in METRICS}
    validate_metrics(value)
    return value


def validate_local(records, run_id):
    return _validate_local(records, run_id, single_scene=False)


def validate_physical_local(records, run_id):
    return _validate_local(records, run_id, single_scene=True)


def _validate_local(records, run_id, single_scene):
    scenario_id = PHYSICAL_SCENARIO if single_scene else SCENARIO
    contract_file = PHYSICAL_CONTRACT if single_scene else CONTRACT
    guards = PHYSICAL_GUARDS if single_scene else GUARDS
    phases = [("a", 2)] if single_scene else [("a", 2), ("b", 5)]
    expected_count = 17 if single_scene else 30
    manifest = unique([r["manifest"] for r in records if r["type"] == "manifest"], "manifest")
    require(manifest.get("runID") == run_id and manifest.get("runMode") == "clean"
            and not manifest.get("validationErrors"), "stale or invalid clean manifest")
    require_identity(manifest.get("scenario"), json.loads(Path(__file__).with_name(contract_file).read_text()),
                     "vitals fixture")
    signals = [r["signal"] for r in records if r["type"] == "signal"]
    require(signals and all(s.get("schemaVersion") == 5 and s.get("runID") == run_id
                           and s.get("scenarioID") == scenario_id for s in signals), "stale signal identity")
    require([s.get("sequence") for s in signals] == list(range(1, len(signals) + 1)), "signal sequence")
    require(all(type(s.get("timestampMilliseconds")) is int and s["timestampMilliseconds"] > 0
                for s in signals), "missing native clock")
    terminal = unique([r for r in records if r["type"] == "semantic-result"], "terminal")
    result = terminal.get("result", {})
    require(terminal.get("runID") == run_id and result.get("scenarioID") == scenario_id, "stale terminal")
    exact({k: result.get(k) for k in ["state", "matchedExpectationCount", "issues"]},
          dict(state="PASS", matchedExpectationCount=expected_count, issues=[]), "native oracle did not pass")
    assertions = [s for s in signals if s.get("kind") == "assertion"]
    exact([s.get("name") for s in assertions], guards, "missing, duplicate or late vitals guard")
    require(all(s.get("result") == "PASS" and s.get("evidenceSource") == "internal-hook"
                for s in assertions), "unacknowledged vitals guard", "FAIL")
    require(not any(s.get("result") == "FAIL" for s in signals), "failed native assertion", "FAIL")
    guard = {s["name"]: s for s in assertions}
    exact(guard["vitals-configuration"].get("vitals"),
          dict(configuration=CONFIGURATION, samplingInterval=0.1), "actual reader configuration differs")
    steps = [s for s in signals if s.get("kind") == "step-started"]
    expected_steps = ["wait-for-scene-ready", "wait-for-signal", "sample-shared-vitals"]
    if not single_scene:
        expected_steps += ["open-window", "wait-for-signal", "sample-shared-vitals"]
    exact([s.get("stepKind") for s in steps], expected_steps, "serialized sampling steps")
    require_before(steps[2], guard["vitals-configuration"], "configuration after phase A begins")
    if not single_scene:
        require_before(guard["vitals-a-complete"], steps[3], "A samples before opening B")
    else:
        require(len([s for s in signals if s.get("kind") == "scene-ready"]) == 1,
                "physical sample requires exactly one native readiness", "FAIL")
    snapshots = [s for s in signals if s.get("kind") == "rum-view-snapshot"]
    require(all(s.get("evidenceSource") == "rum-mapper" for s in snapshots), "view mapper source", "FAIL")
    require(not any(s.get("kind") in ["rum-action", "rum-resource", "rum-error", "rum-long-task",
                                    "rum-log", "rum-trace", "rum-operation"] for s in signals),
            "unexpected telemetry", "FAIL")
    owners, native = {}, {}
    for suffix, index in phases:
        label = "scene-" + suffix.upper()
        claimed = guard["vitals-" + suffix + "-owner"]
        owners[suffix] = owner(claimed)
        require_before(steps[index], claimed, "owner after exact scene step")
        ready = unique([s for s in signals if s.get("kind") == "scene-ready"
                        and s.get("semanticContext", {}).get("logicalSceneID") == label], "native readiness")
        native[label] = ready.get("semanticContext", {}).get("nativeSceneID")
        require(isinstance(native[label], str) and bool(native[label]), "missing native scene")
        exact(claimed.get("sourceContext"), dict(logicalSceneID=label, nativeSceneID=native[label], screen="home"),
              "SDK/native scene mismatch")
        require(ready.get("evidenceSource") == "probe" and ready.get("scenePhase") == "ready",
                "actual readiness missing")
        require_before(ready, steps[index], "readiness before sampling")
        if suffix == "b":
            require_before(steps[3], ready, "B readiness before open request")
        homes = [s for s in snapshots if s.get("semanticContext", {}).get("logicalSceneID") == label]
        require(homes and all(owner(s) == owners[suffix] for s in homes), "Home owner changed", "FAIL")
        require(all(s.get("semanticContext", {}).get("nativeSceneID") in [None, native[label]] for s in homes),
                "conflicting native mapper scene", "FAIL")
        before = [s for s in homes if s["sequence"] < claimed["sequence"]]
        require(before and before[-1].get("rumContext", {}).get("viewActive") is True,
                "independent active Home before owner assertion", "FAIL")
        began, ack = [guard["vitals-" + suffix + "-" + part] for part in ["sampling-began", "samples-acknowledged"]]
        exact(owner(began), owners[suffix], "sampling owner")
        exact(owner(ack), owners[suffix], "sample acknowledgement owner")
        samples = [s for s in homes if began["sequence"] < s["sequence"] < ack["sequence"]]
        require(samples and samples[-1].get("rumContext", {}).get("viewActive") is True,
                "no active samples before acknowledgement", "FAIL")
        validate_metrics(metrics(samples[-1]), complete=True)
    if not single_scene:
        require(len(set(native.values())) == 2 and owners["a"]["view_id"] != owners["b"]["view_id"]
                and owners["a"]["session_id"] == owners["b"]["session_id"], "scene/view alias or split session", "FAIL")
    else:
        require(all(s.get("semanticContext", {}).get("logicalSceneID") == "scene-A"
                    for s in snapshots if s.get("rumContext", {}).get("viewName") == "ProbeHomeView"),
                "unexpected physical Home scene", "FAIL")
    exact(owner(guard["vitals-stop-boundary"]), owners["a" if single_scene else "b"], "session stop owner")
    session_id = owners["a"]["session_id"]
    sessions = [s for s in signals if s.get("kind") == "rum-session-started"]
    require(len(sessions) == 1 and sessions[0].get("rumContext", {}).get("sessionID") == session_id
            and sessions[0].get("rumContext", {}).get("sessionDiscarded") is False, "one sampled session required")
    if not single_scene:
        retired = guard["vitals-a-retired"]
        exact(owner(retired), owners["a"], "retired A owner")
        ended_a = [s for s in snapshots if owner(s) == owners["a"] and s["sequence"] < retired["sequence"]]
        require(ended_a and ended_a[-1].get("rumContext", {}).get("viewActive") is False,
                "A still active before B samples", "FAIL")
        background = [s for s in signals if s.get("kind") == "scene-lifecycle"
                      and s.get("semanticContext", {}).get("nativeSceneID") == native["scene-A"]
                      and s.get("activationState") == "background" and s["sequence"] < retired["sequence"]]
        require(background, "actual serial scene topology missing before retirement", "FAIL")
    latest = {}
    for snapshot in snapshots:
        value = owner(snapshot)
        require(value["session_id"] == session_id, "unexpected view session", "FAIL")
        observed = snapshot.get("vitals", {})
        home = snapshot.get("rumContext", {}).get("viewName") == "ProbeHomeView"
        require(observed.get("nativeSource") == "ios" and
                (observed.get("originalRunID") == run_id or not home and observed.get("originalRunID") is None),
                "stale snapshot origin or source", "FAIL")
        exact(snapshot.get("rumContext", {}).get("viewTimeSpentNanoseconds"),
              observed.get("timeSpentNanoseconds"), "snapshot interval differs")
        exact(observed.get("counters"), ZERO, "unexpected view counts")
        metrics(snapshot)
        latest[value["view_id"]] = snapshot
    names = ["ApplicationLaunch"] + ["ProbeHomeView"] * len(phases)
    require(len(latest) == len(names) and sorted(s["rumContext"].get("viewName", "") for s in latest.values()) ==
            names, "complete final view inventory", "FAIL")
    final_views = []
    for snapshot in latest.values():
        context, observed = snapshot["rumContext"], snapshot["vitals"]
        require(context.get("viewActive") is False, "view did not end at final boundary", "FAIL")
        exact(context.get("viewTimeSpentNanoseconds"), observed.get("timeSpentNanoseconds"), "mapper interval differs")
        home = context["viewName"] == "ProbeHomeView"
        require(observed.get("nativeSource") == "ios" and
                (observed.get("originalRunID") == run_id or not home and observed.get("originalRunID") is None),
                "stale view origin or source", "FAIL")
        validate_metrics(metrics(snapshot), complete=home)
        require_before(snapshot, guard["vitals-inventory-verified"], "final mapper before inventory")
        final_views.append(dict(owner(snapshot), name=context["viewName"], run_id=observed.get("originalRunID"),
                                source="ios", is_active=False, container_present=False,
                                counters=ZERO, metrics=metrics(snapshot),
                                slow_frames_present=observed.get("slowFrames") is not None))
    for suffix, _ in phases:
        final = guard["vitals-final-" + suffix]
        snapshot = latest[owners[suffix]["view_id"]]
        exact(owner(final), owners[suffix], "final owner differs")
        exact(final.get("vitals"), snapshot.get("vitals"), "final assertion does not reflect actual mapper")
        require_before(snapshot, final, "final mapper before acknowledgement")
        if suffix == "b" or single_scene:
            require_before(guard["vitals-stop-boundary"], snapshot, "final sampled view ended before session stop")
    if not single_scene:
        exact(ended_a[-1]["vitals"], latest[owners["a"]["view_id"]]["vitals"], "ended A metrics mutated during B")
    return dict(assertions=expected_count, signal_count=len(signals), session_id=session_id, owners=owners,
                single_scene_physical_sample=single_scene,
                native_scenes=native, views=final_views, simultaneous_visibility_claimed=False,
                physical_device_claimed=False, timeseries_default_disabled=True)


def compare_metrics(actual, expected, slow_frames_present):
    validate_metrics(actual)
    for field in METRICS:
        a, e = actual[field], expected[field]
        if field == "slowFrames" and e == [] and a is None and not slow_frames_present:
            # Observed backend representation: an empty SDK array is omitted.
            # Keep the original projection and permit no other missing metric.
            continue
        if field in FLOATS and e is not None:
            require(close(a, e), "backend metric differs: " + field, "FAIL")
        else:
            exact(a, e, "backend metric presence/integer differs: " + field)


def validate_views(local, rows, allow_pending=False, previous=None):
    view_count = 2 if local.get("single_scene_physical_sample") is True else 3
    require(len(local["views"]) == view_count, "invalid local view inventory", "FAIL")
    require(isinstance(rows, list) and len(rows) == view_count, "incomplete or extra backend views", "FAIL")
    require(len({r.get("view_id") for r in rows}) == view_count, "duplicate backend views", "FAIL")
    pending = False
    for expected in local["views"]:
        row = unique([r for r in rows if r.get("view_id") == expected["view_id"]], "backend view identity")
        require(set(row) == PROJECT_KEYS, "malformed backend projection", "FAIL")
        for field in PROJECT_KEYS - {"metrics", "is_active", "slow_frames_present"}:
            exact(row[field], expected[field], "backend view differs: " + field)
        validate_metrics(row["metrics"])
        present = row["slow_frames_present"]
        require(type(present) is bool and present == (row["metrics"]["slowFrames"] is not None),
                "explicit null or inconsistent slow-frame presence", "FAIL")
        time, final_time = row["metrics"]["timeSpentNanoseconds"], expected["metrics"]["timeSpentNanoseconds"]
        require(type(row["is_active"]) is bool, "missing backend view activity", "FAIL")
        if allow_pending:
            require(time <= final_time, "backend view exceeds frozen final interval", "FAIL")
            prior = next((r for r in previous or [] if r.get("view_id") == row["view_id"]), None)
            if prior:
                require(time >= prior["metrics"]["timeSpentNanoseconds"], "backend interval regressed", "FAIL")
                require(not row["is_active"] or prior["is_active"], "backend view reactivated", "FAIL")
            if time < final_time or row["is_active"]:
                pending = True
                continue
        exact(row["is_active"], False, "backend final view remains active")
        compare_metrics(row["metrics"], expected["metrics"], row["slow_frames_present"])
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
    require(False, "backend final vitals did not converge after three fresh reads", "FAIL")


def validate_backend(local, views, actions, resources, tasks, errors, crashes):
    require(actions == [] and resources == [] and tasks == []
            and type(errors) is int and errors == 0 and type(crashes) is int and crashes == 0,
            "unexpected backend telemetry", "FAIL")
    validate_views(local, views)
    return dict(state="PASS", view_count=len(local["views"]), action_count=0, resource_count=0, long_task_count=0,
                error_count=0, crash_count=0, measured_vitals_verified=True, physical_device_claimed=False,
                omitted_empty_slow_frame_arrays=sum(
                    expected["metrics"]["slowFrames"] == [] and not row["slow_frames_present"]
                    for expected in local["views"] for row in views if row["view_id"] == expected["view_id"]))
