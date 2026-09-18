"""T07: explicit flags and captured internal metrics with exact typed ownership."""
import json
import math
from pathlib import Path
from acceptance_common import canonical, require, require_before, require_identity, unique

SCENARIO = "flags.explicit-target.internal-mutations-cross-scene-serial"
CONTRACT = "flag-scenario-contract.json"
CHECKPOINTS = ["initial", "swift-boolean", "swift-integer", "objc-string",
               "objc-nested", "internal-a", "internal-b", "final"]
PHASES = ["flag-" + phase + "-" + scene for phase in CHECKPOINTS for scene in ["a", "b"]]
SHARED, FINAL_A, FINAL_B = "exp180_shared", "exp180_final_a", "exp180_final_b"


def normalized_flags(flags):
    require(isinstance(flags, dict) and set(flags) <= {SHARED, FINAL_A, FINAL_B}, "malformed/foreign flags", "FAIL")
    for value in flags.values():
        valid = type(value) in (bool, int, str)
        if isinstance(value, dict):
            valid = (set(value) == {"enabled", "weights"} and type(value["enabled"]) is bool
                     and isinstance(value["weights"], list) and all(type(v) is int for v in value["weights"]))
        require(valid, "flag value type differs", "FAIL")
    return flags


def normalized_state(state):
    require(isinstance(state, dict) and set(state) <= {"flags", "build", "fbc", "leakedInternalAttribute"},
            "missing/malformed flag state", "FAIL")
    flags = normalized_flags(state.get("flags"))
    require(state.get("leakedInternalAttribute") is False, "internal attribute leaked or not checked", "FAIL")
    build, fbc = state.get("build"), state.get("fbc")
    if build is not None:
        require(isinstance(build, dict) and set(build) == {"min", "max", "average"} and
                all(type(v) in (int, float) and math.isfinite(v) and v > 0 for v in build.values()),
                "build sample type/value differs", "FAIL")
        build = {k: float(v) for k, v in build.items()}
    require(fbc is None or type(fbc) is int and fbc > 0, "FBC type/value differs", "FAIL")
    return dict(flags=flags, build=build, fbc=fbc, leakedInternalAttribute=False)


def validate_checkpoint(state, previous, index):
    checkpoint, is_a = index // 2, index % 2 == 0
    flags = {}
    if is_a and checkpoint >= 1:
        flags[SHARED] = True if checkpoint == 1 else 7
    if not is_a and checkpoint >= 3:
        flags[SHARED] = "B" if checkpoint == 3 else {"enabled": False, "weights": [2, 4]}
    if checkpoint == 7:
        flags[FINAL_A if is_a else FINAL_B] = "A-final" if is_a else "B-final"
    build, fbc = None, None
    if checkpoint >= (5 if is_a else 6):
        build = dict(min=32.0, max=52.0, average=42.0) if is_a else dict(min=20.0, max=60.0, average=40.0)
        fbc = 101 if is_a else 202
    expected = dict(flags=flags, build=build, fbc=fbc, leakedInternalAttribute=False)
    require(canonical(state) == canonical(expected), "flag/internal state or peer invariance differs", "FAIL")

