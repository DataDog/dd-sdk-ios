import copy
import json
from pathlib import Path
import unittest
from acceptance_common import Rejected
import trace_contract as t


def fixture():
    run = "exp181-unit"
    records = [dict(type="manifest", manifest=dict(runID=run, runMode="clean", validationErrors=[],
               scenario=json.loads(Path(__file__).with_name(t.CONTRACT).read_text())))]
    signals = []

    def signal(kind, **kw):
        value = dict(kind=kind, sequence=len(signals) + 1, runID=run, scenarioID=t.SCENARIO,
                     schemaVersion=5, evidenceSource="probe")
        value.update(kw)
        signals.append(value)
        return value

    def assertion(name, owner=None, **kw):
        if owner is not None:
            kw.update(evidenceSource="internal-hook", rumContext=dict(viewID=owner, sessionID="session"))
        return signal("assertion", name=name, result="PASS", **kw)

    def view(identifier, name, scene=None):
        return signal("rum-view-snapshot", evidenceSource="rum-mapper",
                      semanticContext=dict(logicalSceneID=scene, screen="home"),
                      rumContext=dict(viewID=identifier, sessionID="session", viewName=name,
                                      viewActive=True, viewDocumentVersion=1))
    view("launch", "ApplicationLaunch")
    for scene in ["scene-A", "scene-B"]:
        signal("scene-ready", semanticContext=dict(logicalSceneID=scene, nativeSceneID="native-" + scene))
        view(scene, "ProbeHomeView", scene)
    signal("step-started", stepKind="run-trace-ownership-batch")
    assertion("trace-owner-a", "scene-A")
    assertion("trace-owner-b", "scene-B")
    assertion("trace-call-boundary")
    assertion("trace-start-a", "scene-A")
    assertion("trace-start-b", "scene-B")
    assertion("trace-fallback-empty-handoff")
    assertion("trace-start-fallback", "scene-B")
    assertion("trace-starts-enqueued")
    for phase in t.URL_PHASES:
        assertion("trace-only-request-started-" + phase, sourceContext=dict(logicalSceneID=t.source(phase)))
    assertion("trace-all-loaders-held")
    for index, phase in enumerate(t.PHASES):
        owner = "scene-A" if t.source(phase) == "scene-A" else "scene-B"
        peer = "scene-B" if owner == "scene-A" else "scene-A"
        assertion("trace-finish-" + phase, peer)
        operation = "urlsession.request" if phase.startswith("url-") else "exp181." + phase
        resource = ("https://multi-scene-probe.invalid/trace-only/" + run + "/" + t.source(phase) + "/home/" + phase
                    if phase.startswith("url-") else operation)
        span_id = f"{index + 1:016x}"
        signal("rum-trace", evidenceSource="trace-mapper", name=phase, eventID=span_id,
               sourceContext=dict(logicalSceneID=t.source(phase), screen="home"),
               rumContext=dict(viewID=owner, sessionID="session"),
               trace=dict(traceID=f"{index + 1:032x}", spanID=span_id, parentSpanID="0" * 16,
                          operationName=operation, resourceName=resource, serviceName=t.SERVICE, isError=False,
                          durationNanoseconds=123456789, startTimeNanoseconds=1789680000123456789,
                          rumApplicationID="application", rumSessionID="session", rumViewID=owner))
        if phase.startswith("url-"):
            assertion("trace-only-request-completed-" + phase, sourceContext=dict(logicalSceneID=t.source(phase)))
    assertion("trace-local-owners-verified")
    assertion("trace-batch-finished")
    records += [dict(type="signal", signal=s) for s in signals]
    records.append(dict(type="semantic-result", runID=run,
                        result=dict(scenarioID=t.SCENARIO, state="PASS", matchedExpectationCount=20, issues=[])))
    return records, run


def named(records, name):
    return next(r["signal"] for r in records if r.get("signal", {}).get("name") == name)


def resequence(records):
    for index, record in enumerate(r for r in records if r["type"] == "signal"):
        record["signal"]["sequence"] = index + 1


