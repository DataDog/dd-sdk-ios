import copy
import json
from pathlib import Path
import unittest
from acceptance_common import Rejected
import log_contract as l

IDS = {name: f"00000000-0000-0000-0000-{i:012d}" for i, name in
       enumerate(["application", "session", "launch", "scene-A", "scene-B", "action-a", "action-b"], 1)}


def fixture():
    run = "exp182-unit"
    records = [dict(type="manifest", manifest=dict(runID=run, runMode="clean", validationErrors=[],
               scenario=json.loads(Path(__file__).with_name(l.CONTRACT).read_text())))]
    signals = []

    def signal(kind, **kw):
        value = dict(kind=kind, sequence=len(signals) + 1, runID=run, scenarioID=l.SCENARIO,
                     schemaVersion=5, evidenceSource="probe")
        value.update(kw)
        signals.append(value)
        return value

    def context(scene):
        suffix = "a" if scene == "scene-A" else "b"
        return dict(viewID=IDS[scene], sessionID=IDS["session"], actionIDs=[IDS["action-" + suffix]])

    def assertion(name, owner=None):
        kw = {} if owner is None else dict(evidenceSource="internal-hook", rumContext=context(owner))
        return signal("assertion", name=name, result="PASS", **kw)

    def view(identifier, name, scene=None):
        return signal("rum-view-snapshot", evidenceSource="rum-mapper",
                      semanticContext=dict(logicalSceneID=scene, screen="home"),
                      rumContext=dict(viewID=IDS[identifier], sessionID=IDS["session"], viewName=name,
                                      viewActive=True, viewDocumentVersion=1))
    view("launch", "ApplicationLaunch")
    for scene in ["scene-A", "scene-B"]:
        signal("scene-ready", semanticContext=dict(logicalSceneID=scene, nativeSceneID="native-" + scene))
        view(scene, "ProbeHomeView", scene)
    signal("step-started", stepKind="run-log-ownership-batch")
    assertion("log-actions-boundary")
    assertion("log-owner-a", "scene-A")
    assertion("log-owner-b", "scene-B")
    assertion("log-representative-before-a", "scene-B")
    assertion("log-call-boundary")
    for i, suffix in enumerate(["a", "b", "fallback"]):
        scene = "scene-A" if suffix == "a" else "scene-B"
        source = "source-less" if suffix == "fallback" else scene
        if suffix == "fallback":
            assertion("log-fallback-empty-handoff")
        assertion("log-emission-" + suffix, scene)
        for status in ["info", "error"]:
            phase = "log-" + status + "-" + suffix
            wire = {"status": status, "message": phase, "service": l.SERVICE,
                    "application_id": IDS["application"], "session_id": IDS["session"], "view.id": IDS[scene],
                    "user_action.id": context(scene)["actionIDs"][0], "probe.run_id": run,
                    "probe.phase": phase, "probe.source_scene": source}
            signal("rum-log", evidenceSource="log-mapper", name=phase,
                   sourceContext=dict(logicalSceneID=source, phase=phase, screen="home"),
                   rumContext=context(scene), log=wire)
        phase = "log-error-" + suffix
        assertion("log-mirror-payload-" + phase)
        error_id = f"00000000-0000-0000-0000-{i + 50:012d}"
        signal("rum-error", evidenceSource="rum-mapper", name="mirror-" + phase, eventID=error_id,
               sourceContext=dict(logicalSceneID=source, phase=phase, screen="home"), rumContext=context(scene),
               error=dict(id=error_id, source="logger", isCrash=False))
    assertion("log-stops-boundary")
    for suffix, scene in [("a", "scene-A"), ("b", "scene-B")]:
        phase = "log-action-" + suffix
        action_id = IDS["action-" + suffix]
        signal("rum-action", evidenceSource="rum-mapper", name=phase, eventID=action_id,
               rumContext=context(scene), sourceContext=dict(logicalSceneID=scene, phase=phase, screen="home"),
               action=dict(id=action_id, type="tap", target=phase, resourceCount=0, errorCount=1 if suffix == "a" else 2))
    assertion("log-local-owners-verified")
    assertion("log-batch-finished")
    records += [dict(type="signal", signal=s) for s in signals]
    records.append(dict(type="semantic-result", runID=run, result=dict(
        scenarioID=l.SCENARIO, state="PASS", matchedExpectationCount=24, issues=[])))
    return records, run


def named(records, name):
    return next(r["signal"] for r in records if r["type"] == "signal" and r["signal"].get("name") == name)


def backend(local, run):
    rows = {k: [dict(v, run_id=run) for v in local[k]] for k in ["logs", "errors", "views", "actions"]}
    for i, row in enumerate(rows["logs"]):
        row.update(log_id="backend-" + str(i), leaked_internal_attribute=False)
    for row in rows["errors"]:
        row["is_crash"] = False
    return rows


def check_backend(local, run, rows):
    return l.validate_backend(local, run, rows["logs"], rows["errors"], rows["views"], rows["actions"], [], 0)


