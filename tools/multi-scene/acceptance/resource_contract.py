"""T03 Resource oracle: exact captured owners across navigation/session renewal."""
import json
from pathlib import Path
from acceptance_common import require, require_before, require_identity, unique

SCENARIO = "resources.explicit-start.captured-owner-cross-scene-serial"
CONTRACT = "resource-scenario-contract.json"
SWIFT = ["resource-swift-request", "resource-swift-url", "resource-swift-method"]
OBJC = ["resource-objc-request", "resource-objc-url", "resource-objc-method"]
AUTO = ["resource-auto-success", "resource-auto-error"]
LEGACY = "resource-legacy-source-a"
PEER = "resource-peer-finished"
PHASES = SWIFT + [LEGACY] + OBJC + AUTO
FAILURES = OBJC + [AUTO[1]]


def validate_local(records, run_id):
    manifest = unique([r["manifest"] for r in records if r["type"] == "manifest"], "manifest")
    require(manifest.get("runID") == run_id and manifest.get("runMode") == "clean", "stale or non-clean manifest")
    require(not manifest.get("validationErrors"), "manifest validation errors")
    scenario = manifest.get("scenario", {})
    opened = set()
    for step in scenario.get("steps", []):
        if step.get("kind") == "open-window":
            opened.add(step.get("value"))
        if step.get("kind") == "wait-for-scene-ready":
            require(step.get("scene") not in opened, "readiness consumed twice")
    require_identity(scenario, json.loads(Path(__file__).with_name(CONTRACT).read_text()), "Resource fixture contract")
    signals = [r["signal"] for r in records if r["type"] == "signal"]
    require(signals and all(s.get("runID") == run_id and s.get("scenarioID") == SCENARIO and
                           s.get("schemaVersion") == 5 for s in signals), "stale signal identity/schema")
    require([s["sequence"] for s in signals] == list(range(1, len(signals) + 1)), "missing/duplicate/reordered signal sequence")
    terminal = unique([r for r in records if r["type"] == "semantic-result"], "terminal")
    result = terminal.get("result", {})
    require(terminal.get("runID") == run_id and result.get("scenarioID") == SCENARIO, "stale terminal identity")
    require(result.get("state") == "PASS", "app oracle did not pass: " + str(result.get("issues")), "FAIL")
    require(result.get("matchedExpectationCount") == 22 and result.get("issues") == [], "weak app oracle", "FAIL")
    require(not any(s.get("result") == "FAIL" for s in signals), "failed native assertion", "FAIL")
    batch = unique([s for s in signals if s.get("kind") == "step-started" and
                    s.get("stepKind") == "run-resource-ownership-batch"], "Resource batch")

    def assertion(name):
        s = unique([s for s in signals if s.get("kind") == "assertion" and s.get("name") == name], name)
        require(s.get("result") == "PASS", "native assertion failed: " + name, "FAIL")
        return s

    native, owners, initial = {}, {}, {}
    snapshots = [s for s in signals if s.get("kind") == "rum-view-snapshot"]
    require(all(s.get("evidenceSource") == "rum-mapper" for s in snapshots), "non-mapper view substituted")
    for scene, suffix in [("scene-A", "a"), ("scene-B", "b")]:
        ready = [s for s in signals if s.get("kind") == "scene-ready" and
                 s.get("semanticContext", {}).get("logicalSceneID") == scene]
        require(ready, "missing native readiness: " + scene)
        require_before(ready[0], batch, "native readiness")
        native[scene] = ready[0]["semanticContext"].get("nativeSceneID")
        homes = [s for s in snapshots if s.get("semanticContext", {}).get("logicalSceneID") == scene and
                 s.get("semanticContext", {}).get("screen") == "home" and s["sequence"] < batch["sequence"]]
        require(homes, "missing mapper Home before batch", "FAIL")
        require(len({s["rumContext"].get("viewID") for s in homes}) == 1, "Home occurrence changed before batch", "FAIL")
        initial[scene] = homes[-1]["rumContext"]
        require(initial[scene].get("viewActive") is True, "inactive Home prerequisite", "INCONCLUSIVE")
        owners[scene] = initial[scene].get("viewID")
        claimed = assertion("resource-owner-" + suffix)
        require(claimed.get("evidenceSource") == "internal-hook" and
                all(claimed.get("rumContext", {}).get(k) == initial[scene].get(k) for k in ["viewID", "sessionID"]),
                "start snapshot differs from independent mapper owner", "FAIL")
        require_before(batch, claimed, "batch start")
    require(all(native.values()) and all(owners.values()) and len(set(native.values())) == 2 and len(set(owners.values())) == 2,
            "native scenes or owners alias", "FAIL")
    old_session = initial["scene-A"]["sessionID"]
    require(initial["scene-B"]["sessionID"] == old_session, "initial owners in different sessions", "FAIL")
    started = assertion("resource-all-started")
    navigation = assertion("resource-navigation-finished")
    new_owner = assertion("resource-new-owner-b")
    boundary = assertion("resource-release-boundary")
    verified = assertion("resource-local-owners-verified")
    completed = assertion("resource-batch-finished")
    ordered = [batch, started, navigation, new_owner, boundary, verified, completed]
    for earlier, later in zip(ordered, ordered[1:]):
        require_before(earlier, later, "Resource lifecycle assertion")
    new_context = new_owner.get("rumContext", {})
    new_session = new_context.get("sessionID")
    require(new_session and new_session != old_session and new_context.get("viewID") not in owners.values(),
            "session/new peer occurrence was not renewed", "FAIL")
    for phase in PHASES:
        owner = initial["scene-B" if phase == LEGACY else "scene-A"]
        start = assertion("resource-start-" + phase)
        require_before(batch, start, "Resource start")
        require_before(start, started, "Resource start")
        require(all(start.get("rumContext", {}).get(k) == owner.get(k) for k in ["viewID", "sessionID"]),
                "wrong captured start owner: " + phase, "FAIL")
    for phase in AUTO:
        require_before(assertion("transport-paused-" + phase), started, "URLSession pause")
        require_before(boundary, assertion("transport-finished-" + phase), "URLSession completion")

    events = [s for s in signals if s.get("kind") in {"rum-resource", "rum-error"}]
    require(len(events) == 9, "missing/duplicate/unexpected Resource or error", "FAIL")
    expected = []
    for phase in PHASES:
        s = unique([s for s in events if s.get("name") == phase], phase)
        require(s.get("evidenceSource") == "rum-mapper", "non-mapper completion substituted")
        require_before(boundary, s, "Resource completion")
        require_before(s, verified, "Resource verification")
        owner = owners["scene-B" if phase == LEGACY else "scene-A"]
        require(s.get("rumContext", {}).get("viewID") == owner and s["rumContext"].get("sessionID") == old_session,
                "wrong exact completion owner: " + phase, "FAIL")
        require(s.get("sourceContext", {}).get("logicalSceneID") == "scene-A", "wrong Resource source", "FAIL")
        require(not s["rumContext"].get("actionIDs"), "Resource acquired a later action", "FAIL")
        is_error = phase in FAILURES
        require(s.get("kind") == ("rum-error" if is_error else "rum-resource"), "wrong completion kind", "FAIL")
        payload = s.get("error" if is_error else "resource", {})
        expected_url = "https://resource-probe.invalid/" + run_id + "/" + phase
        status = 200 if phase in AUTO else (0 if is_error else 201)
        require(payload.get("resourceURL" if is_error else "url") == expected_url, "wrong request URL/run", "FAIL")
        require(payload.get("resourceStatusCode" if is_error else "statusCode") == status, "wrong response status", "FAIL")
        require(payload.get("id"), "missing completion ID", "FAIL")
        row = dict(phase=phase, kind="error" if is_error else "resource", event_id=payload["id"],
                   view_id=owner, session_id=old_session, source_scene="scene-A", url=expected_url, status=status)
        if is_error:
            require(payload.get("source") == "network" and payload.get("isCrash") is not True, "wrong error classification", "FAIL")
        else:
            method = {SWIFT[0]: "POST", SWIFT[2]: "PUT"}.get(phase, "GET")
            require(payload.get("method") == method, "wrong Resource method", "FAIL")
            require(payload.get("durationNanoseconds", 0) > 0, "missing Resource duration", "FAIL")
            require(payload.get("size") == (2 if phase in AUTO else 55), "wrong Resource size", "FAIL")
            row.update(method=method, duration_ns=payload["durationNanoseconds"], size=payload["size"],
                       encoded_size=payload.get("encodedBodySize"))
        expected.append(row)
    require(len({e["event_id"] for e in expected}) == 9, "reused completion identity", "FAIL")
    peer = unique([s for s in signals if s.get("kind") == "rum-action" and s.get("name") == PEER], PEER)
    require(peer.get("evidenceSource") == "rum-mapper", "non-mapper peer action")
    require_before(boundary, peer, "peer action")
    require_before(peer, verified, "peer action verification")
    action = peer.get("action", {})
    require(peer.get("rumContext", {}).get("viewID") == new_context.get("viewID") and
            peer["rumContext"].get("sessionID") == new_session, "wrong peer action owner", "FAIL")
    require(action.get("id") and action.get("type") == "tap" and action.get("target") == PEER and
            action.get("resourceCount") == 0 and action.get("errorCount") == 0, "old Resource contaminated peer action", "FAIL")

    # A new A start excludes its old branch from restoration. B is restored once.
    # This inventory is independent of the internal owner snapshot and includes launch.
    view_inventory = {}
    for s in snapshots:
        c = s.get("rumContext", {})
        require(c.get("sessionID") in {old_session, new_session} and c.get("viewID"), "unexpected view/session", "FAIL")
        value = dict(view_id=c["viewID"], session_id=c["sessionID"], name=c.get("viewName"))
        if c["viewID"] in view_inventory:
            require(view_inventory[c["viewID"]] == value, "view identity mutated", "FAIL")
        view_inventory[c["viewID"]] = value
    roles = [(old_session, "ApplicationLaunch"), (old_session, "ProbeHomeView"), (old_session, "ProbeHomeView"),
             (old_session, "Resource Next A"), (new_session, "ProbeHomeView"),
             (new_session, "Resource New A"), (new_session, "Resource New B")]
    require(sorted((v["session_id"], v["name"] or "") for v in view_inventory.values()) == sorted(roles),
            "unexpected local view inventory", "FAIL")
    require(new_context.get("viewID") in view_inventory, "new peer snapshot lacks mapper evidence", "FAIL")
    return dict(assertions=22, session_ids=[old_session, new_session], native_scenes=native, owners=owners,
                views=list(view_inventory.values()), completions=expected,
                peer=dict(phase=PEER, action_id=action["id"], target=PEER, view_id=new_context["viewID"],
                          session_id=new_session, resource_count=0, error_count=0),
                signal_count=len(signals), simultaneous_visibility_claimed=False)


