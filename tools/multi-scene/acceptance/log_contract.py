"""T09: six logs and three mirrors retain exact emission view/action ownership."""
import json
import uuid
from pathlib import Path
from acceptance_common import canonical, require, require_before, require_identity, unique

SCENARIO = "logs.captured-emission.native-mirrors-cross-scene-serial"
CONTRACT = "log-scenario-contract.json"
PHASES = ["log-info-a", "log-error-a", "log-info-b", "log-error-b", "log-info-fallback", "log-error-fallback"]
ERRORS = [phase for phase in PHASES if phase.startswith("log-error-")]
ACTIONS = ["log-action-a", "log-action-b"]
INVENTORY = ["log-info-a", "log-error-a", "mirror-log-error-a", "log-info-b", "log-error-b",
             "mirror-log-error-b", "log-info-fallback", "log-error-fallback",
             "mirror-log-error-fallback", *ACTIONS]
SERVICE = "ios-sdk-native-multi-scene-probe"


def source(phase):
    return "scene-A" if phase.endswith("-a") else "scene-B" if phase.endswith("-b") else "source-less"


def valid_uuid(value):
    try:
        return isinstance(value, str) and str(uuid.UUID(value)) == value.lower()
    except (ValueError, AttributeError):
        return False


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
    require_identity(scenario, json.loads(Path(__file__).with_name(CONTRACT).read_text()), "Log fixture")
    signals = [r["signal"] for r in records if r["type"] == "signal"]
    require(signals and all(s.get("schemaVersion") == 5 and s.get("runID") == run_id and
                           s.get("scenarioID") == SCENARIO for s in signals), "stale signal identity")
    require([s["sequence"] for s in signals] == list(range(1, len(signals) + 1)), "signal sequence")
    terminal = unique([r for r in records if r["type"] == "semantic-result"], "terminal")
    result = terminal.get("result", {})
    require(terminal.get("runID") == run_id and result.get("scenarioID") == SCENARIO, "stale terminal")
    require(result.get("state") == "PASS" and result.get("matchedExpectationCount") == 24 and
            result.get("issues") == [], "app oracle did not pass", "FAIL")
    require(not any(s.get("result") == "FAIL" for s in signals), "failed native assertion", "FAIL")

    def assertion(name):
        s = unique([s for s in signals if s.get("kind") == "assertion" and s.get("name") == name], name)
        require(s.get("result") == "PASS", "assertion failed: " + name, "FAIL")
        return s

    batch = unique([s for s in signals if s.get("kind") == "step-started" and
                    s.get("stepKind") == "run-log-ownership-batch"], "Log batch")
    action_boundary = assertion("log-actions-boundary")
    boundary = assertion("log-call-boundary")
    stops = assertion("log-stops-boundary")
    verified = assertion("log-local-owners-verified")
    completed = assertion("log-batch-finished")
    ordered = [batch, action_boundary, boundary, stops, verified, completed]
    for a, b in zip(ordered, ordered[1:]):
        require_before(a, b, "Log critical boundary")

    snapshots = [s for s in signals if s.get("kind") == "rum-view-snapshot" and s.get("evidenceSource") == "rum-mapper"]
    owners, native = {}, {}
    for scene, suffix in [("scene-A", "a"), ("scene-B", "b")]:
        ready = [s for s in signals if s.get("kind") == "scene-ready" and
                 s.get("semanticContext", {}).get("logicalSceneID") == scene]
        require(ready, "missing native readiness")
        require_before(ready[0], batch, "native readiness")
        native[scene] = ready[0]["semanticContext"].get("nativeSceneID")
        claimed = assertion("log-owner-" + suffix)
        require_before(action_boundary, claimed, "live action guard")
        require_before(claimed, boundary, "owner guard")
        homes = [s for s in snapshots if s.get("semanticContext", {}).get("logicalSceneID") == scene and
                 s.get("semanticContext", {}).get("screen") == "home" and s["sequence"] < boundary["sequence"]]
        require(homes, "missing independent mapper Home")
        require(len({s["rumContext"].get("viewID") for s in homes}) == 1, "Home occurrence changed", "FAIL")
        home = homes[-1].get("rumContext", {})
        require(home.get("viewActive") is True, "owner ended before logging", "INCONCLUSIVE")
        owner = claimed.get("rumContext", {})
        require(claimed.get("evidenceSource") == "internal-hook" and
                all(owner.get(k) == home.get(k) for k in ["viewID", "sessionID"]),
                "claimed owner differs from independent mapper", "FAIL")
        require(len(owner.get("actionIDs", [])) == 1 and valid_uuid(owner["actionIDs"][0]), "missing captured action", "FAIL")
        owners[scene] = owner
    require(all(native.values()) and len(set(native.values())) == 2, "native scenes alias", "FAIL")
    require(all(valid_uuid(c.get("viewID")) for c in owners.values()) and
            len({c["viewID"] for c in owners.values()}) == 2, "view owners alias", "FAIL")
    require(len({c["actionIDs"][0] for c in owners.values()}) == 2, "action owners alias", "FAIL")
    sid = owners["scene-A"].get("sessionID")
    require(valid_uuid(sid) and sid == owners["scene-B"].get("sessionID"), "session ownership", "FAIL")

    def matches(signal, context, label):
        actual = signal.get("rumContext", {})
        require(all(actual.get(k) == context.get(k) for k in ["viewID", "sessionID", "actionIDs"]), label, "FAIL")

    representative = assertion("log-representative-before-a")
    require_before(assertion("log-owner-b"), representative, "representative guard")
    require_before(representative, boundary, "representative guard")
    require(representative.get("evidenceSource") == "internal-hook", "representative source")
    matches(representative, owners["scene-B"], "A did not log against B representative")
    empty = assertion("log-fallback-empty-handoff")
    emissions = {suffix: assertion("log-emission-" + suffix) for suffix in ["a", "b", "fallback"]}
    fallback = emissions["fallback"].get("rumContext", {})
    matches(emissions["fallback"], unique([c for c in owners.values() if c["viewID"] == fallback.get("viewID")],
                                         "known representative"), "source-less representative changed")
    owners["source-less"] = fallback
    require_before(empty, emissions["fallback"], "empty handoff guard")
    events = [s for s in signals if s.get("kind") in ["rum-log", "rum-error", "rum-action"]]
    require([s.get("name") for s in events] == INVENTORY, "missing/duplicate/reordered Log inventory", "FAIL")
    require(not any(s.get("kind") in ["rum-resource", "rum-trace"] for s in signals), "unexpected local event", "FAIL")
    by_name = {s["name"]: s for s in events}
    for suffix, scene in [("a", "scene-A"), ("b", "scene-B"), ("fallback", "source-less")]:
        emission = emissions[suffix]
        require_before(boundary, emission, "emission guard")
        require_before(emission, by_name["log-info-" + suffix], "guard after logging")
        require(emission.get("evidenceSource") == "internal-hook", "emission owner source")
        matches(emission, owners[scene], "emission owner differs")
    require_before(by_name["mirror-log-error-a"], emissions["b"], "A mirror before B pair")
    require_before(by_name["mirror-log-error-b"], empty, "B mirror before source-less pair")
    require_before(by_name["mirror-log-error-fallback"], stops, "stop before final mirror")

    logs, errors, actions = [], [], []
    for phase in PHASES:
        signal = by_name[phase]
        owner = owners[source(phase)]
        require(signal.get("kind") == "rum-log" and signal.get("evidenceSource") == "log-mapper", "log mapper identity", "FAIL")
        require(signal.get("eventID") is None, "invented SDK log ID", "FAIL")
        require(signal.get("sourceContext", {}).get("logicalSceneID") == source(phase) and
                signal.get("sourceContext", {}).get("phase") == phase, "log source differs", "FAIL")
        matches(signal, owner, "log owner differs")
        wire = signal.get("log", {})
        expected = {"status": "error" if phase in ERRORS else "info", "message": phase, "service": SERVICE,
                    "session_id": sid, "view.id": owner["viewID"], "user_action.id": owner["actionIDs"][0],
                    "probe.run_id": run_id, "probe.phase": phase, "probe.source_scene": source(phase)}
        require(valid_uuid(wire.get("application_id")) and set(wire) == set(expected) | {"application_id"},
                "malformed log projection or private-key leakage", "FAIL")
        require(all(wire.get(k) == v for k, v in expected.items()), "encoded log fields differ", "FAIL")
        logs.append(dict(phase=phase, status=wire["status"], message=phase, service=SERVICE,
                         application_id=wire["application_id"], session_id=sid, view_id=owner["viewID"],
                         action_id=owner["actionIDs"][0], source_scene=source(phase)))
        if phase in ERRORS:
            mirror = by_name["mirror-" + phase]
            payload = assertion("log-mirror-payload-" + phase)
            require_before(signal, payload, "mirror before log")
            require_before(payload, mirror, "payload guard after mirror")
            require(mirror.get("kind") == "rum-error" and mirror.get("evidenceSource") == "rum-mapper", "mirror source", "FAIL")
            matches(mirror, owner, "mirror owner differs")
            info = mirror.get("error", {})
            require(valid_uuid(info.get("id")) and mirror.get("eventID") == info["id"] and
                    info.get("source") == "logger" and info.get("isCrash") is False, "mirror payload", "FAIL")
            require(mirror.get("sourceContext", {}).get("phase") == phase and
                    mirror.get("sourceContext", {}).get("logicalSceneID") == source(phase), "mirror source metadata", "FAIL")
            errors.append(dict(phase=phase, event_id=info["id"], session_id=sid, view_id=owner["viewID"],
                               action_ids=owner["actionIDs"], source_scene=source(phase),
                               error_source="logger", payload_matches=True, leaked_internal_attribute=False))
    require(len({row["application_id"] for row in logs}) == 1, "foreign log application", "FAIL")
    require(len({row["event_id"] for row in errors}) == 3, "duplicate mirror ID", "FAIL")
    for phase in ACTIONS:
        event = by_name[phase]
        owner = owners[source(phase)]
        require_before(stops, event, "action completed before stop boundary")
        require_before(event, verified, "action after verification")
        require(event.get("kind") == "rum-action" and event.get("evidenceSource") == "rum-mapper", "action source")
        matches(event, owner, "independent action mapper differs from captured snapshot")
        info = event.get("action", {})
        count = 2 if fallback["viewID"] == owner["viewID"] else 1
        require(info.get("id") == owner["actionIDs"][0] and event.get("eventID") == info["id"] and
                info.get("target") == phase and info.get("type") == "tap" and
                info.get("errorCount") == count and info.get("resourceCount") == 0, "action counts/identity", "FAIL")
        actions.append(dict(phase=phase, action_id=info["id"], target=phase, session_id=sid,
                            view_id=owner["viewID"], resource_count=0, error_count=count))
    inventory = {}
    for snapshot in snapshots:
        c = snapshot.get("rumContext", {})
        require(c.get("sessionID") == sid and valid_uuid(c.get("viewID")), "unexpected view/session", "FAIL")
        value = dict(view_id=c["viewID"], session_id=sid, name=c.get("viewName"))
        require(c["viewID"] not in inventory or inventory[c["viewID"]] == value, "mutated view identity", "FAIL")
        inventory[c["viewID"]] = value
    require(sorted(v["name"] or "" for v in inventory.values()) == ["ApplicationLaunch", "ProbeHomeView", "ProbeHomeView"],
            "complete RUM view inventory differs", "FAIL")
    return dict(assertions=24, session_id=sid, native_scenes=native, owners={s: c["viewID"] for s, c in owners.items()},
                logs=logs, errors=errors, actions=actions, views=list(inventory.values()),
                signal_count=len(signals), simultaneous_visibility_claimed=False)


