"""T11: exact exported/fatal context and real crash recovery across three processes."""
import json
import re
import uuid
from pathlib import Path
from acceptance_common import require, require_before, require_identity, unique

SCENARIO = "fatal.process-context.prepare-crash"
RECOVER = "fatal.process-context.recover"
CONSUMED = "fatal.process-context.verify-consumed"
SCENARIOS = [SCENARIO, RECOVER, CONSUMED]
CONTRACT = "fatal-scenario-contract.json"
MINIMUM_TESTS = 188
PREPARE_GUARDS = [
    "fatal-process", "fatal-owner-a", "fatal-owner-b", "fatal-export-before", "fatal-provider-before",
    "fatal-mutation-dispatched", "fatal-export-after", "fatal-provider-after",
    "fatal-capture-unchanged", "fatal-injection-drained", "fatal-prepare-complete",
]
RECOVERY_GUARDS = [
    "fatal-process", "fatal-recovery-current", "fatal-reporter-enable",
    "fatal-launch-report", "fatal-recovery-complete",
]


def valid_uuid(value):
    try:
        return isinstance(value, str) and str(uuid.UUID(value)) == value.lower()
    except (ValueError, AttributeError):
        return False


def owner(signal):
    context = signal.get("rumContext", {})
    require(valid_uuid(context.get("sessionID")) and valid_uuid(context.get("viewID")),
            "missing actual RUM identity", "FAIL")
    return dict(session_id=context["sessionID"], view_id=context["viewID"], name=context.get("viewName"))


def assertion(signals, name):
    signal = unique([s for s in signals if s.get("kind") == "assertion" and s.get("name") == name], name)
    require(signal.get("result") == "PASS", "non-passing guard " + name, "FAIL")
    return signal


def phase_records(phase, scenario):
    records, run_id = phase["records"], phase["run_id"]
    manifest = unique([r["manifest"] for r in records if r["type"] == "manifest"], "phase manifest")
    require(manifest.get("runID") == run_id and manifest.get("runMode") == "clean"
            and not manifest.get("validationErrors"), "stale or invalid phase manifest")
    contract = json.loads(Path(__file__).with_name(CONTRACT).read_text())[scenario]
    require_identity(manifest.get("scenario"), contract, "fatal phase contract")
    signals = [r["signal"] for r in records if r["type"] == "signal"]
    require(signals and all(s.get("runID") == run_id and s.get("scenarioID") == scenario
                           and s.get("schemaVersion") == 5 for s in signals), "stale phase signals")
    require(all(a["sequence"] < b["sequence"] for a, b in zip(signals, signals[1:])),
            "phase sequence is not strictly increasing")
    require(not any(s.get("kind") == "assertion" and s.get("result") != "PASS" for s in signals),
            "failed or unacknowledged native guard", "FAIL")
    require(not any(s.get("kind") in ["rum-action", "rum-resource", "rum-log", "rum-trace", "rum-operation"]
                    for s in signals), "unexpected local telemetry", "FAIL")
    terminal = unique([r for r in records if r["type"] == "semantic-result"], "phase terminal")
    result = terminal.get("result", {})
    require(terminal.get("runID") == run_id and result.get("scenarioID") == scenario, "stale terminal")
    require(result.get("state") == "PASS" and not result.get("issues")
            and result.get("matchedExpectationCount") == (24 if scenario == SCENARIO else 10),
            "phase terminal did not satisfy its frozen expectations", "FAIL")
    names = PREPARE_GUARDS if scenario == SCENARIO else RECOVERY_GUARDS
    guards = [assertion(signals, name) for name in names]
    for a, b in zip(guards, guards[1:]):
        require_before(a, b, "fatal guard")
    last_record = unique([r for r in records if r.get("signal") == guards[-1]], "completed phase record")
    require(records.index(last_record) < records.index(terminal), "guards completed after terminal", "FAIL")
    pid = guards[0].get("fatal", {}).get("processID")
    require(type(pid) is int and pid > 0, "missing real process identity")
    require(all(s["fatal"].get("processID") == pid for s in signals if "fatal" in s),
            "foreign process observation", "FAIL")
    require(phase.get("process_id") == pid, "launcher and native process identity differ", "FAIL")
    snapshots = [s for s in signals if s.get("kind") == "rum-view-snapshot"]
    require(snapshots and all(s.get("evidenceSource") == "rum-mapper" for s in snapshots),
            "view ownership is not independent mapper evidence", "FAIL")
    return signals, snapshots, terminal, pid


