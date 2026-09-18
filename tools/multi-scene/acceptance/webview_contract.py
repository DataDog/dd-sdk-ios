"""T10: actual WebKit callbacks bind to exact native containers, with detached omission."""
import json
import uuid
from pathlib import Path
from acceptance_common import canonical, require, require_before, require_identity, unique

SCENARIO = "webview.captured-container.native-navigation-rebind-serial"
CONTRACT = "webview-scenario-contract.json"
HOST = "multi-scene-probe.invalid"
PHASES = ["web-a-original", "web-b-original", "web-a-navigation", "web-a-detached",
          "web-a-rebound-b", "web-b-after-teardown"]
SOURCES = ["scene-A", "scene-B", "scene-A", "detached", "scene-B", "scene-B"]
OWNERS = ["WebNativeA1", "WebNativeB1", "WebNativeA2", None, "WebNativeB1", "WebNativeB1"]
DOCUMENTS = ["A/initial", "B/initial", "A/navigation", "A/navigation", "A/navigation", "B/initial"]
NATIVE_NAMES = ["ApplicationLaunch", "ProbeHomeView", "ProbeHomeView", "WebNativeA1", "WebNativeA2", "WebNativeB1"]


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
    require_identity(scenario, json.loads(Path(__file__).with_name(CONTRACT).read_text()), "WebView fixture")
    signals = [r["signal"] for r in records if r["type"] == "signal"]
    require(signals and all(s.get("schemaVersion") == 5 and s.get("runID") == run_id and
                           s.get("scenarioID") == SCENARIO for s in signals), "stale signal identity")
    require([s["sequence"] for s in signals] == list(range(1, len(signals) + 1)), "signal sequence")
    require(all(type(s.get("timestampMilliseconds")) is int and s["timestampMilliseconds"] > 0 for s in signals),
            "malformed native timestamps")
    terminal = unique([r for r in records if r["type"] == "semantic-result"], "terminal")
    result = terminal.get("result", {})
    require(terminal.get("runID") == run_id and result.get("scenarioID") == SCENARIO, "stale terminal")
    require(result.get("state") == "PASS" and result.get("matchedExpectationCount") == 14 and
            result.get("issues") == [], "app oracle did not pass", "FAIL")
    require(not any(s.get("result") == "FAIL" for s in signals), "failed native assertion", "FAIL")
    require(not any(s.get("kind") in ["rum-error", "rum-action", "rum-resource", "rum-log", "rum-trace",
                                     "rum-operation"] for s in signals), "unexpected local event", "FAIL")

    def assertion(name):
        s = unique([s for s in signals if s.get("kind") == "assertion" and s.get("name") == name], name)
        require(s.get("result") == "PASS", "assertion failed: " + name, "FAIL")
        return s

    def ordered(*items):
        for a, b in zip(items, items[1:]):
            require_before(a, b, "WebView critical boundary")

    batch = unique([s for s in signals if s.get("kind") == "step-started" and
                    s.get("stepKind") == "run-webview-ownership-batch"], "WebView batch")
    replay = assertion("web-replay-ready")
    mounted = assertion("web-two-mounted-containers")
    ordered(batch, replay, mounted)
    snapshots = [s for s in signals if s.get("kind") == "rum-view-snapshot"]
    require(snapshots and all(s.get("evidenceSource") == "rum-mapper" for s in snapshots),
            "call-site native label substituted for mapper", "FAIL")
    inventory = {}
    for snapshot in snapshots:
        c = snapshot.get("rumContext", {})
        require(valid_uuid(c.get("sessionID")) and valid_uuid(c.get("viewID")), "invalid native identity", "FAIL")
        value = dict(view_id=c["viewID"], session_id=c["sessionID"], name=c.get("viewName"))
        require(c["viewID"] not in inventory or inventory[c["viewID"]] == value, "mutated native identity", "FAIL")
        inventory[c["viewID"]] = value
    require(sorted(v["name"] or "" for v in inventory.values()) == NATIVE_NAMES,
            "complete native inventory differs", "FAIL")
    sessions = {v["session_id"] for v in inventory.values()}
    require(len(sessions) == 1, "foreign native session", "FAIL")
    sid = sessions.pop()
    native = {}
    for scene in ["scene-A", "scene-B"]:
        ready = [s for s in signals if s.get("kind") == "scene-ready" and
                 s.get("semanticContext", {}).get("logicalSceneID") == scene]
        require(ready, "missing native readiness")
        require_before(ready[0], batch, "native readiness")
        native[scene] = ready[0]["semanticContext"].get("nativeSceneID")
        require(isinstance(native[scene], str) and native[scene], "missing actual scene")
        homes = [s for s in snapshots if s.get("semanticContext", {}).get("logicalSceneID") == scene and
                 s.get("semanticContext", {}).get("screen") == "home" and s["sequence"] < batch["sequence"]]
        require(homes and len({s["rumContext"]["viewID"] for s in homes}) == 1 and
                homes[-1]["rumContext"].get("viewActive") is True, "missing live Home before batch", "FAIL")
    require(len(set(native.values())) == 2, "actual scenes alias", "FAIL")
    owners = {}
    for name, scene in [("WebNativeA1", "scene-A"), ("WebNativeB1", "scene-B"), ("WebNativeA2", "scene-A")]:
        start = assertion("web-native-start-" + name)
        claimed = assertion("web-owner-" + name)
        ordered(replay, start, claimed)
        views = [s for s in snapshots if s.get("rumContext", {}).get("viewName") == name and
                 start["sequence"] < s["sequence"] < claimed["sequence"]]
        require(views, "owner guard lacks preceding independent mapper", "FAIL")
        actual = views[-1]
        context = actual["rumContext"]
        require(context.get("sessionHasReplay") is True and context.get("viewActive") is True and
                actual.get("semanticContext", {}).get("logicalSceneID") == scene and
                actual.get("semanticContext", {}).get("nativeSceneID") == native[scene],
                "owner lacks actual Replay/scene evidence", "FAIL")
        require(claimed.get("evidenceSource") == "internal-hook" and
                all(claimed.get("rumContext", {}).get(k) == context.get(k)
                    for k in ["viewID", "sessionID", "viewName"]), "native guard owner differs", "FAIL")
        owners[name] = context["viewID"]
    require(len(set(owners.values())) == 3, "native occurrences alias", "FAIL")
    callbacks = [s for s in signals if s.get("kind") == "web-bridge-message"]
    require([s.get("name") for s in callbacks] == PHASES, "missing/extra/reordered WebKit callbacks", "FAIL")
    expected, instances = [], []
    for i, signal in enumerate(callbacks):
        phase, scene, owner = PHASES[i], SOURCES[i], OWNERS[i]
        document = run_id + "/" + DOCUMENTS[i]
        actual_scene = native.get(scene)
        boundary = assertion("web-dispatch-boundary-" + phase)
        ready = assertion("web-document-ready-" + document)
        ordered(mounted, ready, boundary, signal)
        message = signal.get("webMessage", {})
        source = dict(logicalSceneID=scene, nativeSceneID=actual_scene, screen="web", phase=phase)
        for event in [signal, boundary]:
            require(all(event.get("sourceContext", {}).get(k) == v for k, v in source.items()),
                    "actual callback/dispatch attachment differs", "FAIL")
        require(signal.get("evidenceSource") == "webkit-callback" and signal.get("result") == "PASS" and
                signal.get("rumContext") is None, "callback input mislabeled as native output", "FAIL")
        require(valid_uuid(message.get("browserViewID")) and signal.get("eventID") == message["browserViewID"],
                "browser UUID identity", "FAIL")
        fixed = dict(phase=phase, runID=run_id, sourceScene=scene, documentID=document,
                     url="https://" + HOST + "/" + document, nativeSceneID=actual_scene,
                     spoofedSceneID=native["scene-B" if i in [0, 2, 3] else "scene-A"])
        require(all(message.get(k) == v for k, v in fixed.items()), "WebKit input differs", "FAIL")
        date = message.get("dateMilliseconds")
        require(type(date) is int and boundary["timestampMilliseconds"] < date <= signal["timestampMilliseconds"],
                "stale browser date or guard after dispatch", "FAIL")
        instance = message.get("webViewIdentity")
        require(isinstance(instance, str) and instance, "missing actual WebView identity", "FAIL")
        instances.append(instance)
        if owner:
            ordered(assertion("web-owner-" + owner), boundary)
            require(boundary.get("evidenceSource") == "internal-hook" and
                    boundary.get("rumContext", {}).get("viewID") == owners[owner] and
                    boundary.get("rumContext", {}).get("sessionID") == sid, "dispatch owner differs", "FAIL")
        else:
            require(boundary.get("rumContext") is None, "detached callback invented a native owner", "FAIL")
        expected.append(dict(view_id=message["browserViewID"], session_id=sid, name=phase,
                             source="browser", source_scene=scene, phase=phase, document_id=document,
                             url=message["url"], container_id=owners.get(owner),
                             container_source="ios" if owner else None, container_present=owner is not None))
    require(len({r["view_id"] for r in expected}) == 6 and
            not ({r["view_id"] for r in expected} & set(inventory)), "browser IDs reused", "FAIL")
    require(len(set(instances)) == 2 and all(instances[i] == instances[0] for i in [2, 3, 4]) and
            instances[1] == instances[5], "navigation/rebind replaced actual WebView", "FAIL")
    representative = assertion("web-representative-before-a")
    require(representative.get("evidenceSource") == "internal-hook" and
            representative.get("rumContext", {}).get("viewID") == owners["WebNativeB1"] and
            representative.get("rumContext", {}).get("sessionID") == sid, "contradictory representative missing", "FAIL")
    ordered(assertion("web-owner-WebNativeB1"), representative, assertion("web-dispatch-boundary-" + PHASES[0]))
    ordered(callbacks[0], assertion("web-dispatch-boundary-" + PHASES[1]))
    ordered(callbacks[1], assertion("web-navigation-boundary"), assertion("web-native-start-WebNativeA2"),
            assertion("web-owner-WebNativeA2"), assertion("web-document-ready-" + run_id + "/A/navigation"))
    for index, before, after in [(2, "web-detach-boundary", "web-detached"),
                                 (3, "web-rebind-boundary", "web-rebound"),
                                 (4, "web-teardown-boundary", "web-a-torn-down")]:
        ordered(callbacks[index], assertion(before), assertion(after),
                assertion("web-dispatch-boundary-" + PHASES[index + 1]))
    ordered(callbacks[-1], assertion("web-local-inputs-verified"), assertion("web-batch-finished"))
    return dict(assertions=14, session_id=sid, native_scenes=native, owners=owners,
                views=list(inventory.values()), browser_views=expected, signal_count=len(signals),
                simultaneous_visibility_claimed=False)