def validate_backend(local, run_id, resources, errors, views, actions, crashes):
    require(crashes == 0, "backend crash evidence", "FAIL")
    require(len(resources) == 5 and len(errors) == 4, "backend Resource/error inventory differs", "FAIL")
    require(len(views) == 7 and len({v.get("view_id") for v in views}) == 7, "backend view inventory differs", "FAIL")
    for expected in local["views"]:
        row = unique([v for v in views if v.get("view_id") == expected["view_id"]], "backend view")
        require(row.get("run_id") == run_id, "restored view run ID hidden by query", "FAIL")
        require(all(row.get(k) == v for k, v in expected.items()), "backend view differs from mapper", "FAIL")
    for expected in local["completions"]:
        rows = errors if expected["kind"] == "error" else resources
        row = unique([r for r in rows if r.get("phase") == expected["phase"]], expected["phase"])
        require(row.get("run_id") == run_id, "stale backend completion run", "FAIL")
        require(all(row.get(k) == v for k, v in expected.items()), "backend completion fields differ: " + expected["phase"], "FAIL")
        require(not row.get("action_ids"), "backend Resource acquired a later action", "FAIL")
        if expected["kind"] == "error":
            require(row.get("error_source") == "network" and row.get("is_crash") is not True, "backend error classification", "FAIL")
    require(len(actions) == 1, "backend peer action count differs", "FAIL")
    require(actions[0].get("run_id") == run_id and all(actions[0].get(k) == v for k, v in local["peer"].items()),
            "backend peer action fields/counts differ", "FAIL")
    return dict(state="PASS", resource_count=5, error_count=4, view_count=7, peer_action_count=1, crash_count=0)
