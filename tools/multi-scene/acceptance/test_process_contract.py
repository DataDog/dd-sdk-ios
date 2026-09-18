import copy
import json
from pathlib import Path
import unittest
from acceptance_common import Rejected
import process_contract as p


def uid(number):
    return f"00000000-0000-0000-0000-{number:012d}"


def fixture():
    run, sid = "exp185-unit", uid(1)
    scenario = json.loads(Path(__file__).with_name(p.CONTRACT).read_text())
    records = [dict(type="manifest", manifest=dict(runID=run, runMode="clean", validationErrors=[], scenario=scenario))]
    signals, owners = [], {"a": dict(sessionID=sid, viewID=uid(2)), "b": dict(sessionID=sid, viewID=uid(3))}

    def add(kind, time=90000, **kwargs):
        signal = dict(kind=kind, evidenceSource="internal-hook", schemaVersion=5, sequence=len(signals) + 1,
                      runID=run, scenarioID=p.SCENARIO, timestampMilliseconds=time, **kwargs)
        signals.append(signal)
        records.append(dict(type="signal", signal=signal))
        return signal

    def assertion(name, time=90000, **kw):
        return add("assertion", time, name=name, result="PASS", **kw)

    def view(label, count=0, action=0, time=90000):
        context = owners[label] if label else dict(sessionID=sid, viewID=uid(4))
        s = add("rum-view-snapshot", time, rumContext=dict(
            context, viewName="ProbeHomeView" if label else "ApplicationLaunch", viewActive=True),
            semanticContext=dict(logicalSceneID="scene-" + label.upper()) if label else {},
            processSignal=dict(nativeSource="ios", originalRunID=run, viewLongTaskCount=count,
                               viewErrorCount=2 * count, viewActionCount=action, viewResourceCount=0, viewCrashCount=0))
        s["evidenceSource"] = "rum-mapper"

    session = add("rum-session-started", rumContext=dict(sessionID=sid, sessionDiscarded=False))
    session["evidenceSource"] = "rum-mapper"
    for label in [None, "a", "b"]:
        view(label)
    for label in ["a", "b"]:
        s = add("scene-ready", semanticContext=dict(logicalSceneID="scene-" + label.upper(), nativeSceneID="native-" + label),
                scenePhase="ready", activationState="foreground-inactive")
        s["evidenceSource"] = "probe"
    add("step-started", stepKind="run-process-signal-batch")
    assertion("process-configuration", processSignal=dict(longTaskThreshold=0.5, appHangThreshold=0.5,
              hasLongTaskObserver=True, hasAppHangMonitor=True, hasMemoryWarningMonitor=True))
    for label in ["a", "b"]:
        assertion("process-owner-" + label, rumContext=owners[label],
                  sourceContext=dict(logicalSceneID="scene-" + label.upper(), nativeSceneID="native-" + label, screen="home"))
    event_number = 10
    for index, label in enumerate(["b", "a"]):
        base = 100000 + index * 4000
        if label == "a":
            assertion("process-selection-boundary", base - 2000)
            action = add("rum-action", base - 1990, rumContext=owners["a"], eventID=uid(20),
                         action=dict(id=uid(20), type="custom", target="process-select-a"))
            action["evidenceSource"] = "rum-mapper"
            assertion("process-selection-acknowledged", base - 1980)
        assertion("process-" + label + "-representative", base, rumContext=owners[label],
                  processSignal=dict(serverTimeOffsetMilliseconds=0))
        assertion("process-" + label + "-memory-boundary", base + 10)

        def event(kind, date, duration=None):
            nonlocal event_number
            event_number += 1
            is_task = kind == "LongTask"
            s = add("rum-long-task" if is_task else "rum-error", base + (11 if kind == "MemoryWarning" else 1530),
                    rumContext=dict(owners[label], eventDateMilliseconds=date), eventID=uid(event_number),
                    processSignal=dict(durationNanoseconds=duration, nativeSource="ios", originalRunID=run,
                                       hasAction=False, hasContainer=False))
            s["evidenceSource"] = "rum-mapper"
            if not is_task:
                s["error"] = dict(id=uid(event_number), type=kind, source="source", isCrash=False,
                                  category="App Hang" if kind == "AppHang" else "Memory Warning")
            return s

        event("MemoryWarning", base + 11)
        assertion("process-" + label + "-memory-acknowledged", base + 15)
        assertion("process-" + label + "-block-began", base + 20)
        assertion("process-" + label + "-block-ended", base + 1520)
        event("LongTask", base + 20, 1_500_000_000)
        event("AppHang", base + 15, 1_505_000_000)
        view(label, 1, int(label == "a"), base + 1540)
        assertion("process-" + label + "-signals-acknowledged", base + 1550, rumContext=owners[label])
    assertion("process-inventory-verified", 110000)
    assertion("process-batch-complete", 110001)
    records.append(dict(type="semantic-result", runID=run, result=dict(
        scenarioID=p.SCENARIO, state="PASS", issues=[], matchedExpectationCount=40)))
    return records, run


