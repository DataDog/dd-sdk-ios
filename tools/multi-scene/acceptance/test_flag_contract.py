import copy
import json
from pathlib import Path
import unittest
from acceptance_common import Rejected
import flag_contract as t


def state_for(index):
    checkpoint, is_a = index // 2, index % 2 == 0
    a_values = [{}, {t.SHARED: True}] + [{t.SHARED: 7}] * 5 + [{t.SHARED: 7, t.FINAL_A: "A-final"}]
    b_values = [{}] * 3 + [{t.SHARED: "B"}] + [{t.SHARED: dict(enabled=False, weights=[2, 4])}] * 3
    b_values += [{t.SHARED: dict(enabled=False, weights=[2, 4]), t.FINAL_B: "B-final"}]
    values = copy.deepcopy((a_values if is_a else b_values)[checkpoint])
    build = (dict(min=32.0, max=52.0, average=42.0) if is_a else dict(min=20.0, max=60.0, average=40.0))
    present = checkpoint >= (5 if is_a else 6)
    return dict(flags=values, build=build if present else None, fbc=(101000000 if is_a else 202000000) if present else None,
                leakedInternalAttribute=False)


def fixture():
    run = "exp180-unit"
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
                      flagState=state or dict(flags={}, build=None, fbc=None, leakedInternalAttribute=False),
                      rumContext=dict(viewID=identifier, sessionID="session", viewName=name,
                                      viewActive=True, viewDocumentVersion=version))

    view("launch", "ApplicationLaunch")
    for scene in ["scene-A", "scene-B"]:
        signal("scene-ready", semanticContext=dict(logicalSceneID=scene, nativeSceneID="native-" + scene))
        view(scene, "ProbeHomeView", scene)
    signal("step-started", stepKind="run-view-flag-batch")
    for scene, suffix in [("scene-A", "a"), ("scene-B", "b")]:
        assertion("flag-owner-" + suffix, evidenceSource="internal-hook",
                  rumContext=dict(viewID=scene, sessionID="session"))
    assertion("flag-call-boundary")
    assertion("flag-calls-enqueued")
    for index, phase in enumerate(t.PHASES):
        scene = "scene-A" if index % 2 == 0 else "scene-B"
        snapshot = view(scene, "ProbeHomeView", scene, state_for(index), index + 2)
        context = copy.deepcopy(snapshot["rumContext"])
        assertion("flag-payload-" + phase, evidenceSource="rum-mapper", eventID=phase,
                  rumContext=context, acknowledgedSignalSequence=snapshot["sequence"], flagState=state_for(index))
        signal("rum-error", evidenceSource="rum-mapper", name=phase,
               rumContext=dict(viewID=scene, sessionID="session"),
               sourceContext=dict(logicalSceneID="scene-A"),
               error=dict(id=phase, source="custom", type="ProbeFlag"))
    assertion("flag-local-owners-verified")
    assertion("flag-batch-finished")
    records += [dict(type="signal", signal=s) for s in signals]
    records.append(dict(type="semantic-result", runID=run,
                        result=dict(scenarioID=t.SCENARIO, state="PASS", matchedExpectationCount=34, issues=[])))
    return records, run


def named(records, name):
    return next(r["signal"] for r in records if r.get("signal", {}).get("name") == name)


def mutate_state(records, index, change):
    check = named(records, "flag-payload-" + t.PHASES[index])
    change(check["flagState"])
    snapshot = next(r["signal"] for r in records if r.get("signal", {}).get("sequence") == check["acknowledgedSignalSequence"])
    snapshot["flagState"] = copy.deepcopy(check["flagState"])


