import copy
import json
from pathlib import Path
import unittest
from acceptance_common import Rejected
import timing_contract as t


def state_for(index):
    checkpoint, is_a = index // 2, index % 2 == 0
    if checkpoint < (1 if is_a else 4):
        return dict(timings={}, loading=None)
    timing = (100 if checkpoint == 1 else 200) if is_a else (400 if checkpoint == 4 else 500)
    loading = (120 if checkpoint < 3 else 300) if is_a else (420 if checkpoint < 6 else 600)
    timings = {t.SHARED: timing}
    if checkpoint == 7:
        timings[t.FINAL_A if is_a else t.FINAL_B] = 700 if is_a else 750
    return dict(timings=timings, loading=loading)


def fixture():
    run = "exp179-unit"
    records = [dict(type="manifest", manifest=dict(runID=run, runMode="clean", validationErrors=[],
               scenario=json.loads(Path(__file__).with_name(t.CONTRACT).read_text())))]
    signals = []

    def signal(kind, **kw):
        value = dict(kind=kind, sequence=len(signals) + 1, runID=run, scenarioID=t.SCENARIO,
                     schemaVersion=5, evidenceSource="probe")
        value.update(kw)
        signals.append(value)
        return value

    def assertion(name, **kw):
        return signal("assertion", name=name, result="PASS", **kw)

    def view(identifier, name, scene=None, state=None, version=1):
        return signal("rum-view-snapshot", evidenceSource="rum-mapper",
                      semanticContext=dict(logicalSceneID=scene, screen="home"),
                      timingState=state or dict(timings={}, loading=None),
                      rumContext=dict(viewID=identifier, sessionID="session", viewName=name,
                                      viewActive=True, viewDocumentVersion=version))

    view("launch", "ApplicationLaunch")
    for scene in ["scene-A", "scene-B"]:
        signal("scene-ready", semanticContext=dict(logicalSceneID=scene, nativeSceneID="native-" + scene))
        view(scene, "ProbeHomeView", scene)
    signal("step-started", stepKind="run-view-timing-batch")
    for scene, suffix in [("scene-A", "a"), ("scene-B", "b")]:
        assertion("timing-owner-" + suffix, evidenceSource="internal-hook",
                  rumContext=dict(viewID=scene, sessionID="session"))
    assertion("timing-call-boundary")
    assertion("timing-calls-enqueued")
    for index, phase in enumerate(t.PHASES):
        scene = "scene-A" if index % 2 == 0 else "scene-B"
        snapshot = view(scene, "ProbeHomeView", scene, state_for(index), index + 2)
        context = copy.deepcopy(snapshot["rumContext"])
        assertion("timing-payload-" + phase, evidenceSource="rum-mapper", eventID=phase,
                  rumContext=context, acknowledgedSignalSequence=snapshot["sequence"], timingState=state_for(index))
        signal("rum-error", evidenceSource="rum-mapper", name=phase,
               rumContext=dict(viewID=scene, sessionID="session"),
               sourceContext=dict(logicalSceneID="scene-A"),
               error=dict(id=phase, source="custom", type="ProbeTiming"))
    assertion("timing-local-owners-verified")
    assertion("timing-batch-finished")
    records += [dict(type="signal", signal=s) for s in signals]
    records.append(dict(type="semantic-result", runID=run,
                        result=dict(scenarioID=t.SCENARIO, state="PASS", matchedExpectationCount=34, issues=[])))
    return records, run


def named(records, name):
    return next(r["signal"] for r in records if r.get("signal", {}).get("name") == name)


def mutate_state(records, index, change):
    check = named(records, "timing-payload-" + t.PHASES[index])
    change(check["timingState"])
    snapshot = next(r["signal"] for r in records if r.get("signal", {}).get("sequence") == check["acknowledgedSignalSequence"])
    snapshot["timingState"] = copy.deepcopy(check["timingState"])


