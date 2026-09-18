import copy
import json
from pathlib import Path
import unittest
from acceptance_common import Rejected
import vitals_contract as v


def uid(number):
    return f"00000000-0000-0000-0000-{number:012d}"


def fixture():
    run, sid = "exp186-unit", uid(1)
    scenario = json.loads(Path(__file__).with_name(v.CONTRACT).read_text())
    records = [dict(type="manifest", manifest=dict(runID=run, runMode="clean", validationErrors=[], scenario=scenario))]
    signals, owners = [], {"a": dict(sessionID=sid, viewID=uid(2)), "b": dict(sessionID=sid, viewID=uid(3))}

    def add(kind, **kwargs):
        signal = dict(kind=kind, evidenceSource="internal-hook", schemaVersion=5, sequence=len(signals) + 1,
                      runID=run, scenarioID=v.SCENARIO, timestampMilliseconds=90000 + len(signals), **kwargs)
        signals.append(signal)
        records.append(dict(type="signal", signal=signal))
        return signal

    def guard(name, **kwargs):
        return add("assertion", name=name, result="PASS", **kwargs)

    def view(label, time, active=True, sampled=False):
        context = owners[label] if label else dict(sessionID=sid, viewID=uid(4))
        observation = dict(timeSpentNanoseconds=time, nativeSource="ios", originalRunID=run if label else None,
                           counters=copy.deepcopy(v.ZERO), slowFrames=[], slowFramesRate=None)
        if sampled:
            observation.update(cpuTicks=40.0, cpuRate=40.0 / (time / 1e9),
                               memoryAverage=2048.0, memoryMax=3072.0,
                               refreshRateAverage=45.0, refreshRateMin=30.0, slowFramesRate=0.0)
        value = add("rum-view-snapshot", rumContext=dict(
            context, viewName="ProbeHomeView" if label else "ApplicationLaunch", viewActive=active,
            viewTimeSpentNanoseconds=time), semanticContext=dict(logicalSceneID="scene-" + label.upper()) if label else {},
                    vitals=observation)
        value["evidenceSource"] = "rum-mapper"
        return value

    def ready(label):
        s = add("scene-ready", semanticContext=dict(logicalSceneID="scene-" + label.upper(), nativeSceneID="native-" + label),
                scenePhase="ready", activationState="foreground-active")
        s["evidenceSource"] = "probe"

    def step(kind):
        add("step-started", stepKind=kind)

    def begin(label):
        owner = owners[label]
        guard("vitals-" + label + "-owner", rumContext=owner,
              sourceContext=dict(logicalSceneID="scene-" + label.upper(), nativeSceneID="native-" + label, screen="home"))
        return owner

    s = add("rum-session-started", rumContext=dict(sessionID=sid, sessionDiscarded=False))
    s["evidenceSource"] = "rum-mapper"
    view(None, 500_000_000, active=False)
    ready("a")
    view("a", 500_000_000)
    step("wait-for-scene-ready")
    step("wait-for-signal")
    step("sample-shared-vitals")
    guard("vitals-configuration", vitals=dict(configuration=v.CONFIGURATION, samplingInterval=0.1))
    begin("a")
    guard("vitals-a-sampling-began", rumContext=owners["a"])
    view("a", 2_000_000_000, sampled=True)
    guard("vitals-a-samples-acknowledged", rumContext=owners["a"])
    guard("vitals-a-complete")
    step("open-window")
    background = add("scene-lifecycle", semanticContext=dict(logicalSceneID="scene-A", nativeSceneID="native-a"),
                     activationState="background")
    background["evidenceSource"] = "probe"
    final_a = view("a", 3_000_000_000, active=False, sampled=True)
    ready("b")
    view("b", 500_000_000)
    step("wait-for-signal")
    step("sample-shared-vitals")
    begin("b")
    guard("vitals-a-retired", rumContext=owners["a"])
    guard("vitals-b-sampling-began", rumContext=owners["b"])
    view("b", 2_000_000_000, sampled=True)
    guard("vitals-b-samples-acknowledged", rumContext=owners["b"])
    guard("vitals-stop-boundary", rumContext=owners["b"])
    final_b = view("b", 3_000_000_000, active=False, sampled=True)
    guard("vitals-final-a", rumContext=owners["a"], vitals=copy.deepcopy(final_a["vitals"]))
    guard("vitals-final-b", rumContext=owners["b"], vitals=copy.deepcopy(final_b["vitals"]))
    guard("vitals-inventory-verified")
    guard("vitals-b-complete")
    records.append(dict(type="semantic-result", runID=run, result=dict(
        scenarioID=v.SCENARIO, state="PASS", issues=[], matchedExpectationCount=30)))
    return records, run