def validate_local(records, run_id):
    manifest = unique([r["manifest"] for r in records if r["type"] == "manifest"], "manifest")
    require(manifest.get("runID") == run_id and manifest.get("runMode") == "clean" and
            not manifest.get("validationErrors"), "stale or invalid clean manifest")
    scenario = manifest.get("scenario", {})
    opened = set()
    for step in scenario.get("steps", []):
        if step.get("kind") == "open-window":
            opened.add(step.get("value"))
        if step.get("kind") == "wait-for-scene-ready":
            require(step.get("scene") not in opened, "readiness consumed twice")
    require_identity(scenario, json.loads(Path(__file__).with_name(CONTRACT).read_text()), "flag fixture")
    signals = [r["signal"] for r in records if r["type"] == "signal"]
    require(signals and all(s.get("schemaVersion") == 5 and s.get("runID") == run_id and
                           s.get("scenarioID") == SCENARIO for s in signals), "stale signal identity")
    require([s["sequence"] for s in signals] == list(range(1, len(signals) + 1)), "signal sequence")
    terminal = unique([r for r in records if r["type"] == "semantic-result"], "terminal")
    result = terminal.get("result", {})
    require(terminal.get("runID") == run_id and result.get("scenarioID") == SCENARIO, "stale terminal")
    require(result.get("state") == "PASS" and result.get("matchedExpectationCount") == 34 and
            result.get("issues") == [], "app oracle did not pass", "FAIL")
    require(not any(s.get("result") == "FAIL" for s in signals), "failed native assertion", "FAIL")
    batch = unique([s for s in signals if s.get("kind") == "step-started" and
                    s.get("stepKind") == "run-view-flag-batch"], "flag batch")

    def assertion(name):
        signal = unique([s for s in signals if s.get("kind") == "assertion" and s.get("name") == name], name)
        require(signal.get("result") == "PASS", "assertion failed: " + name, "FAIL")
        return signal

    boundary = assertion("flag-call-boundary")
    enqueued = assertion("flag-calls-enqueued")
    verified = assertion("flag-local-owners-verified")
    completed = assertion("flag-batch-finished")
    for earlier, later in [(batch, boundary), (boundary, enqueued), (enqueued, verified), (verified, completed)]:
        require_before(earlier, later, "flag critical boundary")
    snapshots = [s for s in signals if s.get("kind") == "rum-view-snapshot" and s.get("evidenceSource") == "rum-mapper"]
    owners, native = {}, {}
    for scene, suffix in [("scene-A", "a"), ("scene-B", "b")]:
        ready = [s for s in signals if s.get("kind") == "scene-ready" and
                 s.get("semanticContext", {}).get("logicalSceneID") == scene]
        require(ready, "missing native readiness")
        require_before(ready[0], batch, "native readiness")
        native[scene] = ready[0]["semanticContext"].get("nativeSceneID")
        claimed = assertion("flag-owner-" + suffix)
        require_before(batch, claimed, "owner guard")
        require_before(claimed, boundary, "owner guard")
        homes = [s for s in snapshots if s.get("semanticContext", {}).get("logicalSceneID") == scene and
                 s.get("semanticContext", {}).get("screen") == "home" and s["sequence"] < boundary["sequence"]]
        require(homes, "missing mapper Home")
        require(len({s["rumContext"].get("viewID") for s in homes}) == 1, "Home occurrence changed", "FAIL")
        owner = homes[-1].get("rumContext", {})
        require(owner.get("viewActive") is True, "requested owner ended before calls", "INCONCLUSIVE")
        require(claimed.get("evidenceSource") == "internal-hook" and
                all(claimed.get("rumContext", {}).get(k) == owner.get(k) for k in ["viewID", "sessionID"]),
                "claimed owner differs from independent mapper", "FAIL")
        owners[scene] = owner
    require(all(native.values()) and len(set(native.values())) == 2, "native scenes alias", "FAIL")
    require(owners["scene-A"].get("viewID") and owners["scene-B"].get("viewID") and
            owners["scene-A"]["viewID"] != owners["scene-B"]["viewID"], "view owners alias", "FAIL")
    sid = owners["scene-A"].get("sessionID")
    require(sid and sid == owners["scene-B"].get("sessionID"), "session ownership", "FAIL")
    require(not any(s.get("kind") == "rum-resource" for s in signals), "unexpected Resource event", "FAIL")
    events = [s for s in signals if s.get("kind") == "rum-error"]
    require(len(events) == 16, "complete error inventory differs", "FAIL")
    expected_errors, ordered_errors = [], []
    states, versions = {}, {}
    for index, phase in enumerate(PHASES):
        event = unique([e for e in events if e.get("name") == phase], phase)
        require(event.get("evidenceSource") == "rum-mapper", "non-mapper error")
        require_before(boundary, event, "marker boundary")
        require_before(event, verified, "marker verification")
        check = assertion("flag-payload-" + phase)
        require_before(boundary, check, "payload check")
        require_before(check, event, "payload check before mapper record")
        owner = owners["scene-A" if index % 2 == 0 else "scene-B"]
        context, payload = event.get("rumContext", {}), event.get("error", {})
        require(context.get("viewID") == owner["viewID"] and context.get("sessionID") == sid,
                "wrong marker owner: " + phase, "FAIL")
        require(check.get("evidenceSource") == "rum-mapper" and check.get("eventID") == payload.get("id") and
                check.get("rumContext", {}).get("viewID") == owner["viewID"] and
                check.get("rumContext", {}).get("sessionID") == sid, "unbound flag snapshot", "FAIL")
        prior = [s for s in snapshots if s.get("rumContext", {}).get("viewID") == owner["viewID"] and
                 s["sequence"] < check["sequence"]]
        require(prior, "missing preceding view snapshot", "FAIL")
        snapshot = prior[-1]
        require(check.get("acknowledgedSignalSequence") == snapshot["sequence"], "detached or stale view snapshot", "FAIL")
        require(snapshot.get("rumContext", {}).get("sessionID") == sid and
                snapshot.get("rumContext", {}).get("viewActive") is True, "ended snapshot at marker", "FAIL")
        version = snapshot.get("rumContext", {}).get("viewDocumentVersion")
        require(type(version) is int and version > 0 and
                check.get("rumContext", {}).get("viewDocumentVersion") == version, "wrong document version binding", "FAIL")
        state = normalized_state(check.get("flagState"))
        require(canonical(state) == canonical(normalized_state(snapshot.get("flagState"))),
                "marker state differs from independent view mapper", "FAIL")
        view_id = owner["viewID"]
        require(version >= versions.get(view_id, 0), "view document version regressed", "FAIL")
        validate_checkpoint(state, states.get(view_id), index)
        states[view_id], versions[view_id] = state, version
        require(event.get("sourceContext", {}).get("logicalSceneID") == "scene-A", "wrong source marker", "FAIL")
        require(payload.get("id") and payload.get("source") == "custom" and payload.get("type") == "ProbeFlag" and
                payload.get("isCrash") is not True and payload.get("resourceURL") is None,
                "wrong synthetic marker payload", "FAIL")
        expected_errors.append(dict(phase=phase, event_id=payload["id"], view_id=owner["viewID"], session_id=sid,
                                    source_scene="scene-A", error_source="custom", error_type="ProbeFlag",
                                    payload_matches=True, flags=state["flags"], leaked_internal_attribute=False))
        ordered_errors.append(event)
    for earlier, later in zip(ordered_errors, ordered_errors[1:]):
        require_before(earlier, later, "paired checkpoint order")
    require(len({e["event_id"] for e in expected_errors}) == 16, "duplicate error IDs", "FAIL")
    inventory = {}
    for snapshot in snapshots:
        context = snapshot.get("rumContext", {})
        require(context.get("sessionID") == sid and context.get("viewID"), "unexpected view/session", "FAIL")
        value = dict(view_id=context["viewID"], session_id=sid, name=context.get("viewName"),
                     flag_state=normalized_state(snapshot.get("flagState")))
        if context["viewID"] in inventory:
            require(all(inventory[context["viewID"]][k] == value[k] for k in ["view_id", "session_id", "name"]),
                    "mutated view identity", "FAIL")
        inventory[context["viewID"]] = value
    require(sorted(v["name"] or "" for v in inventory.values()) == ["ApplicationLaunch", "ProbeHomeView", "ProbeHomeView"],
            "complete local view inventory differs", "FAIL")
    for view_id, state in states.items():
        require(inventory[view_id]["flag_state"] == state, "final view changed after final marker", "FAIL")
    return dict(final_document_versions=versions, assertions=34, checkpoints=8, session_id=sid, native_scenes=native,
                owners={s: c["viewID"] for s, c in owners.items()}, views=list(inventory.values()),
                errors=expected_errors, signal_count=len(signals), simultaneous_visibility_claimed=False)


