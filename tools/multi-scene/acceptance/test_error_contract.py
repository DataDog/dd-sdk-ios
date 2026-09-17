import copy
import json
from pathlib import Path
import unittest
from acceptance_common import Rejected
import error_contract as e


def fixture():
    run_id = "exp177-unit"
    records = [{"type": "manifest", "manifest": dict(runID=run_id, runMode="clean", validationErrors=[],
                scenario=json.loads(Path(__file__).with_name(e.CONTRACT).read_text()))}]
    signals = []

    def signal(kind, **kw):
        s = dict(kind=kind, sequence=len(signals) + 1, runID=run_id, scenarioID=e.SCENARIO,
                 schemaVersion=5, evidenceSource="probe")
        s.update(kw)
        signals.append(s)
        return s

    def assertion(name, context=None):
        kw = dict(name=name, result="PASS")
        if context:
            kw.update(evidenceSource="internal-hook", rumContext=context)
        return signal("assertion", **kw)

    def view(identifier, name, scene=None):
        return signal("rum-view-snapshot", evidenceSource="rum-mapper",
                      semanticContext=dict(logicalSceneID=scene, screen="home"),
                      rumContext=dict(viewID=identifier, sessionID="session", viewName=name, viewActive=True))

    view("launch", "ApplicationLaunch")
    for scene in ["scene-A", "scene-B"]:
        signal("scene-ready", semanticContext=dict(logicalSceneID=scene, nativeSceneID="native-" + scene))
        view(scene, "ProbeHomeView", scene)
    signal("step-started", stepKind="run-current-view-error-batch")
    for scene, suffix in [("scene-A", "a"), ("scene-B", "b")]:
        assertion("error-owner-" + suffix, dict(viewID=scene, sessionID="session"))
    assertion("error-call-boundary")
    assertion("error-calls-enqueued")
    for phase in e.PHASES:
        scene = "scene-B" if phase in e.PEERS else "scene-A"
        assertion("error-payload-" + phase)
        signal("rum-error", evidenceSource="rum-mapper", name=phase,
               rumContext=dict(viewID=scene, sessionID="session", actionIDs=["action-" + scene]),
               sourceContext=dict(logicalSceneID="scene-A"),
               error=dict(id=phase, source="network" if phase == e.RESOURCE else "custom", type=e.error_type(phase),
                          resourceURL="https://error-probe.invalid/" + run_id + "/" + e.RESOURCE if phase == e.RESOURCE else None,
                          resourceStatusCode=0 if phase == e.RESOURCE else None))
    assertion("error-callback-completed")
    for scene, name, count in [("scene-A", e.ACTIONS[0], 7), ("scene-B", e.ACTIONS[1], 2)]:
        signal("rum-action", evidenceSource="rum-mapper", name=name,
               rumContext=dict(viewID=scene, sessionID="session"),
               action=dict(id="action-" + scene, type="tap", target=name, resourceCount=0, errorCount=count))
    assertion("error-local-owners-verified")
    assertion("error-batch-finished")
    records += [dict(type="signal", signal=s) for s in signals]
    records.append(dict(type="semantic-result", runID=run_id,
                        result=dict(scenarioID=e.SCENARIO, state="PASS", matchedExpectationCount=24, issues=[])))
    return records, run_id


def named(records, name):
    return next(r["signal"] for r in records if r.get("signal", {}).get("name") == name)


