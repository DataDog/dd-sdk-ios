import copy
import json
from pathlib import Path
import unittest
from acceptance_common import Rejected
import attribute_contract as a


def fixture():
    run_id = "exp178-unit"
    records = [dict(type="manifest", manifest=dict(runID=run_id, runMode="clean", validationErrors=[],
               scenario=json.loads(Path(__file__).with_name(a.CONTRACT).read_text())))]
    signals = []

    def signal(kind, **kw):
        value = dict(kind=kind, sequence=len(signals) + 1, runID=run_id, scenarioID=a.SCENARIO,
                     schemaVersion=5, evidenceSource="probe")
        value.update(kw)
        signals.append(value)
        return value

    def assertion(name, **kw):
        return signal("assertion", name=name, result="PASS", **kw)

    def view(identifier, name, scene=None):
        signal("rum-view-snapshot", evidenceSource="rum-mapper",
               semanticContext=dict(logicalSceneID=scene, screen="home"),
               rumContext=dict(viewID=identifier, sessionID="session", viewName=name, viewActive=True))

    view("launch", "ApplicationLaunch")
    for scene in ["scene-A", "scene-B"]:
        signal("scene-ready", semanticContext=dict(logicalSceneID=scene, nativeSceneID="native-" + scene))
        view(scene, "ProbeHomeView", scene)
    signal("step-started", stepKind="run-view-attribute-batch")
    for scene, suffix in [("scene-A", "a"), ("scene-B", "b")]:
        assertion("attribute-owner-" + suffix, evidenceSource="internal-hook",
                  rumContext=dict(viewID=scene, sessionID="session"))
    assertion("attribute-call-boundary")
    assertion("attribute-calls-enqueued")
    for index, phase in enumerate(a.PHASES):
        context = dict(viewID="scene-A" if index % 2 == 0 else "scene-B", sessionID="session")
        assertion("attribute-payload-" + phase, evidenceSource="rum-mapper", eventID=phase,
                  rumContext=context.copy(), attributeState=a.expected_state(index))
        signal("rum-error", evidenceSource="rum-mapper", name=phase, rumContext=context,
               sourceContext=dict(logicalSceneID="scene-A"),
               error=dict(id=phase, source="custom", type="ProbeAttribute"))
    assertion("attribute-local-owners-verified")
    assertion("attribute-batch-finished")
    records += [dict(type="signal", signal=s) for s in signals]
    records.append(dict(type="semantic-result", runID=run_id,
                        result=dict(scenarioID=a.SCENARIO, state="PASS", matchedExpectationCount=42, issues=[])))
    return records, run_id


def named(records, name):
    return next(r["signal"] for r in records if r.get("signal", {}).get("name") == name)