def named(records, name):
    return next(r["signal"] for r in records if r.get("signal", {}).get("name") == name)


def events(records, kind=None):
    return [r["signal"] for r in records if r["type"] == "signal" and
            (kind is None or r["signal"]["kind"] == kind)]


def backend(local):
    result = []
    for kind in ["views", "errors", "long_tasks", "actions"]:
        result.append([dict.fromkeys(p.PROJECT_KEYS) | row for row in local[kind]])
    return [*result, [], 0]


class ProcessContractTests(unittest.TestCase):
    def setUp(self):
        self.records, self.run = fixture()

    def reject(self):
        with self.assertRaises(Rejected):
            p.validate_local(self.records, self.run)

    def test_complete_two_round_contract(self):
        local = p.validate_local(self.records, self.run)
        self.assertEqual(p.validate_backend(local, self.run, *backend(local))["state"], "PASS")

    def test_stale_fixture(self):
        self.records[0]["manifest"]["scenario"]["steps"][-1]["kind"] = "emit-marker"
        self.reject()

    def test_consumed_readiness_step(self):
        self.records[0]["manifest"]["scenario"]["steps"].insert(3, dict(kind="wait-for-scene-ready", scene="scene-B"))
        self.reject()

    def test_restored_run_identity(self):
        for target in [self.records[0]["manifest"], self.records[-1], events(self.records)[0]]:
            old = target["runID"]
            target["runID"] = "stale"
            self.reject()
            target["runID"] = old

    def test_payload_origin_cannot_borrow_envelope(self):
        events(self.records, "rum-error")[0]["processSignal"]["originalRunID"] = "stale"
        self.reject()

    def test_wrong_actual_monitor_threshold(self):
        named(self.records, "process-configuration")["processSignal"]["longTaskThreshold"] = 0.1
        self.reject()

    def test_missing_native_monitor(self):
        named(self.records, "process-configuration")["processSignal"]["hasAppHangMonitor"] = False
        self.reject()

    def test_missing_failed_duplicate_and_late_guards(self):
        original = copy.deepcopy(self.records)
        s = named(self.records, "process-b-representative")
        s.pop("result")
        self.reject()
        self.records = copy.deepcopy(original)
        s = named(self.records, "process-b-representative")
        s["result"] = "FAIL"
        self.reject()
        self.records = copy.deepcopy(original)
        named(self.records, "process-b-block-began")["name"] = "process-b-memory-boundary"
        self.reject()
        self.records = copy.deepcopy(original)
        a, b = named(self.records, "process-b-representative"), named(self.records, "process-b-memory-boundary")
        a["name"], b["name"] = b["name"], a["name"]
        self.reject()

    def test_missing_independent_readiness(self):
        events(self.records, "scene-ready")[0]["scenePhase"] = "requested"
        self.reject()

    def test_conflicting_mapper_native_id(self):
        events(self.records, "rum-view-snapshot")[1]["semanticContext"]["nativeSceneID"] = "foreign"
        self.reject()

    def test_claimed_source_is_not_owner(self):
        named(self.records, "process-owner-a")["rumContext"]["viewID"] = uid(99)
        self.reject()

    def test_wrong_representative_before_stimulus(self):
        named(self.records, "process-b-representative")["rumContext"] = dict(sessionID=uid(1), viewID=uid(2))
        self.reject()

    def test_peer_owner_swapped(self):
        events(self.records, "rum-long-task")[0]["rumContext"]["viewID"] = uid(2)
        self.reject()

    def test_duplicate_event_id(self):
        events(self.records, "rum-long-task")[1]["eventID"] = events(self.records, "rum-long-task")[0]["eventID"]
        self.reject()

    def test_view_count_broadcast(self):
        events(self.records, "rum-view-snapshot")[-1]["processSignal"]["viewLongTaskCount"] = 2
        self.reject()

    def test_active_action_on_process_signal(self):
        events(self.records, "rum-error")[0]["processSignal"]["hasAction"] = True
        self.reject()

    def test_extra_container(self):
        events(self.records, "rum-long-task")[0]["processSignal"]["hasContainer"] = True
        self.reject()

    def test_fatal_hang_substitution(self):
        events(self.records, "rum-error")[1]["error"]["isCrash"] = True
        self.reject()

    def test_wrong_error_category(self):
        events(self.records, "rum-error")[0]["error"]["category"] = "App Hang"
        self.reject()

    def test_duration_type_threshold_and_interval(self):
        for value in [True, "1500000000", 0, 5_000_000_000]:
            original = events(self.records, "rum-long-task")[0]["processSignal"]["durationNanoseconds"]
            events(self.records, "rum-long-task")[0]["processSignal"]["durationNanoseconds"] = value
            self.reject()
            events(self.records, "rum-long-task")[0]["processSignal"]["durationNanoseconds"] = original
        events(self.records, "rum-long-task")[0]["rumContext"]["eventDateMilliseconds"] -= 2000
        self.reject()

    def test_acknowledgement_before_producer(self):
        task = events(self.records, "rum-long-task")[0]
        ack = named(self.records, "process-b-signals-acknowledged")
        record = next(r for r in self.records if r.get("signal") is task)
        self.records.remove(record)
        index = next(i for i, r in enumerate(self.records) if r.get("signal") is ack)
        self.records.insert(index + 1, record)
        for index, signal in enumerate(events(self.records)):
            signal["sequence"] = index + 1
        self.reject()

    def test_extra_unrelated_telemetry(self):
        events(self.records)[0]["kind"] = "rum-resource"
        self.reject()

    def test_backend_rejects_all_ownership_duration_count_and_type_changes(self):
        local = p.validate_local(self.records, self.run)
        for index, field, value in [
            (0, "view_error_count", 9), (0, "view_crash_count", True),
            (1, "view_id", uid(99)), (1, "error_category", "Exception"),
            (1, "run_id", "restored"), (1, "error_source_type", "browser"),
            (2, "duration_ns", "1500000000"), (2, "action_present", True),
            (3, "view_id", uid(99)), (3, "action_type", "tap"),
        ]:
            evidence = backend(local)
            evidence[index][0][field] = value
            with self.subTest(field=field), self.assertRaises(Rejected):
                p.validate_backend(local, self.run, *evidence)

    def test_backend_missing_extra_duplicate_and_malformed_projection(self):
        local = p.validate_local(self.records, self.run)
        for mutation in ["missing", "extra", "duplicate", "malformed"]:
            evidence = backend(local)
            rows = evidence[2]
            if mutation == "missing":
                rows.pop()
            elif mutation == "extra":
                rows.append(copy.deepcopy(rows[0]))
            elif mutation == "duplicate":
                rows[1]["event_id"] = rows[0]["event_id"]
            else:
                rows[0]["unreviewed"] = "extra"
            with self.subTest(mutation=mutation), self.assertRaises(Rejected):
                p.validate_backend(local, self.run, *evidence)

    def test_optional_zero_counters_stay_optional(self):
        local = p.validate_local(self.records, self.run)
        evidence = backend(local)
        for row in evidence[0]:
            if row["view_long_task_count"] == 0:
                row["view_long_task_count"] = None
            row["view_crash_count"] = None
        self.assertEqual(p.validate_backend(local, self.run, *evidence)["state"], "PASS")


if __name__ == "__main__":
    unittest.main()
