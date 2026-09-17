import copy
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("acceptance", Path(__file__).with_name("acceptance.py"))
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)


def fixture():
    run_id = "exp161-unit-run"
    records = [{"type": "manifest", "manifest": {
        "runID": run_id, "runMode": "clean", "validationErrors": [],
        "scenario": json.loads(Path(__file__).with_name("scenario-contract.json").read_text())}}]
    signals = []

    def signal(kind, **kwargs):
        value = dict(sequence=len(signals) + 1, timestampMilliseconds=1000 + len(signals),
                     runID=run_id, scenarioID=a.SCENARIO, schemaVersion=5,
                     kind=kind, evidenceSource="probe")
        value.update(kwargs)
        signals.append(value)
        return value

    for scene in ["scene-A", "scene-B"]:
        context = {"logicalSceneID": scene, "nativeSceneID": "native-" + scene, "screen": "home"}
        signal("scene-ready", semanticContext=context)
        signal("rum-view-snapshot", semanticContext=context, evidenceSource="rum-mapper",
               rumContext={"viewID": "view-" + scene, "sessionID": "session", "viewActive": True})
    signal("rum-view-snapshot", semanticContext={"screen": "application-launch"},
           rumContext={"viewID": "launch", "sessionID": "session", "viewActive": False})
    signal("step-started", stepKind="run-continuous-action-target-batch", stepIndex=4)
    phase_index = 0
    for kind, name in a.BATCH:
        signal("step-started", stepKind=kind, name=name)
        if kind != "emit-scene-context-marker":
            signal("assertion", name="continuous-action-submitted-" + name, result="PASS")
        matching = next((p for p in a.PHASES if p[0] == name), None)
        if matching:
            _, owner, source, _ = matching
            signal("rum-action", evidenceSource="rum-mapper",
                   sourceContext={"logicalSceneID": source, "nativeSceneID": "native-" + source, "phase": name, "uptime": 5000.0 + phase_index},
                   rumContext={"viewID": "view-" + owner, "sessionID": "session"},
                   action={"id": "action-" + str(phase_index), "target": name, "type": "custom",
                           "loadingTimeNanoseconds": 100})
            phase_index += 1
    records.extend({"type": "signal", "signal": s} for s in signals)
    records.append({"type": "semantic-result", "runID": run_id,
                    "result": {"scenarioID": a.SCENARIO, "state": "PASS",
                               "matchedExpectationCount": 15, "issues": []}})
    return records, run_id


def backend(local, run_id):
    actions = [{**r, "run_id": run_id, "session_id": local["session_id"]} for r in local["actions"]]
    views = [{"view_id": v, "session_id": local["session_id"], "run_id": run_id} for v in local["view_ids"]]
    return actions, views


class AcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.records, self.run_id = fixture()

    def signals(self):
        return [r["signal"] for r in self.records if r["type"] == "signal"]

    def rejects(self, match):
        with self.assertRaisesRegex(a.Rejected, match):
            a.validate_local(self.records, self.run_id)

    def test_complete_local_and_backend(self):
        local = a.validate_local(self.records, self.run_id)
        actions, views = backend(local, self.run_id)
        self.assertEqual(a.validate_backend(local, self.run_id, actions, views, 0)["state"], "PASS")

    def test_mixed_console_preserves_exact_objects(self):
        raw = "\n".join("system noise " + json.dumps(r) + " suffix" for r in self.records)
        self.assertEqual(a.parse_records(raw), self.records)

    def test_truncated_object_is_not_invented(self):
        self.assertEqual(a.parse_records('noise {"type":"signal","signal":'), [])

    def test_stale_build_and_source_identity(self):
        for label in ["installed binary", "source during build"]:
            with self.assertRaisesRegex(a.Rejected, "stale or changed"):
                a.require_identity("prior-build", "frozen-build", label)

    def test_stale_manifest(self):
        self.records[0]["manifest"]["runID"] = "previous-run"
        self.rejects("stale")

    def test_stale_fixture_oracle(self):
        self.records[0]["manifest"]["scenario"]["expectedSemanticTimeline"].pop()
        self.rejects("stale fixture")

    def test_same_count_fixture_with_wrong_owner_rejected(self):
        self.records[0]["manifest"]["scenario"]["expectedSemanticTimeline"][2]["scene"] = "scene-A"
        self.rejects("fixture contract")

    def test_native_mapper_schema_has_no_occurrence_label(self):
        self.assertTrue(all("occurrence" not in s.get("semanticContext", {}) for s in self.signals()))
        self.assertTrue(all("semanticContext" not in s for s in self.signals() if s["kind"] == "rum-action"))
        local = a.validate_local(self.records, self.run_id)
        self.assertEqual(local["owners"], {"scene-A": "view-scene-A", "scene-B": "view-scene-B"})

    def test_wrong_native_source_rejected(self):
        next(s for s in self.signals() if s["kind"] == "rum-action")["sourceContext"]["nativeSceneID"] = "foreign-scene"
        self.rejects("wrong native source")

    def test_consumed_readiness(self):
        self.records[0]["manifest"]["scenario"]["steps"][3] = {
            "kind": "wait-for-scene-ready", "scene": "scene-B"}
        self.rejects("readiness consumed twice")

    def test_missing_signal(self):
        del self.records[3]
        self.rejects("signal sequence")

    def test_duplicate_signal(self):
        self.records.insert(3, copy.deepcopy(self.records[2]))
        self.rejects("signal sequence")

    def test_wrong_owner_despite_passing_app_oracle(self):
        next(s for s in self.signals() if s["kind"] == "rum-action")["rumContext"]["viewID"] = "view-scene-A"
        self.rejects("wrong exact owner")

    def test_wrong_final_name(self):
        s = next(s for s in self.signals() if s.get("sourceContext", {}).get("phase") == "long-running-finished-b")
        s["action"]["target"] = "long-running-shared"
        self.rejects("final name")

    def test_early_completion(self):
        s = next(s for s in self.signals() if s.get("sourceContext", {}).get("phase") == "long-running-finished-b")
        s["sourceContext"]["phase"] = "long-running-shared"
        self.rejects("expected exactly one")

    def test_same_view_occurrence_in_both_scenes(self):
        for s in self.signals():
            if s["kind"] == "rum-view-snapshot" and s.get("semanticContext", {}).get("logicalSceneID") == "scene-B":
                s["rumContext"]["viewID"] = "view-scene-A"
        self.rejects("alias")

    def test_inactive_view_at_start_is_inconclusive(self):
        self.signals()[1]["rumContext"]["viewActive"] = False
        with self.assertRaises(a.Rejected) as error:
            a.validate_local(self.records, self.run_id)
        self.assertEqual(error.exception.state, "INCONCLUSIVE")

    def test_late_submission_assertion_cannot_pass(self):
        signals = self.signals()
        first = next(i for i, s in enumerate(signals) if s.get("name") == "continuous-action-submitted-long-running-shared")
        signals[first], signals[first + 1] = signals[first + 1], signals[first]
        for index, s in enumerate(signals):
            s["sequence"] = index + 1
        self.records = [self.records[0]] + [{"type": "signal", "signal": s} for s in signals] + [self.records[-1]]
        self.rejects("outside critical")

    def test_reveal_after_callback_negative_control(self):
        # EXP-142 discriminator: a settled marker cannot replace evidence at the callback boundary.
        with self.assertRaisesRegex(a.Rejected, "critical boundary"):
            a.require_before({"sequence": 22}, {"sequence": 20}, "fresh returned occurrence")

    def test_backend_restored_run_identifier(self):
        local = a.validate_local(self.records, self.run_id)
        actions, views = backend(local, self.run_id)
        views[0]["run_id"] = "previous-run"
        with self.assertRaisesRegex(a.Rejected, "restored view"):
            a.validate_backend(local, self.run_id, actions, views, 0)

    def test_backend_owner_mismatch(self):
        local = a.validate_local(self.records, self.run_id)
        actions, views = backend(local, self.run_id)
        actions[0]["view_id"] = "view-scene-A"
        with self.assertRaisesRegex(a.Rejected, "view_id mismatch"):
            a.validate_backend(local, self.run_id, actions, views, 0)

    def test_backend_missing_or_duplicate_action(self):
        local = a.validate_local(self.records, self.run_id)
        actions, views = backend(local, self.run_id)
        with self.assertRaisesRegex(a.Rejected, "action count"):
            a.validate_backend(local, self.run_id, actions + [actions[0]], views, 0)

    def test_backend_explicit_stop_order(self):
        local = a.validate_local(self.records, self.run_id)
        actions, views = backend(local, self.run_id)
        for collection in [local["actions"], actions]:
            next(r for r in collection if r["phase"] == "long-running-finished-a")["uptime"] = 0
        with self.assertRaisesRegex(a.Rejected, "stop order"):
            a.validate_backend(local, self.run_id, actions, views, 0)

    def test_bridge_rejects_restored_or_incomplete_response(self):
        request = {"request_id": "new", "query": "exact"}
        good = {"request_id": "new", "request_sha256": a.digest(request), "query": "exact",
                "provider": "datadog-mcp", "ok": True, "complete": True, "data": []}
        self.assertEqual(a.validate_bridge(request, good), [])
        for field, value in [("request_id", "old"), ("request_sha256", "old"),
                             ("query", "broader"), ("complete", False), ("ok", False)]:
            bad = {**good, field: value}
            with self.assertRaises(a.Rejected):
                a.validate_bridge(request, bad)


if __name__ == "__main__":
    unittest.main()