def validate_crash_boundary(phase, signals, terminal):
    # simctl can finish successfully when the launched app crashes. Its exit code
    # proves launcher completion only; the recovered report classifies the crash.
    require(phase.get("terminated") is True and type(phase.get("launcher_exit")) is int,
            "fixture process disappearance or launcher completion unconfirmed", "FAIL")
    boundary = assertion(signals, "fatal-crash-boundary")
    boundary_record = unique([r for r in phase["records"] if r.get("signal") == boundary], "crash boundary")
    require(phase["records"].index(terminal) < phase["records"].index(boundary_record),
            "termination boundary occurred before preparation PASS", "FAIL")
    require(boundary["sequence"] == signals[-1]["sequence"], "unexpected work after crash boundary", "FAIL")
    return boundary


def validate_local(phases, run_id):
    require(len(phases) == 3 and [p["scenario_id"] for p in phases] == SCENARIOS, "three ordered phases required")
    run_ids = [p["run_id"] for p in phases]
    require(run_ids[0] == run_id and len(set(run_ids)) == 3 and all(run_ids), "reused phase/run identity")
    binary = phases[0].get("installed_binary_sha256")
    container = phases[0].get("data_container")
    require(isinstance(binary, str) and re.fullmatch(r"[a-f0-9]{64}", binary) and container,
            "missing installed identity")
    require(all(p.get("installed_binary_sha256") == binary and p.get("data_container") == container for p in phases),
            "installation changed between phases")
    observed = [phase_records(p, scenario) for p, scenario in zip(phases, SCENARIOS)]
    require(len({o[3] for o in observed}) == 3, "process reused across phases", "FAIL")
    signals, snapshots, terminal, crashed_pid = observed[0]
    boundary = validate_crash_boundary(phases[0], signals, terminal)
    a, b = assertion(signals, "fatal-owner-a"), assertion(signals, "fatal-owner-b")
    owner_a, owner_b = owner(a), owner(b)
    require(owner_a["session_id"] == owner_b["session_id"] and owner_a["view_id"] != owner_b["view_id"],
            "peer identity conflation", "FAIL")
    native = [x.get("sourceContext", {}).get("nativeSceneID") for x in [a, b]]
    require(all(native) and len(set(native)) == 2, "two actual native scenes required", "FAIL")
    for record, label in [(a, "scene-A"), (b, "scene-B")]:
        original = unique([s for s in snapshots if owner(s) == owner(record)
                           and s.get("rumContext", {}).get("viewActive") is True
                           and s.get("fatal", {}).get("documentVersion") == 1], "initial Home mapper")
        require(original.get("semanticContext", {}).get("logicalSceneID") == label
                and original.get("semanticContext", {}).get("nativeSceneID")
                == record.get("sourceContext", {}).get("nativeSceneID"),
                "call-site label substituted for native mapper owner", "FAIL")
        require_before(original, record, "independent Home capture")
    for name in ["fatal-export-before", "fatal-provider-before", "fatal-export-after",
                 "fatal-provider-after", "fatal-injection-drained", "fatal-crash-boundary"]:
        guard = assertion(signals, name)
        require(owner(guard) == owner_b and guard.get("evidenceSource") == "internal-hook",
                "representative export/provider changed to peer", "FAIL")
    require(owner(assertion(signals, "fatal-capture-unchanged")) == owner_a, "retained snapshot drift", "FAIL")
    mutation = assertion(signals, "fatal-mutation-dispatched")
    witness = [s for s in snapshots if owner(s) == owner_a and s.get("fatal", {}).get("peerMutation") == "A"
               and type(s.get("fatal", {}).get("mutationTiming")) is int and s["fatal"]["mutationTiming"] > 0]
    require(witness, "peer attribute update lacks independent mapper witness", "FAIL")
    require_before(mutation, witness[0], "peer mutation")
    require_before(witness[0], assertion(signals, "fatal-export-after"), "post-mutation export")
    injected = assertion(signals, "fatal-injection-drained")["fatal"]
    require(type(injected.get("documentVersion")) is int and injected.get("viewErrorCount") == 0
            and injected.get("viewCrashCount") == 0, "injected view already contains a fatal event", "FAIL")
    require(not any(s.get("kind") == "rum-error" for s in signals), "error before declared crash", "FAIL")

    inventory = {}
    sessions = []
    recovery_current = []
    fatal = None
    for index, (phase_signals, phase_views, _, pid) in enumerate(observed):
        session_signals = [s for s in phase_signals if s.get("kind") == "rum-session-started"]
        session = unique(session_signals, "one new session per process").get("rumContext", {})
        sid = session.get("sessionID")
        require(valid_uuid(sid) and session.get("sessionDiscarded") is False, "missing sampled phase session", "FAIL")
        sessions.append(sid)
        fresh = {owner(s)["view_id"]: owner(s) for s in phase_views if owner(s)["session_id"] == sid}
        names = sorted(v["name"] or "" for v in fresh.values())
        require(names == (["ApplicationLaunch", "ProbeHomeView", "ProbeHomeView"] if index == 0
                          else ["ApplicationLaunch", "FatalRecovery"]), "unexpected fresh native view inventory", "FAIL")
        for vid, value in fresh.items():
            require(vid not in inventory, "view identity reused across process", "FAIL")
            inventory[vid] = value
        for snapshot in phase_views:
            actual = owner(snapshot)
            is_recovered = index == 1 and actual == owner_b
            require(actual["session_id"] == sid or is_recovered, "foreign restored view", "FAIL")
            state = snapshot.get("fatal", {})
            expected = 1 if is_recovered else 0
            require(state.get("viewErrorCount") == expected and state.get("viewCrashCount") == expected,
                    "local fatal counts assigned to wrong owner", "FAIL")
        if index == 0:
            require(sid == owner_b["session_id"], "original session mismatch", "FAIL")
            continue
        current = assertion(phase_signals, "fatal-recovery-current")
        current_owner = owner(current)
        recovery_current.append(current_owner)
        require(current_owner["session_id"] == sid and current_owner["name"] == "FatalRecovery"
                and current_owner["view_id"] in fresh, "recovery current view not independently observed", "FAIL")
        first_current = next(s for s in phase_views if owner(s) == current_owner)
        require_before(first_current, current, "current recovery mapper")
        launch = assertion(phase_signals, "fatal-launch-report")
        require(launch.get("fatal", {}).get("launchDidCrash") is (index == 1),
                "missing/contradictory actual launch acknowledgement", "FAIL")
        errors = [s for s in phase_signals if s.get("kind") == "rum-error"]
        require(len(errors) == (1 if index == 1 else 0), "missing or duplicate fatal mapper", "FAIL")
        if index == 1:
            error = errors[0]
            payload = assertion(phase_signals, "fatal-error-payload")
            require_before(assertion(phase_signals, "fatal-reporter-enable"), payload, "report decoded before current context")
            require_before(error, assertion(phase_signals, "fatal-recovery-complete"), "fatal mapper")
            require(owner(error) == owner_b and owner(payload) == owner_b, "recovery substituted current owner", "FAIL")
            data = payload.get("fatal", {})
            require(data.get("originalRunID") == run_id and data.get("nativeSource") == "ios"
                    and data.get("exceptionType") == "SIGABRT" and valid_uuid(data.get("incidentIdentifier"))
                    and data.get("hasAction") is False and data.get("hasContainer") is False,
                    "invalid recovered fatal payload", "FAIL")
            require(str(data.get("crashedProcess", "")).endswith("[" + str(crashed_pid) + "]"),
                    "report is from another process", "FAIL")
            details = error.get("error", {})
            require(details.get("isCrash") is True and details.get("source") == "source"
                    and str(details.get("type", "")).startswith("SIGABRT ("),
                    "not the declared native crash", "FAIL")
            eid = error.get("eventID")
            require(valid_uuid(eid) and payload.get("eventID") == eid, "fatal mapper identity mismatch", "FAIL")
            crash_time = error.get("rumContext", {}).get("eventDateMilliseconds")
            require(type(crash_time) is int and abs(crash_time - boundary["timestampMilliseconds"]) <= 5000,
                    "crash timestamp outside declared boundary", "FAIL")
            recovered = unique([s for s in phase_views if owner(s) == owner_b], "recovered original view update")
            require(recovered.get("rumContext", {}).get("viewActive") is False
                    and recovered.get("rumContext", {}).get("viewDocumentVersion") == injected["documentVersion"] + 1,
                    "recovery did not update the injected view revision exactly once", "FAIL")
            fatal = dict(owner_b, event_id=eid, incident_id=data["incidentIdentifier"],
                         exception_type=data["exceptionType"], error_type=details["type"], crashed_process=data["crashedProcess"],
                         document_version=injected["documentVersion"] + 1, event_date=crash_time)
    require(len(set(sessions)) == 3 and len(inventory) == 7, "session/view inventory incomplete", "FAIL")
    return dict(state="PASS", session_ids=sessions, view_inventory=list(inventory.values()), run_ids=run_ids,
                original_a=owner_a, original_b=owner_b, recovery_current=recovery_current, fatal=fatal,
                process_ids=[o[3] for o in observed], view_count=7, fatal_count=1, native_expectations=44,
                signal_count=sum(len(o[0]) for o in observed))


