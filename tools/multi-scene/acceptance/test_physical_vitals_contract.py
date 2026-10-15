"""Synthetic unit controls for the separately declared one-scene hardware sample."""
import copy
import json
from pathlib import Path
import unittest
from acceptance_common import Rejected
import vitals_contract as v
from test_vitals_contract import fixture, named, snapshots, uid


def physical_fixture():
    records, run = fixture()
    ack = named(records, "vitals-a-samples-acknowledged")
    result = copy.deepcopy(records[:next(i for i, r in enumerate(records) if r.get("signal") is ack) + 1])
    final = copy.deepcopy(next(s for s in snapshots(records)
                               if s["rumContext"]["viewID"] == uid(2) and not s["rumContext"]["viewActive"]))
    stop = copy.deepcopy(named(records, "vitals-stop-boundary"))
    stop["rumContext"] = dict(sessionID=uid(1), viewID=uid(2))
    tail = [stop, final, named(records, "vitals-final-a"),
            named(records, "vitals-inventory-verified"), named(records, "vitals-a-complete")]
    result += [dict(type="signal", signal=copy.deepcopy(s)) for s in tail]
    result[0]["manifest"]["scenario"] = json.loads(Path(__file__).with_name(v.PHYSICAL_CONTRACT).read_text())
    for index, row in enumerate(result[1:], 1):
        row["signal"].update(sequence=index, timestampMilliseconds=90000+index, scenarioID=v.PHYSICAL_SCENARIO)
    result.append(dict(type="semantic-result", runID=run, result=dict(
        scenarioID=v.PHYSICAL_SCENARIO, state="PASS", issues=[], matchedExpectationCount=17)))
    return result, run


class PhysicalVitalsTests(unittest.TestCase):
    def setUp(self):
        self.records, self.run = physical_fixture()
        self.local = v.validate_physical_local(self.records, self.run)
        self.rows = copy.deepcopy(self.local["views"])

    def test_exact_single_scene_sample_and_backend_pass(self):
        self.assertEqual(self.local["assertions"], 17)
        self.assertEqual(len(self.local["native_scenes"]), 1)
        self.assertEqual(v.validate_backend(self.local, self.rows, [], [], [], 0, 0)["view_count"], 2)
        self.assertFalse(self.local["physical_device_claimed"])

    def test_serial_and_physical_contracts_cannot_replace_each_other(self):
        with self.assertRaises(Rejected):
            v.validate_local(self.records, self.run)
        records, run = fixture()
        with self.assertRaises(Rejected):
            v.validate_physical_local(records, run)
        local = copy.deepcopy(self.local)
        del local["single_scene_physical_sample"]
        with self.assertRaises(Rejected):
            v.validate_views(local, self.rows)

    def test_critical_identity_readiness_sampling_and_final_boundaries(self):
        mutations = [
            "stale_run", "stale_source_run", "extra_scene", "wrong_native_owner",
            "missing_guard", "duplicate_guard", "unacknowledged_guard", "late_stop",
            "late_final_mapper", "missing_samples", "early_sample_end", "wrong_final_values",
            "active_final", "wrong_session", "wrong_scene", "extra_view", "nonzero_counts",
            "unrelated_telemetry", "wrong_count", "wrong_stop_owner",
        ]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                r = copy.deepcopy(self.records)
                views = snapshots(r)
                if mutation == "stale_run": r[0]["manifest"]["runID"] = "old"
                elif mutation == "stale_source_run": views[2]["vitals"]["originalRunID"] = "old"
                elif mutation == "extra_scene":
                    ready = copy.deepcopy(next(x for x in r if x.get("signal", {}).get("kind") == "scene-ready"))
                    ready["signal"]["semanticContext"].update(logicalSceneID="scene-B", nativeSceneID="native-b")
                    r.insert(-1, ready)
                elif mutation == "wrong_native_owner": named(r, "vitals-a-owner")["sourceContext"]["nativeSceneID"] = "other"
                elif mutation == "missing_guard": named(r, "vitals-final-a")["name"] = "missing"
                elif mutation == "duplicate_guard": named(r, "vitals-final-a")["name"] = "vitals-a-owner"
                elif mutation == "unacknowledged_guard": named(r, "vitals-a-samples-acknowledged")["result"] = None
                elif mutation == "late_stop":
                    stop, final = named(r, "vitals-stop-boundary"), named(r, "vitals-final-a")
                    stop["name"], final["name"] = "vitals-final-a", "vitals-stop-boundary"
                elif mutation == "late_final_mapper":
                    item = next(x for x in r if x.get("signal") is views[-1])
                    r.remove(item)
                    r.insert(-1, item)
                elif mutation == "missing_samples": views[2]["vitals"].pop("cpuTicks")
                elif mutation == "early_sample_end": views[2]["rumContext"]["viewActive"] = False
                elif mutation == "wrong_final_values": named(r, "vitals-final-a")["vitals"]["memoryMax"] = 9999
                elif mutation == "active_final": views[-1]["rumContext"]["viewActive"] = True
                elif mutation == "wrong_session": views[-1]["rumContext"]["sessionID"] = uid(99)
                elif mutation == "wrong_scene": views[-1]["semanticContext"]["logicalSceneID"] = "scene-B"
                elif mutation == "extra_view": views[-1]["rumContext"]["viewID"] = uid(99)
                elif mutation == "nonzero_counts": views[-1]["vitals"]["counters"]["errors"] = 1
                elif mutation == "unrelated_telemetry": views[0]["kind"] = "rum-resource"
                elif mutation == "wrong_count": r[-1]["result"]["matchedExpectationCount"] = 30
                elif mutation == "wrong_stop_owner": named(r, "vitals-stop-boundary")["rumContext"] = dict(sessionID=uid(1), viewID=uid(99))
                for index, row in enumerate(r[1:-1], 1):
                    row["signal"]["sequence"] = index
                with self.assertRaises(Rejected):
                    v.validate_physical_local(r, self.run)

    def test_complete_backend_inventory_and_exact_metric_rules(self):
        variants = [self.rows[:-1], self.rows+[self.rows[0]], [self.rows[0], self.rows[0]]]
        for rows in variants:
            with self.assertRaises(Rejected):
                v.validate_views(self.local, rows)
        for field, value in [("session_id", uid(99)), ("view_id", uid(99)),
                             ("run_id", "old"), ("is_active", True)]:
            rows = copy.deepcopy(self.rows)
            rows[1][field] = value
            with self.assertRaises(Rejected):
                v.validate_views(self.local, rows)
        for field, value in [("cpuTicks", 0), ("memoryAverage", "2048"),
                             ("refreshRateAverage", float("nan")), ("timeSpentNanoseconds", 3_000_000_001)]:
            rows = copy.deepcopy(self.rows)
            rows[1]["metrics"][field] = value
            with self.assertRaises(Rejected):
                v.validate_views(self.local, rows)
        for row in self.rows:
            row["metrics"]["slowFrames"] = None
            row["slow_frames_present"] = False
        self.assertEqual(v.validate_backend(self.local, self.rows, [], [], [], 0, 0)["omitted_empty_slow_frame_arrays"], 2)


if __name__ == "__main__":
    unittest.main()
