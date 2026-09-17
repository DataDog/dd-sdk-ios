"""T04 current-view errors: live targets, fallbacks, callback and captured Resource."""
import json
from pathlib import Path
from acceptance_common import require, require_before, require_identity, unique

SCENARIO = "errors.explicit-target.current-view-cross-scene-serial"
CONTRACT = "error-scenario-contract.json"
PHASES = ["error-swift-message", "error-swift-error", "error-swift-callback",
          "error-objc-message", "error-objc-error", "error-invalid-exact-a",
          "error-invalid-representative-b", "error-legacy-source-a", "error-resource-captured-a"]
PEERS = PHASES[6:8]
ACTIONS = ["error-action-a", "error-action-b"]
RESOURCE = PHASES[-1]


def error_type(phase):
    return ("ProbeMessage" if phase == PHASES[0] else None if phase == PHASES[3]
            else "ProbeResource" if phase == RESOURCE else "ProbeCurrentError - 177")


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
    require_identity(scenario, json.loads(Path(__file__).with_name(CONTRACT).read_text()), "current-error fixture")
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
    batch = unique([s for s in signals if s.get("kind") == "step-started" and
                    s.get("stepKind") == "run-current-view-error-batch"], "error batch")

    def assertion(name):
        s = unique([s for s in signals if s.get("kind") == "assertion" and s.get("name") == name], name)
        require(s.get("result") == "PASS", "assertion failed: " + name, "FAIL")
        return s

    boundary = assertion("error-call-boundary")
    enqueued = assertion("error-calls-enqueued")
    callback = assertion("error-callback-completed")
    verified = assertion("error-local-owners-verified")
    completed = assertion("error-batch-finished")
    for earlier, later in [(batch, boundary), (boundary, enqueued), (enqueued, verified),
                           (boundary, callback), (callback, verified), (verified, completed)]:
        require_before(earlier, later, "error batch/callback boundary")
    snapshots = [s for s in signals if s.get("kind") == "rum-view-snapshot" and s.get("evidenceSource") == "rum-mapper"]
    owners, native = {}, {}
    for scene, suffix in [("scene-A", "a"), ("scene-B", "b")]:
        ready = [s for s in signals if s.get("kind") == "scene-ready" and
                 s.get("semanticContext", {}).get("logicalSceneID") == scene]
        require(ready, "missing native readiness")
        require_before(ready[0], batch, "native readiness")
        native[scene] = ready[0]["semanticContext"].get("nativeSceneID")
        claimed = assertion("error-owner-" + suffix)
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
    require(len(events) == 9, "complete error inventory differs", "FAIL")
    expected_actions = []
    for scene, name, count in [("scene-A", ACTIONS[0], 7), ("scene-B", ACTIONS[1], 2)]:
        action = unique([s for s in signals if s.get("kind") == "rum-action" and s.get("name") == name], name)
        require(action.get("evidenceSource") == "rum-mapper", "non-mapper action")
        require_before(boundary, action, "action start boundary")
        require_before(action, verified, "action verification")
        payload, context = action.get("action", {}), action.get("rumContext", {})
        require(context.get("viewID") == owners[scene]["viewID"] and context.get("sessionID") == sid, "wrong action owner", "FAIL")
        require(payload.get("id") and payload.get("type") == "tap" and payload.get("target") == name and
                payload.get("errorCount") == count and payload.get("resourceCount") == 0, "foreign action counts", "FAIL")
        expected_actions.append(dict(phase=name, action_id=payload["id"], target=name, view_id=context["viewID"],
                                     session_id=sid, error_count=count, resource_count=0))
    require(expected_actions[0]["action_id"] != expected_actions[1]["action_id"], "action IDs alias", "FAIL")
    expected_errors = []
    ordered_errors = []
    for phase in PHASES:
        event = unique([e for e in events if e.get("name") == phase], phase)
        require(event.get("evidenceSource") == "rum-mapper", "non-mapper error")
        require_before(boundary, event, "error boundary")
        require_before(event, verified, "error verification")
        payload_check = assertion("error-payload-" + phase)
        require_before(boundary, payload_check, "payload check")
        require_before(payload_check, event, "payload check before mapper record")
        owner = owners["scene-B" if phase in PEERS else "scene-A"]
        action = expected_actions[1 if phase in PEERS else 0]
        context, payload = event.get("rumContext", {}), event.get("error", {})
        require(context.get("viewID") == owner["viewID"] and context.get("sessionID") == sid and
                context.get("actionIDs") == [action["action_id"]], "wrong error view/session/action owner: " + phase, "FAIL")
        require(event.get("sourceContext", {}).get("logicalSceneID") == "scene-A", "wrong source marker", "FAIL")
        source = "network" if phase == RESOURCE else "custom"
        url = "https://error-probe.invalid/" + run_id + "/" + RESOURCE if phase == RESOURCE else None
        status = 0 if phase == RESOURCE else None
        require(payload.get("id") and payload.get("source") == source and payload.get("type") == error_type(phase) and
                payload.get("isCrash") is not True and payload.get("resourceURL") == url and
                payload.get("resourceStatusCode") == status, "wrong synthetic error payload", "FAIL")
        expected_errors.append(dict(phase=phase, event_id=payload["id"], view_id=owner["viewID"], session_id=sid,
                                    source_scene="scene-A", action_ids=[action["action_id"]], error_source=source,
                                    error_type=error_type(phase), url=url, status=status, payload_matches=True))
        ordered_errors.append(event)
    for earlier, later in zip(ordered_errors, ordered_errors[1:]):
        require_before(earlier, later, "error submission order")
    require_before(ordered_errors[2], callback, "callback before error mapper")
    require(len({e["event_id"] for e in expected_errors}) == 9, "duplicate error IDs", "FAIL")
    inventory = {}
    for s in snapshots:
        c = s.get("rumContext", {})
        require(c.get("sessionID") == sid and c.get("viewID"), "unexpected view/session", "FAIL")
        value = dict(view_id=c["viewID"], session_id=sid, name=c.get("viewName"))
        if c["viewID"] in inventory:
            require(inventory[c["viewID"]] == value, "mutated view identity", "FAIL")
        inventory[c["viewID"]] = value
    require(sorted(v["name"] or "" for v in inventory.values()) == ["ApplicationLaunch", "ProbeHomeView", "ProbeHomeView"],
            "complete local view inventory differs", "FAIL")
    return dict(assertions=24, callbacks=1, session_id=sid, native_scenes=native,
                owners={s: c["viewID"] for s, c in owners.items()}, views=list(inventory.values()),
                errors=expected_errors, actions=expected_actions, signal_count=len(signals), simultaneous_visibility_claimed=False)


def validate_backend(local, run_id, resources, errors, views, actions, crashes):
    require(crashes == 0 and len(resources) == 0, "backend crashes or unexpected Resources", "FAIL")
    require(len(errors) == 9 and len(views) == 3 and len(actions) == 2, "complete backend inventory differs", "FAIL")
    require(len({v.get("view_id") for v in views}) == 3 and len({e.get("event_id") for e in errors}) == 9,
            "duplicate backend event IDs", "FAIL")
    for kind in ["views", "errors", "actions"]:
        rows = dict(views=views, errors=errors, actions=actions)[kind]
        key = "view_id" if kind == "views" else "phase"
        for expected in local[kind]:
            row = unique([r for r in rows if r.get(key) == expected[key]], "backend " + kind)
            require(row.get("run_id") == run_id, "restored/stale backend run hidden", "FAIL")
            require(all(row.get(k) == v for k, v in expected.items()), "backend fields differ: " + kind, "FAIL")
            if kind == "errors":
                require(row.get("is_crash") is not True, "backend error is a crash", "FAIL")
    return dict(state="PASS", error_count=9, resource_count=0, view_count=3, action_count=2, crash_count=0)