def validate_backend(local, run_id, views, errors, actions, resources, crash_count):
    require(len(views) == 7 and len(errors) == 1 and not actions and not resources,
            "complete backend inventory differs", "FAIL")
    require(crash_count == 2, "expected one fatal error and one crashed view", "FAIL")
    expected = {v["view_id"]: v for v in local["view_inventory"]}
    require(len({v.get("view_id") for v in views}) == 7, "duplicate/missing backend view", "FAIL")
    for view in views:
        actual = {key: view.get(key) for key in ["view_id", "session_id", "name"]}
        require(actual == expected.get(view.get("view_id")), "backend view owner drift", "FAIL")
        require(view.get("source") == "ios" and view.get("container_present") is False,
                "invalid native backend view source/container", "FAIL")
        count = 1 if view["view_id"] == local["original_b"]["view_id"] else 0
        require(view.get("error_count") == count and view.get("crash_count") == count
                and view.get("action_count") == 0 and view.get("resource_count") == 0,
                "backend counts assigned to wrong owner", "FAIL")
        if count:
            require(view.get("is_active") is False and view.get("document_version") == local["fatal"]["document_version"],
                    "backend fatal view revision differs", "FAIL")
        if view.get("name") == "FatalRecovery":
            index = local["session_ids"].index(view["session_id"])
            require(view.get("run_id") == local["run_ids"][index], "restored recovery run identifier", "FAIL")
    error = errors[0]
    original = local["fatal"]
    for field in ["session_id", "view_id", "event_id", "incident_id", "exception_type", "error_type", "crashed_process"]:
        require(error.get(field) == original[field], "backend fatal mismatch: " + field, "FAIL")
    require(error.get("run_id") == run_id and error.get("source") == "ios"
            and error.get("error_source") == "source" and error.get("is_crash") is True
            and error.get("container_present") is False and error.get("action_present") is False,
            "backend fatal context/source drift", "FAIL")
    require(error.get("phase") == "fatal-original", "backend lost original fatal phase", "FAIL")
    return dict(state="PASS", sessions=3, views=7, fatal_errors=1, actions=0, resources=0,
                consumed_report_acknowledged=True)