def validate_backend(local, run_id, logs, errors, views, actions, resources, crashes):
    require(resources == [] and crashes == 0, "unexpected backend Resource/crash", "FAIL")
    require(len(logs) == 6 and len(errors) == 3 and len(views) == 3 and len(actions) == 2,
            "incomplete or extra backend inventory", "FAIL")
    require(all(isinstance(row.get("log_id"), str) and row["log_id"] for row in logs) and
            len({row["log_id"] for row in logs}) == 6, "missing/duplicate backend log IDs", "FAIL")
    require(len({row.get("event_id") for row in errors}) == 3 and
            len({row.get("view_id") for row in views}) == 3 and
            len({row.get("action_id") for row in actions}) == 2, "duplicate backend RUM IDs", "FAIL")
    for kind, rows in [("logs", logs), ("errors", errors), ("views", views), ("actions", actions)]:
        key = "view_id" if kind == "views" else "phase"
        for expected in local[kind]:
            row = unique([r for r in rows if r.get(key) == expected[key]], "backend " + kind)
            require(row.get("run_id") == run_id, "stale backend run hidden", "FAIL")
            require(all(canonical(row.get(k)) == canonical(v) for k, v in expected.items()),
                    "backend fields differ: " + kind + "/" + expected[key], "FAIL")
            if kind == "errors":
                require(row.get("is_crash") is False, "backend mirror crash discriminator", "FAIL")
            if kind == "logs":
                require(row.get("leaked_internal_attribute") is False, "private log metadata leaked", "FAIL")
    return dict(state="PASS", log_count=6, error_count=3, view_count=3, action_count=2, resource_count=0, crash_count=0)