class TimingContractTests(unittest.TestCase):
    def test_golden_local_and_backend_contract(self):
        records, run = fixture()
        local = t.validate_local(records, run)
        self.assertEqual((local["assertions"], local["checkpoints"], len(local["errors"])), (34, 8, 16))
        self.assertEqual(local["views"][-2]["timing_state"], state_for(14))
        self.assertEqual(local["views"][-1]["timing_state"], state_for(15))
        data = {k: [dict(r, run_id=run) for r in local[k]] for k in ["errors", "views"]}
        self.assertEqual(t.validate_backend(local, run, [], data["errors"], data["views"], 0)["error_count"], 16)

    def test_changed_manifest_and_consumed_readiness(self):
        for change in ["readiness", "missing"]:
            records, run = fixture()
            scenario = records[0]["manifest"]["scenario"]
            if change == "readiness":
                scenario["steps"].append(dict(kind="wait-for-scene-ready", scene="scene-B"))
            else:
                scenario["completionConditions"].pop()
            with self.assertRaises(Rejected):
                t.validate_local(records, run)

    def test_stale_identity_and_non_mapper_events(self):
        for key, value in [("runID", "stale"), ("scenarioID", "old"), ("schemaVersion", 4), ("evidenceSource", "probe")]:
            records, run = fixture()
            named(records, t.PHASES[0])[key] = value
            with self.assertRaises(Rejected):
                t.validate_local(records, run)

    def test_wrong_owner_source_session_or_crash(self):
        for container, key, value in [("rumContext", "viewID", "scene-B"), ("rumContext", "sessionID", "other"),
                                      ("sourceContext", "logicalSceneID", "scene-B"), ("error", "isCrash", True)]:
            records, run = fixture()
            named(records, t.PHASES[0])[container][key] = value
            with self.assertRaises(Rejected):
                t.validate_local(records, run)

    def test_equal_reversed_and_noninteger_timing_replacements(self):
        for value in [100, 99, 0, -1, True, "200", 200.5, dict(value=200)]:
            records, run = fixture()
            mutate_state(records, 4, lambda s: s["timings"].update({t.SHARED: value}))
            with self.assertRaises(Rejected):
                t.validate_local(records, run)

    def test_loading_overwrite_false_and_true_discriminators(self):
        for index, value in [(4, 121), (4, None), (6, 120), (6, 119), (10, 421), (12, 420),
                             (2, True), (2, "120"), (2, 0)]:
            records, run = fixture()
            mutate_state(records, index, lambda s: s.update(loading=value))
            with self.assertRaises(Rejected):
                t.validate_local(records, run)

    def test_peer_mutation_missing_and_foreign_final_keys(self):
        for index, change in [(3, lambda s: s.update(loading=1)),
                               (8, lambda s: s["timings"].update({t.SHARED: 201})),
                               (14, lambda s: s["timings"].pop(t.FINAL_A)),
                               (14, lambda s: s["timings"].update({t.FINAL_B: 800})),
                               (15, lambda s: s["timings"].update({t.FINAL_B: 500}))]:
            records, run = fixture()
            mutate_state(records, index, change)
            with self.assertRaises(Rejected):
                t.validate_local(records, run)

    def test_detached_snapshot_wrong_version_and_state(self):
        for key, value in [("acknowledgedSignalSequence", 1), ("eventID", "other"),
                           ("timingState", dict(timings={}, loading=999)),
                           ("rumContext", dict(viewID="scene-A", sessionID="session", viewDocumentVersion=999))]:
            records, run = fixture()
            named(records, "timing-payload-" + t.PHASES[2])[key] = value
            with self.assertRaises(Rejected):
                t.validate_local(records, run)

    def test_late_guard_and_late_snapshot_binding(self):
        for late in ["guard", "snapshot"]:
            records, run = fixture()
            if late == "guard":
                one, two = named(records, "timing-owner-a"), named(records, "timing-local-owners-verified")
                one["name"], two["name"] = two["name"], one["name"]
            else:
                named(records, "timing-payload-" + t.PHASES[0])["acknowledgedSignalSequence"] = named(records, t.PHASES[-1])["sequence"]
            with self.assertRaises(Rejected):
                t.validate_local(records, run)

    def test_inactive_home_and_aliased_native_scenes(self):
        for kind in ["inactive", "aliased"]:
            records, run = fixture()
            signals = [r["signal"] for r in records if "signal" in r]
            if kind == "inactive":
                next(s for s in signals if s["kind"] == "rum-view-snapshot" and s["rumContext"]["viewID"] == "scene-A")["rumContext"]["viewActive"] = False
            else:
                ready = [s for s in signals if s["kind"] == "scene-ready"]
                ready[1]["semanticContext"]["nativeSceneID"] = ready[0]["semanticContext"]["nativeSceneID"]
            with self.assertRaises(Rejected):
                t.validate_local(records, run)

    def test_missing_duplicate_or_reordered_markers(self):
        for kind in ["missing", "duplicate", "reordered"]:
            records, run = fixture()
            first, second = named(records, t.PHASES[0]), named(records, t.PHASES[1])
            if kind == "missing":
                first["kind"] = "unrelated"
            elif kind == "duplicate":
                records.insert(-1, dict(type="signal", signal=copy.deepcopy(first)))
            else:
                first["name"], second["name"] = second["name"], first["name"]
            with self.assertRaises(Rejected):
                t.validate_local(records, run)

    def test_backend_final_values_types_and_restored_run_ids(self):
        records, run = fixture()
        local = t.validate_local(records, run)
        for kind, index, key, value in [("views", 1, "timing_state", state_for(12)),
                                       ("views", 1, "timing_state", dict(timings={t.SHARED: True, t.FINAL_A: 700}, loading=300)),
                                       ("views", 1, "run_id", "restored"), ("errors", 0, "view_id", "scene-B"),
                                       ("errors", 0, "payload_matches", False), ("errors", 0, "run_id", "restored")]:
            data = {k: [dict(copy.deepcopy(r), run_id=run) for r in local[k]] for k in ["errors", "views"]}
            data[kind][index][key] = value
            with self.assertRaises(Rejected):
                t.validate_backend(local, run, [], data["errors"], data["views"], 0)

    def test_backend_requires_complete_inventory_and_zero_crashes(self):
        records, run = fixture()
        local = t.validate_local(records, run)
        for kind in ["errors", "views", "resources", "crashes"]:
            data = {k: [dict(r, run_id=run) for r in local[k]] for k in ["errors", "views"]}
            if kind in data:
                data[kind].append(copy.deepcopy(data[kind][0]))
            with self.assertRaises(Rejected):
                t.validate_backend(local, run, [{}] if kind == "resources" else [],
                                   data["errors"], data["views"], 1 if kind == "crashes" else 0)


if __name__ == "__main__":
    unittest.main()