class TraceContractTests(unittest.TestCase):
    def test_golden_exact_local_and_backend_ownership(self):
        records, run = fixture()
        local = t.validate_local(records, run)
        self.assertEqual((local["assertions"], len(local["spans"]), len(local["views"])), (20, 9, 3))
        spans = [dict(s, run_id=run) for s in local["spans"]]
        views = [dict(s, run_id=run) for s in local["views"]]
        self.assertEqual(t.validate_backend(local, run, spans, views, [], 0, 0)["state"], "PASS")

    def test_changed_contract_and_consumed_readiness_rejected(self):
        for mode in ["readiness", "missing"]:
            records, run = fixture()
            scenario = records[0]["manifest"]["scenario"]
            if mode == "readiness":
                scenario["steps"].append(dict(kind="wait-for-scene-ready", scene="scene-B"))
            else:
                scenario["completionConditions"].pop()
            with self.assertRaises(Rejected):
                t.validate_local(records, run)

    def test_stale_runs_schema_and_mapper_identity_rejected(self):
        for key, value in [("runID", "restored"), ("scenarioID", "old"), ("schemaVersion", 4), ("evidenceSource", "probe")]:
            records, run = fixture()
            named(records, "native-a")[key] = value
            with self.assertRaises(Rejected):
                t.validate_local(records, run)

    def test_missing_and_late_critical_guards_rejected(self):
        guards = ["trace-owner-a", "trace-start-a", "trace-fallback-empty-handoff", "trace-start-fallback",
                  "trace-starts-enqueued", "trace-all-loaders-held", "trace-finish-native-a",
                  "trace-finish-url-b", "trace-only-request-started-url-a", "trace-local-owners-verified"]
        for guard in guards:
            records, run = fixture()
            record = next(r for r in records if r.get("signal", {}).get("name") == guard)
            records.remove(record)
            records.insert(-1, record)
            resequence(records)
            with self.assertRaises(Rejected, msg=guard):
                t.validate_local(records, run)

    def test_peer_finish_and_start_fallback_must_match_independent_owner(self):
        for name, owner in [("trace-owner-a", "scene-B"), ("trace-start-a", "scene-B"),
                            ("trace-start-fallback", "foreign"), ("trace-finish-native-a", "scene-A"),
                            ("trace-finish-url-fallback", "scene-B")]:
            records, run = fixture()
            named(records, name)["rumContext"]["viewID"] = owner
            with self.assertRaises(Rejected, msg=name):
                t.validate_local(records, run)

    def test_loader_callback_before_release_rejected(self):
        records, run = fixture()
        callback = next(r for r in records if r.get("signal", {}).get("name") == "trace-only-request-completed-url-b")
        records.remove(callback)
        boundary = next(i for i, r in enumerate(records) if r.get("signal", {}).get("name") == "trace-all-loaders-held")
        records.insert(boundary, callback)
        resequence(records)
        with self.assertRaises(Rejected):
            t.validate_local(records, run)

    def test_duplicate_missing_and_reordered_spans_rejected(self):
        for mode in ["duplicate", "missing", "reorder"]:
            records, run = fixture()
            index = next(i for i, r in enumerate(records) if r.get("signal", {}).get("name") == "native-b")
            if mode == "duplicate":
                records.insert(index, copy.deepcopy(records[index]))
            elif mode == "missing":
                records.pop(index)
            else:
                records[index], records[index + 2] = records[index + 2], records[index]
            resequence(records)
            with self.assertRaises(Rejected):
                t.validate_local(records, run)

    def test_payload_identity_timing_and_correlation_rejected(self):
        changes = [("rumViewID", "scene-A"), ("rumSessionID", "foreign"), ("rumApplicationID", "foreign"),
                   ("rumActionIDs", ["foreign"]), ("traceID", "1"), ("spanID", "f" * 16),
                   ("parentSpanID", "0" * 15 + "1"), ("durationNanoseconds", True),
                   ("durationNanoseconds", 0), ("startTimeNanoseconds", "1"),
                   ("serviceName", "foreign"), ("isError", True), ("operationName", "other"), ("resourceName", "other")]
        for key, value in changes:
            records, run = fixture()
            named(records, "native-b")["trace"][key] = value
            with self.assertRaises(Rejected, msg=key):
                t.validate_local(records, run)

    def test_joint_mapper_and_trace_misownership_cannot_fool_oracle(self):
        records, run = fixture()
        for name in ["native-a", "otel-a", "url-a"]:
            named(records, name)["rumContext"]["viewID"] = "scene-B"
            named(records, name)["trace"]["rumViewID"] = "scene-B"
        with self.assertRaises(Rejected):
            t.validate_local(records, run)

    def test_extra_rum_events_and_weak_terminal_rejected(self):
        for mode in ["resource", "error", "view", "terminal"]:
            records, run = fixture()
            if mode == "terminal":
                records[-1]["result"]["matchedExpectationCount"] = 19
            else:
                extra = copy.deepcopy(next(r for r in records if r.get("signal", {}).get("kind") == "rum-view-snapshot"))
                if mode == "view":
                    extra["signal"]["rumContext"]["viewID"] = "extra"
                else:
                    extra["signal"]["kind"] = "rum-" + mode
                records.insert(-1, extra)
                resequence(records)
            with self.assertRaises(Rejected):
                t.validate_local(records, run)

    def test_backend_missing_extra_duplicate_and_stale_records_rejected(self):
        records, run = fixture()
        local = t.validate_local(records, run)
        for kind in ["spans", "views"]:
            for mode in ["missing", "extra", "duplicate", "stale"]:
                data = {k: [dict(copy.deepcopy(s), run_id=run) for s in local[k]] for k in ["spans", "views"]}
                if mode == "missing":
                    data[kind].pop()
                elif mode == "extra":
                    data[kind].append(copy.deepcopy(data[kind][0]))
                elif mode == "duplicate":
                    data[kind][-1] = copy.deepcopy(data[kind][0])
                else:
                    data[kind][0]["run_id"] = "restored"
                with self.assertRaises(Rejected):
                    t.validate_backend(local, run, data["spans"], data["views"], [], 0, 0)

    def test_backend_exact_span_fields_and_rum_absence_rejected(self):
        records, run = fixture()
        local = t.validate_local(records, run)
        changes = [("trace_id", "f" * 32), ("view_id", "scene-A"), ("duration_ns", 123),
                   ("is_error", True), ("phase", "other"), ("action_ids", ["other"]),
                   ("application_id", "foreign"), ("session_id", "foreign"), ("parent_id", "f" * 16)]
        for key, value in changes:
            spans = [dict(copy.deepcopy(s), run_id=run) for s in local["spans"]]
            spans[0][key] = value
            views = [dict(s, run_id=run) for s in local["views"]]
            with self.assertRaises(Rejected, msg=key):
                t.validate_backend(local, run, spans, views, [], 0, 0)
        for resources, errors, crashes in [([{}], 0, 0), ([], 1, 0), ([], 0, 1)]:
            with self.assertRaises(Rejected):
                t.validate_backend(local, run, [dict(s, run_id=run) for s in local["spans"]],
                                   [dict(s, run_id=run) for s in local["views"]], resources, errors, crashes)