class FlagContractTests(unittest.TestCase):
    def test_golden_local_and_backend_contract(self):
        records, run = fixture()
        local = t.validate_local(records, run)
        self.assertEqual((local["assertions"], local["checkpoints"], len(local["errors"])), (34, 8, 16))
        self.assertEqual(local["views"][-2]["flag_state"], state_for(14))
        self.assertEqual(local["views"][-1]["flag_state"], state_for(15))
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

    def test_boolean_integer_string_and_nested_replacements(self):
        for index, value in [(2, 1), (2, "true"), (4, True), (4, 7.0), (4, "7"), (7, 7),
                             (9, "B"), (9, dict(enabled=0, weights=[2, 4])),
                             (9, dict(enabled=False, weights=[True, 4])),
                             (9, dict(enabled=False, weights=[2.0, 4])),
                             (9, dict(enabled=False, weights=[4, 2])),
                             (9, dict(enabled=False, weights=[2, 4], extra=0))]:
            records, run = fixture()
            mutate_state(records, index, lambda s: s["flags"].update({t.SHARED: value}))
            with self.assertRaises(Rejected):
                t.validate_local(records, run)

    def test_build_aggregates_fbc_and_internal_key_discriminators(self):
        for index, change in [(10, lambda s: s["build"].update(average=32)),
                              (10, lambda s: s["build"].update(min=52)),
                              (13, lambda s: s["build"].update(max=52)),
                              (10, lambda s: s.update(build=None)),
                              (10, lambda s: s.update(fbc=202000000)),
                              (13, lambda s: s.update(fbc=None)),
                              (10, lambda s: s.update(fbc=True)),
                              (10, lambda s: s.update(fbc=101000000.0)),
                              (13, lambda s: s.update(leakedInternalAttribute=True)),
                              (13, lambda s: s.pop("leakedInternalAttribute")),
                              (11, lambda s: s.update(build=dict(min=20, max=60, average=40)))]:
            records, run = fixture()
            mutate_state(records, index, change)
            with self.assertRaises(Rejected):
                t.validate_local(records, run)
        for value in [True, "32", 0, -1, float("nan"), float("inf")]:
            records, run = fixture()
            mutate_state(records, 10, lambda s: s["build"].update(min=value))
            with self.assertRaises(Rejected):
                t.validate_local(records, run)

    def test_peer_mutation_missing_and_foreign_final_keys(self):
        for index, change in [(3, lambda s: s["flags"].update({t.SHARED: True})),
                              (8, lambda s: s["flags"].update({t.SHARED: "B"})),
                              (14, lambda s: s["flags"].pop(t.FINAL_A)),
                              (14, lambda s: s["flags"].update({t.FINAL_B: "B-final"})),
                              (15, lambda s: s["flags"].update({t.FINAL_B: "A-final"}))]:
            records, run = fixture()
            mutate_state(records, index, change)
            with self.assertRaises(Rejected):
                t.validate_local(records, run)

    def test_detached_snapshot_wrong_version_and_state(self):
        for key, value in [("acknowledgedSignalSequence", 1), ("eventID", "other"),
                           ("flagState", dict(flags={}, build=None, fbc=999, leakedInternalAttribute=False)),
                           ("rumContext", dict(viewID="scene-A", sessionID="session", viewDocumentVersion=999))]:
            records, run = fixture()
            named(records, "flag-payload-" + t.PHASES[2])[key] = value
            with self.assertRaises(Rejected):
                t.validate_local(records, run)

    def test_late_guard_and_late_snapshot_binding(self):
        for late in ["guard", "snapshot"]:
            records, run = fixture()
            if late == "guard":
                one, two = named(records, "flag-owner-a"), named(records, "flag-local-owners-verified")
                one["name"], two["name"] = two["name"], one["name"]
            else:
                named(records, "flag-payload-" + t.PHASES[0])["acknowledgedSignalSequence"] = named(records, t.PHASES[-1])["sequence"]
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
        for kind, index, key, value in [("views", 1, "flag_state", state_for(12)),
                                       ("views", 1, "flag_state", dict(flags={t.SHARED: True, t.FINAL_A: "A-final"}, build=None, fbc=None, leakedInternalAttribute=False)),
                                       ("views", 1, "run_id", "restored"), ("errors", 0, "view_id", "scene-B"),
                                       ("errors", 2, "flags", {t.SHARED: 1}),
                                       ("errors", 9, "flags", {t.SHARED: dict(enabled=0, weights=[2, 4])}),
                                       ("errors", 15, "leaked_internal_attribute", True),
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