def named(records, name):
    return next(r["signal"] for r in records if r.get("signal", {}).get("name") == name)


def snapshots(records):
    return [r["signal"] for r in records if r.get("signal", {}).get("kind") == "rum-view-snapshot"]


class VitalsContractTests(unittest.TestCase):
    def setUp(self):
        self.records, self.run = fixture()
        self.local = v.validate_local(self.records, self.run)
        self.rows = copy.deepcopy(self.local["views"])

    def reject_local(self, change):
        records = copy.deepcopy(self.records)
        change(records)
        with self.assertRaises(Rejected):
            v.validate_local(records, self.run)

    def test_accepts_exact_final_views_and_zero_unexpected_telemetry(self):
        result = v.validate_backend(self.local, self.rows, [], [], [], 0, 0)
        self.assertEqual(result["state"], "PASS")
        self.assertEqual(result["view_count"], 3)
        self.assertFalse(result["physical_device_claimed"])

    def test_stale_manifest_signal_terminal_and_frozen_fixture_fail(self):
        changes = [
            lambda r: r[0]["manifest"].update(runID="stale"),
            lambda r: r[0]["manifest"]["scenario"]["steps"].pop(),
            lambda r: r[-1].update(runID="stale"),
            lambda r: r[-1]["result"].update(matchedExpectationCount=22),
            lambda r: snapshots(r)[0].update(runID="stale"),
            lambda r: snapshots(r)[1]["vitals"].update(originalRunID="restored"),
        ]
        for change in changes:
            with self.subTest(change=change):
                self.reject_local(change)

    def test_missing_repeated_reordered_and_unacknowledged_guards_fail(self):
        changes = [
            lambda r: named(r, "vitals-a-owner").update(name="unexpected"),
            lambda r: named(r, "vitals-a-owner").update(name="vitals-configuration"),
            lambda r: named(r, "vitals-a-samples-acknowledged").update(result=None),
            lambda r: named(r, "vitals-a-complete").update(sequence=999),
        ]
        for change in changes:
            self.reject_local(change)

    def test_configuration_must_be_actual_and_all_unrelated_producers_disabled(self):
        for key in v.CONFIGURATION:
            self.reject_local(lambda r, k=key: named(r, "vitals-configuration")["vitals"]["configuration"].update({k: False}))
        self.reject_local(lambda r: named(r, "vitals-configuration")["vitals"].update(samplingInterval=0.5))

    def test_swapped_owner_and_native_scene_alias_fail(self):
        self.reject_local(lambda r: named(r, "vitals-b-owner")["rumContext"].update(viewID=uid(2)))
        self.reject_local(lambda r: named(r, "vitals-b-owner")["sourceContext"].update(nativeSceneID="native-a"))
        self.reject_local(lambda r: named(r, "vitals-final-a")["rumContext"].update(viewID=uid(3)))

    def test_native_retirement_is_required_before_b_sampling(self):
        def remove_background(records):
            next(r["signal"] for r in records if r.get("signal", {}).get("kind") == "scene-lifecycle")["activationState"] = "foreground-active"
        self.reject_local(remove_background)
        self.reject_local(lambda r: snapshots(r)[3]["rumContext"].update(viewActive=True))

    def test_missing_samples_and_late_mapper_are_rejected(self):
        self.reject_local(lambda r: snapshots(r)[2]["vitals"].pop("cpuTicks"))
        self.reject_local(lambda r: snapshots(r)[2].update(sequence=999))
        self.reject_local(lambda r: snapshots(r)[5]["vitals"].update(refreshRateAverage=None, refreshRateMin=None))

    def test_final_guard_cannot_supply_values_absent_from_mapper(self):
        self.reject_local(lambda r: named(r, "vitals-final-b")["vitals"].update(memoryMax=9999))

    def test_unexpected_native_events_and_nonzero_view_counts_fail(self):
        self.reject_local(lambda r: snapshots(r)[0].update(kind="rum-long-task"))
        self.reject_local(lambda r: snapshots(r)[2]["vitals"]["counters"].update(actions=1))

    def test_short_view_cpu_rate_and_invalid_metric_types_fail(self):
        for field, value in [("cpuRate", 0), ("cpuTicks", True), ("memoryAverage", "2048"),
                             ("refreshRateAverage", float("nan")), ("memoryMax", -1)]:
            self.reject_local(lambda r, f=field, val=value: snapshots(r)[0]["vitals"].update({f: val}))

    def test_measured_pairs_and_cpu_rate_must_match_the_view_interval(self):
        for change in [dict(memoryAverage=4000), dict(refreshRateMin=50), dict(cpuRate=999)]:
            self.reject_local(lambda r, c=change: snapshots(r)[2]["vitals"].update(c))

    def test_backend_metric_precision_is_bounded_and_never_coerces_types(self):
        home = next(row for row in self.rows if row["name"] == "ProbeHomeView")
        home["metrics"]["memoryAverage"] += 1e-7
        v.validate_views(self.local, self.rows)
        home["metrics"]["memoryAverage"] += 0.1
        with self.assertRaises(Rejected):
            v.validate_views(self.local, self.rows)
        for value in [True, "2048", float("inf")]:
            rows = copy.deepcopy(self.local["views"])
            rows[1]["metrics"]["memoryAverage"] = value
            with self.assertRaises(Rejected):
                v.validate_views(self.local, rows)

    def test_backend_absence_slow_frames_and_exact_interval_are_preserved(self):
        for change in [dict(slowFrames=None), dict(slowFrames=[dict(start=100, duration=50)]),
                       dict(timeSpentNanoseconds=499_999_999), dict(cpuTicks=0)]:
            rows = copy.deepcopy(self.local["views"])
            rows[0]["metrics"].update(change)
            with self.assertRaises(Rejected):
                v.validate_views(self.local, rows)

    def test_backend_complete_inventory_and_ownership_are_required(self):
        for rows in [self.rows[:-1], self.rows + [self.rows[0]], [self.rows[0]] * 3]:
            with self.assertRaises(Rejected):
                v.validate_views(self.local, rows)
        for field, value in [("run_id", "stale"), ("session_id", uid(90)),
                             ("container_present", True), ("is_active", True)]:
            rows = copy.deepcopy(self.rows)
            rows[1][field] = value
            with self.assertRaises(Rejected):
                v.validate_views(self.local, rows)

    def test_unexpected_backend_telemetry_and_boolean_counts_fail(self):
        for args in [([{}], [], [], 0, 0), ([], [{}], [], 0, 0), ([], [], [{}], 0, 0),
                     ([], [], [], 1, 0), ([], [], [], 0, 1), ([], [], [], False, 0)]:
            with self.assertRaises(Rejected):
                v.validate_backend(self.local, self.rows, *args)

    def test_final_indexing_wait_reads_again_without_replacing_values(self):
        early = copy.deepcopy(self.rows)
        home = next(row for row in early if row["name"] == "ProbeHomeView")
        home["is_active"] = True
        home["metrics"]["timeSpentNanoseconds"] = 2_000_000_000
        home["metrics"]["cpuRate"] = 20
        reads, waits = iter([early, self.rows]), []
        actual, count = v.settled_views(self.local, lambda: next(reads), waits.append)
        self.assertIs(actual, self.rows)
        self.assertEqual(count, 2)
        self.assertEqual(waits, [10])

    def test_regressed_overshooting_and_nonconverging_backend_views_fail(self):
        early = copy.deepcopy(self.rows)
        home = next(row for row in early if row["name"] == "ProbeHomeView")
        home["is_active"] = True
        with self.assertRaises(Rejected):
            v.settled_views(self.local, lambda: early, lambda _: None)
        for time in [2_000_000_000, 4_000_000_000]:
            changed = copy.deepcopy(early)
            changed_home = next(row for row in changed if row["name"] == "ProbeHomeView")
            changed_home["metrics"].update(timeSpentNanoseconds=time, cpuRate=40 / (time / 1e9))
            with self.assertRaises(Rejected):
                v.validate_views(self.local, changed, allow_pending=True, previous=early)


if __name__ == "__main__":
    unittest.main()