def validate_backend(local, run_id, resources, errors, views, crashes):
    require(crashes == 0 and len(resources) == 0, "backend crashes or unexpected Resources", "FAIL")
    require(len(errors) == 16 and len(views) == 3, "complete backend inventory differs", "FAIL")
    require(len({v.get("view_id") for v in views}) == 3 and len({e.get("event_id") for e in errors}) == 16,
            "duplicate backend event IDs", "FAIL")
    for kind, rows, key in [("views", views, "view_id"), ("errors", errors, "phase")]:
        for expected in local[kind]:
            row = unique([r for r in rows if r.get(key) == expected[key]], "backend " + kind)
            row = dict(row)
            if kind == "views":
                row["flag_state"] = normalized_state(row.get("flag_state"))
                # FBC is Flutter-only downstream. This native fixture proves its
                # captured ownership locally and in encoded payloads, not ingestion.
                expected = dict(expected, flag_state=dict(expected["flag_state"], fbc=None))
            else:
                row["flags"] = normalized_flags(row.get("flags"))
                require(row.get("leaked_internal_attribute") is False, "backend internal attribute leak", "FAIL")
            require(row.get("run_id") == run_id, "restored/stale backend run hidden", "FAIL")
            require(all(canonical(row.get(k)) == canonical(v) for k, v in expected.items()),
                    "backend fields differ: " + kind, "FAIL")
            if kind == "errors":
                require(row.get("is_crash") is not True, "backend error is a crash", "FAIL")
    return dict(state="PASS", error_count=16, resource_count=0, view_count=3, checkpoints=8, crash_count=0,
                fbc_contract="native backend absence; exact ownership verified locally and in encoding")