class ErrorContractTests(unittest.TestCase):
    def test_valid_complete_contract(self):
        records, run = fixture()
        result = e.validate_local(records, run)
        self.assertEqual(result["callbacks"], 1)
        self.assertEqual(len(result["errors"]), 9)
        self.assertEqual([a["error_count"] for a in result["actions"]], [7, 2])

    def test_stale_run_and_scenario(self):
        for key in ["runID", "scenarioID", "schemaVersion"]:
            with self.subTest(key=key):
                records, run = fixture()
                named(records, e.PHASES[0])[key] = "stale"
                with self.assertRaises(Rejected):
                    e.validate_local(records, run)

    def test_consumed_readiness_and_changed_manifest(self):
        for mutate in [lambda c: c["steps"].append(dict(kind="wait-for-scene-ready", scene="scene-B")),
                       lambda c: c["completionConditions"].pop()]:
            records, run = fixture()
            mutate(records[0]["manifest"]["scenario"])
            with self.assertRaises(Rejected):
                e.validate_local(records, run)

    def test_wrong_view_session_action_and_source(self):
        for container, field, value in [("rumContext", "viewID", "scene-B"), ("rumContext", "sessionID", "other"),
                                        ("rumContext", "actionIDs", ["action-scene-B"]),
                                        ("sourceContext", "logicalSceneID", "scene-B")]:
            with self.subTest(field=field):
                records, run = fixture()
                named(records, e.PHASES[0])[container][field] = value
                with self.assertRaises(Rejected):
                    e.validate_local(records, run)

    def test_resource_error_cannot_acquire_peer_owner(self):
        records, run = fixture()
        named(records, e.RESOURCE)["rumContext"] = dict(viewID="scene-B", sessionID="session", actionIDs=["action-scene-B"])
        with self.assertRaises(Rejected):
            e.validate_local(records, run)

    def test_action_count_contamination(self):
        for field, value in [("errorCount", 3), ("resourceCount", 1), ("id", "action-scene-A")]:
            records, run = fixture()
            named(records, e.ACTIONS[1])["action"][field] = value
            with self.assertRaises(Rejected):
                e.validate_local(records, run)

    def test_missing_duplicate_and_early_callback(self):
        for kind in ["missing", "duplicate", "early"]:
            with self.subTest(kind=kind):
                records, run = fixture()
                callback = named(records, "error-callback-completed")
                if kind == "missing":
                    callback["name"] = "absent"
                elif kind == "duplicate":
                    records.insert(-1, dict(type="signal", signal=copy.deepcopy(callback)))
                else:
                    early = next(r["signal"] for r in records if r.get("signal", {}).get("sequence") == 1)
                    old = callback["sequence"]
                    callback["sequence"] = early["sequence"]
                    early["sequence"] = old
                    records[1:-1] = sorted(records[1:-1], key=lambda r: r["signal"]["sequence"])
                with self.assertRaises(Rejected):
                    e.validate_local(records, run)

    def test_late_critical_guard(self):
        records, run = fixture()
        boundary = named(records, "error-call-boundary")
        verified = named(records, "error-local-owners-verified")
        boundary["name"], verified["name"] = verified["name"], boundary["name"]
        with self.assertRaises(Rejected):
            e.validate_local(records, run)

    def test_ended_or_non_mapper_prerequisite(self):
        for change in ["ended", "non-mapper"]:
            records, run = fixture()
            homes = [r["signal"] for r in records if r.get("signal", {}).get("kind") == "rum-view-snapshot"]
            if change == "ended":
                homes[1]["rumContext"]["viewActive"] = False
            else:
                homes[1]["evidenceSource"] = "internal-hook"
            with self.assertRaises(Rejected):
                e.validate_local(records, run)

    def test_wrong_payload_and_false_payload_check(self):
        for change in ["source", "type", "url", "check"]:
            records, run = fixture()
            error = named(records, e.RESOURCE)
            if change == "check":
                named(records, "error-payload-" + e.RESOURCE)["result"] = "FAIL"
            else:
                error["error"][{"url": "resourceURL"}.get(change, change)] = "wrong"
            with self.assertRaises(Rejected):
                e.validate_local(records, run)

    def test_missing_extra_and_non_mapper_error(self):
        for change in ["missing", "extra", "non-mapper"]:
            records, run = fixture()
            event = named(records, e.PHASES[0])
            if change == "missing":
                event["kind"] = "unrelated"
            elif change == "extra":
                records.insert(-1, dict(type="signal", signal=copy.deepcopy(event)))
            else:
                event["evidenceSource"] = "probe"
            with self.assertRaises(Rejected):
                e.validate_local(records, run)

    def test_complete_backend_matches(self):
        records, run = fixture()
        local = e.validate_local(records, run)
        errors, views, actions = [copy.deepcopy(local[k]) for k in ["errors", "views", "actions"]]
        for rows in [errors, views, actions]:
            for row in rows:
                row["run_id"] = run
        result = e.validate_backend(local, run, [], errors, views, actions, 0)
        self.assertEqual(result["error_count"], 9)

    def test_backend_rejects_ownership_payload_counts_and_restored_ids(self):
        records, run = fixture()
        local = e.validate_local(records, run)
        for kind, field, value in [("errors", "view_id", "scene-B"), ("errors", "action_ids", ["action-scene-B"]),
                                   ("errors", "payload_matches", False), ("errors", "error_type", "wrong"),
                                   ("errors", "is_crash", True), ("actions", "error_count", 9),
                                   ("actions", "resource_count", 1), ("views", "run_id", "restored"),
                                   ("errors", "event_id", e.PHASES[1])]:
            with self.subTest(kind=kind, field=field):
                data = {k: [dict(r, run_id=run) for r in local[k]] for k in ["errors", "views", "actions"]}
                data[kind][0][field] = value
                with self.assertRaises(Rejected):
                    e.validate_backend(local, run, [], data["errors"], data["views"], data["actions"], 0)

    def test_backend_requires_whole_inventory(self):
        records, run = fixture()
        local = e.validate_local(records, run)
        for kind in ["errors", "views", "actions", "resources", "crashes"]:
            data = {k: [dict(r, run_id=run) for r in local[k]] for k in ["errors", "views", "actions"]}
            resources, crashes = [], 0
            if kind == "resources":
                resources = [{}]
            elif kind == "crashes":
                crashes = 1
            else:
                data[kind].append(copy.deepcopy(data[kind][0]))
            with self.assertRaises(Rejected):
                e.validate_backend(local, run, resources, data["errors"], data["views"], data["actions"], crashes)


if __name__ == "__main__":
    unittest.main()