class LogContractTests(unittest.TestCase):
    def test_exact_native_and_backend_owner_inventory(self):
        records, run = fixture()
        local = l.validate_local(records, run)
        self.assertEqual(local["assertions"], 24)
        self.assertEqual(check_backend(local, run, backend(local, run))["state"], "PASS")

    def test_changed_fixture_or_consumed_readiness_rejected(self):
        for mode in ["readiness", "expectation"]:
            records, run = fixture()
            scenario = records[0]["manifest"]["scenario"]
            if mode == "readiness":
                scenario["steps"].append(dict(kind="wait-for-scene-ready", scene="scene-B"))
            else:
                scenario["completionConditions"].pop()
            with self.assertRaises(Rejected):
                l.validate_local(records, run)

    def test_stale_identity_and_mapper_rejected(self):
        for key, value in [("runID", "restored"), ("scenarioID", "old"), ("schemaVersion", 4), ("evidenceSource", "probe")]:
            records, run = fixture()
            named(records, "log-info-a")[key] = value
            with self.assertRaises(Rejected):
                l.validate_local(records, run)

    def test_each_guard_after_its_critical_boundary_rejected(self):
        pairs = [("log-owner-a", "log-call-boundary"), ("log-representative-before-a", "log-call-boundary"),
                 ("log-emission-a", "log-info-a"), ("log-emission-b", "log-info-b"),
                 ("log-fallback-empty-handoff", "log-emission-fallback"),
                 ("log-stops-boundary", "log-action-a"), ("log-mirror-payload-log-error-a", "mirror-log-error-a")]
        for guard, after in pairs:
            records, run = fixture()
            a = records.index(next(r for r in records if r.get("signal", {}).get("name") == guard))
            b = records.index(next(r for r in records if r.get("signal", {}).get("name") == after))
            records[a], records[b] = records[b], records[a]
            for i, r in enumerate(r for r in records if r["type"] == "signal"):
                r["signal"]["sequence"] = i + 1
            with self.assertRaises(Rejected, msg=guard):
                l.validate_local(records, run)

    def test_early_mirror_or_action_completion_rejected(self):
        for name in ["mirror-log-error-a", "log-action-a"]:
            records, run = fixture()
            row = next(r for r in records if r.get("signal", {}).get("name") == name)
            records.remove(row)
            records.insert(2, row)
            for i, r in enumerate(r for r in records if r["type"] == "signal"):
                r["signal"]["sequence"] = i + 1
            with self.assertRaises(Rejected):
                l.validate_local(records, run)

    def test_wrong_live_and_encoded_owners_rejected(self):
        for name, field in [("log-info-a", "viewID"), ("mirror-log-error-a", "actionIDs"),
                            ("log-owner-a", "viewID"), ("log-action-a", "actionIDs"),
                            ("log-representative-before-a", "viewID")]:
            records, run = fixture()
            named(records, name)["rumContext"][field] = [IDS["action-b"]] if field == "actionIDs" else IDS["scene-A" if name == "log-representative-before-a" else "scene-B"]
            with self.assertRaises(Rejected, msg=name):
                l.validate_local(records, run)

    def test_malformed_wire_fields_and_invented_log_ids_rejected(self):
        for key, value in [("view.id", IDS["scene-B"]), ("user_action.id", IDS["action-b"]),
                           ("probe.run_id", "old"), ("status", "error"), ("message", "uncontrolled"),
                           ("application_id", True), ("_dd.internal.rum.error.context_captured", True)]:
            records, run = fixture()
            named(records, "log-info-a")["log"][key] = value
            with self.assertRaises(Rejected, msg=key):
                l.validate_local(records, run)
        records, run = fixture()
        named(records, "log-info-a")["eventID"] = "fabricated"
        with self.assertRaises(Rejected):
            l.validate_local(records, run)

    def test_missing_log_mirror_action_or_payload_check_rejected(self):
        for name in ["log-info-b", "mirror-log-error-b", "log-action-b", "log-mirror-payload-log-error-b"]:
            records, run = fixture()
            records[:] = [r for r in records if r.get("signal", {}).get("name") != name]
            for i, r in enumerate(r for r in records if r["type"] == "signal"):
                r["signal"]["sequence"] = i + 1
            with self.assertRaises(Rejected):
                l.validate_local(records, run)

    def test_wrong_action_counts_and_mirror_source_rejected(self):
        for name, field, key, value in [
            ("log-action-a", "action", "errorCount", 2), ("log-action-b", "action", "resourceCount", 1),
            ("mirror-log-error-a", "error", "source", "custom"), ("mirror-log-error-a", "error", "isCrash", True),
        ]:
            records, run = fixture()
            named(records, name)[field][key] = value
            with self.assertRaises(Rejected):
                l.validate_local(records, run)

    def test_backend_missing_extra_duplicate_and_wrong_owner_rejected(self):
        records, run = fixture()
        local = l.validate_local(records, run)
        for kind in ["logs", "errors", "actions", "views"]:
            for mode in ["missing", "extra", "duplicate", "owner", "run"]:
                rows = backend(local, run)
                if mode == "missing":
                    rows[kind].pop()
                elif mode == "extra":
                    rows[kind].append(copy.deepcopy(rows[kind][0]))
                elif mode == "duplicate":
                    rows[kind][1] = copy.deepcopy(rows[kind][0])
                else:
                    rows[kind][0]["view_id" if mode == "owner" else "run_id"] = "wrong"
                with self.assertRaises(Rejected, msg=(kind, mode)):
                    check_backend(local, run, rows)

    def test_backend_metadata_and_log_record_identity_required(self):
        records, run = fixture()
        local = l.validate_local(records, run)
        for kind, key, value in [("logs", "log_id", None), ("logs", "leaked_internal_attribute", True),
                                ("errors", "leaked_internal_attribute", True),
                                ("errors", "payload_matches", False), ("errors", "action_ids", [])]:
            rows = backend(local, run)
            rows[kind][0][key] = value
            with self.assertRaises(Rejected):
                check_backend(local, run, rows)

    def test_backend_resource_crash_or_partial_mirror_is_failure(self):
        records, run = fixture()
        local = l.validate_local(records, run)
        rows = backend(local, run)
        for resources, crashes in [([{}], 0), ([], 1)]:
            with self.assertRaises(Rejected):
                l.validate_backend(local, run, rows["logs"], rows["errors"], rows["views"], rows["actions"], resources, crashes)


if __name__ == "__main__":
    unittest.main()