class AttributeContractTests(unittest.TestCase):
    def test_complete_contract(self):
        records, run = fixture()
        local = a.validate_local(records, run)
        self.assertEqual((local["assertions"], local["checkpoints"], len(local["errors"])), (42, 10, 20))
        self.assertEqual([sum(e["view_id"] == s for e in local["errors"]) for s in ["scene-A", "scene-B"]], [10, 10])

    def test_expected_checkpoint_discriminators(self):
        self.assertEqual(a.expected_state(2)["exp178_shadow"], "swift-a")
        self.assertEqual(a.expected_state(3)["exp178_shadow"], "global-v1")
        self.assertEqual(a.expected_state(6), dict(exp178_shadow="global-v1", exp178_process="global-v1",
                                                 exp178_integer=7, exp178_flag=True, exp178_nested=dict(value="swift-a")))
        self.assertEqual(a.expected_state(8), dict(exp178_shadow="global-v1", exp178_process="global-v1"))
        self.assertEqual(a.expected_state(13)["exp178_nested"], dict(value="objc-b"))
        self.assertEqual(a.expected_state(18), a.expected_state(19))
        self.assertEqual(a.expected_state(19), dict(exp178_shadow="global-v2", exp178_process="global-v2"))

    def test_stale_signal_and_terminal_identity(self):
        for container, field in [("signal", "runID"), ("signal", "scenarioID"), ("signal", "schemaVersion"),
                                 ("terminal", "runID")]:
            records, run = fixture()
            target = named(records, a.PHASES[0]) if container == "signal" else records[-1]
            target[field] = "stale"
            with self.assertRaises(Rejected):
                a.validate_local(records, run)

    def test_manifest_readiness_and_expectations_are_frozen(self):
        for change in ["readiness", "missing", "renamed"]:
            records, run = fixture()
            scenario = records[0]["manifest"]["scenario"]
            if change == "readiness":
                scenario["steps"].append(dict(kind="wait-for-scene-ready", scene="scene-B"))
            elif change == "missing":
                scenario["completionConditions"].pop()
            else:
                scenario["steps"][-1]["kind"] = "old-batch"
            with self.assertRaises(Rejected):
                a.validate_local(records, run)

    def test_wrong_owner_session_source_and_payload(self):
        for container, field, value in [("rumContext", "viewID", "scene-B"), ("rumContext", "sessionID", "other"),
                                        ("sourceContext", "logicalSceneID", "scene-B"), ("error", "source", "network"),
                                        ("error", "type", "wrong"), ("error", "isCrash", True)]:
            records, run = fixture()
            named(records, a.PHASES[0])[container][field] = value
            with self.assertRaises(Rejected):
                a.validate_local(records, run)

    def test_payload_snapshot_bound_to_exact_event_and_mapper(self):
        for field, value in [("eventID", "other"), ("evidenceSource", "probe"), ("result", "FAIL"),
                             ("rumContext", dict(viewID="scene-B", sessionID="session"))]:
            records, run = fixture()
            named(records, "attribute-payload-" + a.PHASES[0])[field] = value
            with self.assertRaises(Rejected):
                a.validate_local(records, run)

    def test_value_types_and_missing_keys_are_decisive(self):
        for key, value in [("exp178_integer", True), ("exp178_integer", "7"), ("exp178_integer", 8),
                           ("exp178_flag", 1), ("exp178_flag", False), ("exp178_nested", "swift-a"),
                           ("exp178_nested", dict(value="objc-b")), ("exp178_shadow", None)]:
            records, run = fixture()
            named(records, "attribute-payload-" + a.PHASES[4])["attributeState"][key] = value
            with self.assertRaises(Rejected):
                a.validate_local(records, run)

    def test_peer_mutation_and_removed_keys_reject(self):
        for index, key, value in [(3, "exp178_shadow", "swift-a"), (5, "exp178_integer", 7),
                                  (8, "exp178_integer", 7), (17, "exp178_nested", dict(value="objc-b")),
                                  (6, "exp178_shadow", "swift-a"), (19, "exp178_process", "global-v1")]:
            records, run = fixture()
            named(records, "attribute-payload-" + a.PHASES[index])["attributeState"][key] = value
            with self.assertRaises(Rejected):
                a.validate_local(records, run)

    def test_late_guards_and_out_of_order_markers(self):
        for first, second in [("attribute-owner-a", "attribute-local-owners-verified"),
                              ("attribute-call-boundary", "attribute-local-owners-verified"),
                              (a.PHASES[0], a.PHASES[1])]:
            records, run = fixture()
            one, two = named(records, first), named(records, second)
            one["name"], two["name"] = two["name"], one["name"]
            with self.assertRaises(Rejected):
                a.validate_local(records, run)

    def test_ended_or_non_mapper_prerequisite(self):
        for change in ["ended", "non-mapper", "aliased-native"]:
            records, run = fixture()
            homes = [r["signal"] for r in records if r.get("signal", {}).get("kind") == "rum-view-snapshot"]
            if change == "ended":
                homes[1]["rumContext"]["viewActive"] = False
            elif change == "non-mapper":
                homes[1]["evidenceSource"] = "internal-hook"
            else:
                ready = [r["signal"] for r in records if r.get("signal", {}).get("kind") == "scene-ready"]
                ready[1]["semanticContext"]["nativeSceneID"] = ready[0]["semanticContext"]["nativeSceneID"]
            with self.assertRaises(Rejected):
                a.validate_local(records, run)

    def test_missing_extra_and_duplicate_error_id(self):
        for change in ["missing", "extra", "id"]:
            records, run = fixture()
            event = named(records, a.PHASES[0])
            if change == "missing":
                event["kind"] = "unrelated"
            elif change == "extra":
                records.insert(-1, dict(type="signal", signal=copy.deepcopy(event)))
            else:
                event["error"]["id"] = a.PHASES[1]
            with self.assertRaises(Rejected):
                a.validate_local(records, run)

    def test_complete_backend_and_mutations(self):
        records, run = fixture()
        local = a.validate_local(records, run)
        data = {k: [dict(r, run_id=run) for r in local[k]] for k in ["errors", "views"]}
        self.assertEqual(a.validate_backend(local, run, [], data["errors"], data["views"], 0)["error_count"], 20)
        mutations = [("errors", "view_id", "scene-B"), ("errors", "payload_matches", False),
                     ("errors", "is_crash", True), ("errors", "run_id", "restored"), ("views", "run_id", "restored"),
                     ("errors", "attribute_state", dict(exp178_shadow="global-v1", exp178_process="global-v1", exp178_flag=True))]
        for kind, field, value in mutations:
            mutated = copy.deepcopy(data)
            mutated[kind][0][field] = value
            with self.assertRaises(Rejected):
                a.validate_backend(local, run, [], mutated["errors"], mutated["views"], 0)

    def test_backend_independently_rejects_type_coercion_and_removal(self):
        records, run = fixture()
        local = a.validate_local(records, run)
        for index, key, value in [(4, "exp178_integer", True), (4, "exp178_flag", 1),
                                  (8, "exp178_integer", 7), (17, "exp178_nested", dict(value="objc-b"))]:
            data = {k: [dict(copy.deepcopy(r), run_id=run) for r in local[k]] for k in ["errors", "views"]}
            data["errors"][index]["attribute_state"][key] = value
            with self.assertRaises(Rejected):
                a.validate_backend(local, run, [], data["errors"], data["views"], 0)

    def test_backend_whole_inventory(self):
        records, run = fixture()
        local = a.validate_local(records, run)
        for kind in ["errors", "views", "resources", "crashes"]:
            data = {k: [dict(r, run_id=run) for r in local[k]] for k in ["errors", "views"]}
            if kind in data:
                data[kind].append(copy.deepcopy(data[kind][0]))
            with self.assertRaises(Rejected):
                a.validate_backend(local, run, [{}] if kind == "resources" else [],
                                   data["errors"], data["views"], 1 if kind == "crashes" else 0)


if __name__ == "__main__":
    unittest.main()