def validate_backend(local, run_id, views, actions, resources, errors, crashes):
    require(actions == [] and resources == [] and type(errors) is int and errors == 0 and
            type(crashes) is int and crashes == 0, "unexpected backend action/Resource/error/crash", "FAIL")
    require(len(views) == 12 and len({v.get("view_id") for v in views}) == 12, "incomplete/duplicate backend views", "FAIL")
    applications = {v.get("application_id") for v in views}
    require(len(applications) == 1 and valid_uuid(next(iter(applications))), "native application not preserved", "FAIL")
    for expected in local["views"] + local["browser_views"]:
        row = unique([v for v in views if v.get("view_id") == expected["view_id"]], "exact backend view")
        require(row.get("run_id") == run_id and row.get("session_id") == local["session_id"],
                "stale run or browser session not replaced", "FAIL")
        require(row.get("leaked_internal_attribute") is False, "private native scene key leaked", "FAIL")
        require(all(canonical(row.get(k)) == canonical(v) for k, v in expected.items()),
                "backend view/container differs: " + expected["name"], "FAIL")
        if expected in local["views"]:
            require(row.get("source") == "ios" and row.get("container_present") is False,
                    "native view mislabeled as browser container", "FAIL")
        else:
            require(row.get("has_replay") is True and row.get("is_active") is False,
                    "browser Replay/view activity differs", "FAIL")
            require(all(type(row.get(k)) is int and row[k] == v for k, v in
                        dict(action_count=0, resource_count=0, error_count=0, long_task_count=0,
                             time_spent=1000000, format_version=2, document_version=1).items()),
                    "browser counts/duration/version changed", "FAIL")
            require(row.get("loading_type") == "initial_load", "browser loading type changed", "FAIL")
    return dict(state="PASS", view_count=12, native_view_count=6, browser_view_count=6,
                correlated_browser_view_count=5, detached_container_count=0,
                action_count=0, resource_count=0, error_count=0, crash_count=0)
