"""T08: nine native/OTel/URLSession spans retain exact captured start ownership."""
import json
import re
from pathlib import Path
from acceptance_common import canonical, require, require_before, require_identity, unique

SCENARIO = "traces.captured-start.native-otel-urlsession-cross-scene-serial"
CONTRACT = "trace-scenario-contract.json"
PHASES = ["native-b", "otel-b", "native-a", "otel-a", "native-fallback", "otel-fallback",
          "url-b", "url-a", "url-fallback"]
URL_PHASES = ["url-a", "url-b", "url-fallback"]
SERVICE = "ios-sdk-native-multi-scene-probe"


def source(phase):
    return "scene-A" if phase.endswith("-a") else "scene-B" if phase.endswith("-b") else "source-less"


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
    require_identity(scenario, json.loads(Path(__file__).with_name(CONTRACT).read_text()), "Trace fixture")
    signals = [r["signal"] for r in records if r["type"] == "signal"]
    require(signals and all(s.get("schemaVersion") == 5 and s.get("runID") == run_id and
                           s.get("scenarioID") == SCENARIO for s in signals), "stale signal identity")
    require([s["sequence"] for s in signals] == list(range(1, len(signals) + 1)), "signal sequence")
    terminal = unique([r for r in records if r["type"] == "semantic-result"], "terminal")
    result = terminal.get("result", {})
    require(terminal.get("runID") == run_id and result.get("scenarioID") == SCENARIO, "stale terminal")
    require(result.get("state") == "PASS" and result.get("matchedExpectationCount") == 20 and
            result.get("issues") == [], "app oracle did not pass", "FAIL")
    require(not any(s.get("result") == "FAIL" for s in signals), "failed native assertion", "FAIL")

    def assertion(name):
        signal = unique([s for s in signals if s.get("kind") == "assertion" and s.get("name") == name], name)
        require(signal.get("result") == "PASS", "assertion failed: " + name, "FAIL")
        return signal

    batch = unique([s for s in signals if s.get("kind") == "step-started" and
                    s.get("stepKind") == "run-trace-ownership-batch"], "Trace batch")
    boundary = assertion("trace-call-boundary")
    enqueued = assertion("trace-starts-enqueued")
    held = assertion("trace-all-loaders-held")
    verified = assertion("trace-local-owners-verified")
    completed = assertion("trace-batch-finished")
    for earlier, later in zip([batch, boundary, enqueued, held, verified], [boundary, enqueued, held, verified, completed]):
        require_before(earlier, later, "Trace critical boundary")
    snapshots = [s for s in signals if s.get("kind") == "rum-view-snapshot" and s.get("evidenceSource") == "rum-mapper"]
    owners, native = {}, {}
    for scene, suffix in [("scene-A", "a"), ("scene-B", "b")]:
        ready = [s for s in signals if s.get("kind") == "scene-ready" and
                 s.get("semanticContext", {}).get("logicalSceneID") == scene]
        require(ready, "missing native readiness")
        require_before(ready[0], batch, "native readiness")
        native[scene] = ready[0]["semanticContext"].get("nativeSceneID")
        claimed = assertion("trace-owner-" + suffix)
        require_before(batch, claimed, "owner guard")
        require_before(claimed, boundary, "owner guard")
        homes = [s for s in snapshots if s.get("semanticContext", {}).get("logicalSceneID") == scene and
                 s.get("semanticContext", {}).get("screen") == "home" and s["sequence"] < boundary["sequence"]]
        require(homes, "missing independent mapper Home")
        require(len({s["rumContext"].get("viewID") for s in homes}) == 1, "Home occurrence changed", "FAIL")
        owner = homes[-1].get("rumContext", {})
        require(owner.get("viewActive") is True, "requested owner ended before calls", "INCONCLUSIVE")
        require(claimed.get("evidenceSource") == "internal-hook" and
                all(claimed.get("rumContext", {}).get(k) == owner.get(k) for k in ["viewID", "sessionID"]),
                "claimed owner differs from independent mapper", "FAIL")
        owners[scene] = owner
    require(all(native.values()) and len(set(native.values())) == 2, "native scenes alias", "FAIL")
    require(all(c.get("viewID") for c in owners.values()) and
            len({c["viewID"] for c in owners.values()}) == 2, "view owners alias", "FAIL")
    sid = owners["scene-A"].get("sessionID")
    require(sid and sid == owners["scene-B"].get("sessionID"), "session ownership", "FAIL")
    starts = {suffix: assertion("trace-start-" + suffix) for suffix in ["a", "b", "fallback"]}
    empty = assertion("trace-fallback-empty-handoff")
    require_before(starts["b"], empty, "empty handoff guard")
    require_before(empty, starts["fallback"], "empty handoff guard")
    fallback = starts["fallback"].get("rumContext", {})
    require(fallback.get("viewID") in {c["viewID"] for c in owners.values()} and fallback.get("sessionID") == sid,
            "fallback not bound to independent current owner", "FAIL")
    owners["source-less"] = fallback
    for suffix, scene in [("a", "scene-A"), ("b", "scene-B"), ("fallback", "source-less")]:
        start = starts[suffix]
        require_before(boundary, start, "start owner guard")
        require_before(start, enqueued, "start owner guard")
        require(start.get("evidenceSource") == "internal-hook" and
                all(start.get("rumContext", {}).get(k) == owners[scene].get(k) for k in ["viewID", "sessionID"]),
                "start owner differs", "FAIL")
    require_before(starts["a"], starts["b"], "start order")
    for phase in URL_PHASES:
        loader = assertion("trace-only-request-started-" + phase)
        require_before(boundary, loader, "URL loader")
        require_before(loader, held, "all URL loaders held")
        require(loader.get("sourceContext", {}).get("logicalSceneID") == source(phase), "loader source differs", "FAIL")
    require(not any(s.get("kind") in ["rum-resource", "rum-error"] for s in signals), "unexpected RUM event", "FAIL")
    traces = [s for s in signals if s.get("kind") == "rum-trace"]
    require([s.get("name") for s in traces] == PHASES, "missing/duplicate/reordered Trace inventory", "FAIL")
    expected_spans = []
    for phase, signal in zip(PHASES, traces):
        finish = assertion("trace-finish-" + phase)
        require_before(held, finish, "held-before-release guard")
        require_before(finish, signal, "finish guard")
        require_before(signal, verified, "span before verification")
        owner = owners[source(phase)]
        peer = owners["scene-B"] if owner["viewID"] == owners["scene-A"]["viewID"] else owners["scene-A"]
        require(finish.get("evidenceSource") == "internal-hook" and
                all(finish.get("rumContext", {}).get(k) == peer.get(k) for k in ["viewID", "sessionID"]),
                "completion did not run under contradictory peer", "FAIL")
        if phase.startswith("url-"):
            callback = assertion("trace-only-request-completed-" + phase)
            require_before(finish, callback, "URL completion before release")
            require_before(callback, verified, "URL callback inventory")
            require(callback.get("sourceContext", {}).get("logicalSceneID") == source(phase), "URL callback source differs", "FAIL")
        context, span = signal.get("rumContext", {}), signal.get("trace", {})
        require(signal.get("evidenceSource") == "trace-mapper" and context.get("viewID") == owner["viewID"] and
                context.get("sessionID") == sid, "wrong captured Trace owner", "FAIL")
        require(signal.get("sourceContext", {}).get("logicalSceneID") == source(phase) and
                signal.get("sourceContext", {}).get("screen") == "home", "wrong source metadata", "FAIL")
        require(span.get("rumSessionID") == sid and span.get("rumViewID") == owner["viewID"] and
                span.get("rumActionIDs") in [None, []] and context.get("actionIDs") in [None, []],
                "Trace correlation disagrees or inherited foreign action", "FAIL")
        app = span.get("rumApplicationID")
        require(isinstance(app, str) and app, "missing Trace application correlation", "FAIL")
        trace_id, span_id = span.get("traceID"), span.get("spanID")
        require(isinstance(trace_id, str) and re.fullmatch("[0-9a-f]{32}", trace_id) and int(trace_id, 16) > 0,
                "invalid full Trace ID", "FAIL")
        require(isinstance(span_id, str) and re.fullmatch("[0-9a-f]{16}", span_id) and int(span_id, 16) > 0 and
                signal.get("eventID") == span_id, "invalid/broken span ID", "FAIL")
        require(span.get("parentSpanID") == "0000000000000000", "unexpected parent", "FAIL")
        require(type(span.get("durationNanoseconds")) is int and span["durationNanoseconds"] > 0 and
                type(span.get("startTimeNanoseconds")) is int and span["startTimeNanoseconds"] > 0,
                "invalid exact encoded span timing", "FAIL")
        operation = "urlsession.request" if phase.startswith("url-") else "exp181." + phase
        resource = ("https://multi-scene-probe.invalid/trace-only/" + run_id + "/" + source(phase) + "/home/" + phase
                    if phase.startswith("url-") else operation)
        require(span.get("operationName") == operation and span.get("resourceName") == resource and
                span.get("serviceName") == SERVICE and span.get("isError") is False, "span payload differs", "FAIL")
        expected_spans.append(dict(phase=phase, trace_id=trace_id, span_id=span_id, parent_id=span["parentSpanID"],
                                   application_id=app, session_id=sid, view_id=owner["viewID"], action_ids=[],
                                   operation=operation, resource=resource, service=SERVICE,
                                   duration_ns=span["durationNanoseconds"], is_error=False))
    require(len({s["trace_id"] for s in expected_spans}) == 9 and len({s["span_id"] for s in expected_spans}) == 9,
            "duplicate root trace/span IDs", "FAIL")
    require(len({s["application_id"] for s in expected_spans}) == 1, "foreign application", "FAIL")
    inventory = {}
    for snapshot in snapshots:
        context = snapshot.get("rumContext", {})
        require(context.get("sessionID") == sid and context.get("viewID"), "unexpected RUM view/session", "FAIL")
        inventory[context["viewID"]] = dict(view_id=context["viewID"], session_id=sid, name=context.get("viewName"))
    require(len(inventory) == 3 and set(inventory) >= {owners[s]["viewID"] for s in ["scene-A", "scene-B"]},
            "complete RUM view inventory differs", "FAIL")
    require(sorted(v["name"] for v in inventory.values()) == ["ApplicationLaunch", "ProbeHomeView", "ProbeHomeView"],
            "unexpected RUM view names", "FAIL")
    return dict(assertions=20, session_id=sid, native_scenes=native,
                owners={s: c["viewID"] for s, c in owners.items()}, spans=expected_spans,
                views=list(inventory.values()), signal_count=len(signals), simultaneous_visibility_claimed=False)


def validate_backend(local, run_id, spans, views, resources, errors, crashes):
    require(errors == 0 and crashes == 0 and resources == [], "unexpected backend RUM events", "FAIL")
    require(len(spans) == 9 and len(views) == 3, "incomplete or extra backend inventory", "FAIL")
    require(len({s.get("span_id") for s in spans}) == 9 and len({v.get("view_id") for v in views}) == 3,
            "duplicate backend inventory", "FAIL")
    for kind, rows, key in [("spans", spans, "span_id"), ("views", views, "view_id")]:
        for expected in local[kind]:
            row = unique([r for r in rows if r.get(key) == expected[key]], "backend " + kind)
            require(row.get("run_id") == run_id, "stale backend run hidden", "FAIL")
            require(all(canonical(row.get(k)) == canonical(v) for k, v in expected.items()),
                    "backend fields differ: " + kind + "/" + expected[key], "FAIL")
    return dict(state="PASS", span_count=9, view_count=3, resource_count=0, error_count=0, crash_count=0)
