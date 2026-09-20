"""Offline schema-v5 mechanics only; these tests never launch the fixture."""
import copy
import hashlib
import json
import unittest
from unittest.mock import patch
from pathlib import Path

import evaluate_exp198 as evaluator


ROOT = Path(__file__).parent


def receipt(value=0):
    result = {key: value for key in evaluator.RECEIPT}
    for key in ("operations", "native_task_lifecycles", "protocol_starts", "protocol_completions", "invalidations", "completions", "native_completions"):
        result[key] = 1
    return result


def completed_receipt():
    return {
        "protocol_starts": 1,
        "protocol_completions": 1,
        "native_completions": 1,
        "invalidations": 1,
        "errors": 0,
    }


def plan():
    rows = []
    for runtime_id, version, build in (("r17", "17.5", "21F79"), ("r27", "27.0", "24A434")):
        for tracking in ("automatic", "registered"):
            for mode in ("e01-timing", "e01-alloc-retention"):
                quartet = f"{runtime_id}:{tracking}:{mode}"
                for ordinal, arm in enumerate(("A", "B", "B", "A")):
                    rows.append({"cell_id": f"{runtime_id}-{tracking}-{mode}-{ordinal}", "runtime_id": runtime_id, "runtime_version": version, "runtime_build": build, "tracking": tracking, "mode": mode, "arm": arm, "quartet": quartet, "ordinal": ordinal})
    return {
        "schema_version": 5, "experiment": "EXP-198", "stage": "EXECUTION_FROZEN",
        "fixture_sha256": "f" * 64, "contract_sha256": "c" * 64,
        "arms": {
            "A": {"revision": evaluator.A_REV, "source_sha256": "a" * 64, "build_sha256": "b" * 64, "uuid": "UUID: opaque", "app_members": {"E01Fixture": "x"}},
            "B": {"revision": evaluator.B_REV, "source_sha256": "d" * 64, "build_sha256": "e" * 64, "uuid": "UUID: opaque", "app_members": {"E01Fixture": "y"}},
        },
        "matrix": rows,
        "reused_evidence": {"p04_evidence": {"path": str(ROOT / "accepted-p04.json"), "sha256": evaluator.P04_SHA}},
    }


def qualification_pair():
    identity = {"run_id": "11111111-1111-4111-8111-111111111111", "nonce": "22222222-2222-4222-8222-222222222222", "arm": "A", "tracking": "automatic", "mode": "qualify", "os": "17.5", "source_revision": evaluator.A_REV, "source_sha256": "a" * 64, "fixture_sha256": "f" * 64, "build_sha256": "b" * 64, "contract_sha256": "c" * 64}
    summary = {"identity": identity, "purpose": "qualification", "index": 0, "state": "LOCAL_COMPLETE", "started_at": 1, "capture_finished_at": 2, "finished_at": 3, "launch_started_at_ns": 10, "result_mtime_ns": 11, "cell_deadline": 20, "window_deadline": 30, "native_launches": 1, "runtime": {"version": "17.5", "buildversion": "21F79"}, "device": {"udid": "device"}, "host": {"preflight": True, "clean_install": True, "installed_binary_match": True, "no_competing_workload": True, "cleanup": True, "timebox": True}, "cleanup": {"container_absent": True, "process_absent": True, "binding_restored": True, "protected_unchanged": True, "source_unchanged": True, "helpers_unchanged": True, "errors": []}}
    native = {"schema_version": 5, "status": "LOCAL_COMPLETE", "identity": copy.deepcopy(identity), "native_roundtrip": {"task_identity": "task", "prepared_header": "x-datadog-trace-id", "native_completions": 1, "native_errors": 0, "native_body_bytes": 1024, "receiver_body_bytes": 1024, "receipts": receipt(), "receiver_delta": {"mutations": 1, "starts": 1, "completions": 1, "body_bytes": 1024, "metrics": 0}, "metrics_applicability": "automatic_inapplicable"}, "completed_task_control": {"isolated_feature": True, "completed_before_repeat": True, "repeat_resume_attempted": True, "numeric_credit": False, "native_receipts_before": completed_receipt(), "native_receipts_after": completed_receipt(), "classification": "EXPECTED_BASELINE_NEGATIVE", "post_completion_receiver_delta": {"mutations": 1, "starts": 1, "completions": 0}}, "teardown": {"class": "__NSCFLocalDataTask", "selector": "resume", "imp_before": "0x1", "imp_after": "0x1", "equal": True, "native_receipt": {"native_completions": 1, "native_body_bytes": 1024, "native_invalidation": 1}}, "final_release": {"feature_alive_before_release": True, "provider_alive_before_release": True, "handler_alive_before_release": True, "feature_released": True, "provider_released": True, "handler_released": True}, "mode_data": {"qualification": {"controls": {"task_hold": {"held": True, "released": True}, "feature_hold": {"held": True, "released": True}, "payload_continuation": {"applicability": "unsupported_on_A"}}}}}
    return summary, native


def phase(operations, samples=False, label=None, registered=False, second_resume=False, row="first_resume", instrumented=True, arm="B"):
    receipts = {key: 0 for key in evaluator.RECEIPT}
    expected_sdk = operations if instrumented else 0
    for key in ("operations", "native_task_lifecycles", "native_completions", "protocol_starts", "protocol_completions", "invalidations", "data_bytes", "outstanding_enters", "outstanding_leaves"):
        receipts[key] = operations if key != "data_bytes" else 1024 * operations
    receipts["resume_calls"] = operations * (2 if second_resume else 1)
    receipts["mutations"] = expected_sdk * (2 if arm == "A" and second_resume else 1)
    receipts["starts"] = expected_sdk
    receipts["completions"] = expected_sdk
    receipts["metrics"] = operations if registered else 0
    if row == "data": body = 1280 * expected_sdk
    elif row == "completion": body = 0
    elif row == "state": body = 0 if registered else 1024 * expected_sdk
    else: body = 1024 * expected_sdk
    mutation_start = expected_sdk * (2 if arm == "A" and second_resume else 1)
    data = {"expected_operations": operations, "receipts": receipts, "receiver_delta": {"mutations": mutation_start, "starts": expected_sdk, "completions": expected_sdk, "body_bytes": body, "metrics": operations if registered and instrumented else 0}}
    if samples:
        data.update(batch_ns=[1] * 7, samples_ns=[1] * 2000)
    if label:
        data["label"] = label
    return data


def timing_row(name, registered=False, arm="B"):
    if name == "metrics":
        return {"row": "metrics", "applicability": "registered_delegate_only"}
    flush_label = "entry through immediate feature.flush()"
    if name in ("unbound_first_resume", "first_resume"):
        flush_label = "resume through immediate feature flush (already-enqueued SDK work); held start and final flush outside timer"
    elif name == "second_resume_ready":
        flush_label = "second resume through immediate feature flush"
    second = name == "second_resume_ready"
    instrumented = name != "unbound_first_resume"
    row = {"row": name, "instrumentation": "sdk_unbound" if name == "unbound_first_resume" else "instrumented", "workload": {"discarded_warmup_operations": 1000, "measured_batches": 7, "operations_per_batch": 1000, "measured_operations": 7000, "individual_samples": 2000}, "warmup": phase(1000, registered=registered, second_resume=second, row=name, instrumented=instrumented, arm=arm), "caller_return": phase(7000, True, "caller entry to return", registered=registered, second_resume=second, row=name, instrumented=instrumented, arm=arm), "through_flush": phase(7000, True, flush_label, registered=registered, second_resume=second, row=name, instrumented=instrumented, arm=arm)}
    if name == "second_resume_ready":
        for item in (row["caller_return"], row["through_flush"]):
            item["receipts"].update(resume_calls=14000, outstanding_enters=7000, outstanding_leaves=7000)
    return row


def allocation_counter(operations=1, requested_bytes=16):
    return {
        "process_operations": operations,
        "process_bytes": requested_bytes,
        "caller_operations": 0,
        "caller_bytes": 0,
        "other_operations": operations,
        "other_bytes": requested_bytes,
    }


def allocation_row(name, registered=False, arm="B"):
    if name == "metrics":
        return {"row": "metrics", "applicability": "registered_delegate_only"}
    windows = [allocation_counter() for _ in range(16)]
    denominators = [64] * 15 + [40]
    batch_receipt = phase(1000, registered=registered, second_resume=name == "second_resume_ready", row=name, instrumented=name != "unbound_first_resume", arm=arm)["receipts"]
    batches = [{"expected_operations": 1000, "receipts": copy.deepcopy(batch_receipt), "windows": copy.deepcopy(windows), "window_denominators": denominators} for _ in range(7)]
    instrumented = name != "unbound_first_resume"
    measured = phase(7000, registered=registered, second_resume=name == "second_resume_ready", row=name, instrumented=instrumented, arm=arm)
    measured["batches"] = batches
    row = {
        "row": name,
        "instrumentation": "sdk_unbound" if name == "unbound_first_resume" else "instrumented",
        "workload": {"discarded_warmup_operations": 1000, "measured_batches": 7, "operations_per_batch": 1000, "measured_operations": 7000},
        "warmup": phase(1000, registered=registered, second_resume=name == "second_resume_ready", row=name, instrumented=instrumented, arm=arm),
        "allocation": measured,
    }
    if name == "full_task_cycle":
        row.pop("instrumentation")
        row.update(denominator="successful_tasks", budget_applies=True)
    return row


def allocation_data(arm, tracking):
    registered = tracking == "registered"
    rows = {name: allocation_row(name, registered=registered, arm=arm) for name in evaluator.ROWS + ("full_task_cycle",)}
    if tracking == "registered":
        rows["metrics"] = allocation_row("first_resume", registered=True, arm=arm)
        rows["metrics"]["row"] = "metrics"
    calibration = {
        "completed": True,
        "calibration_before_unbound": True,
        "lock_free": True,
        "passes": {"caller": True, "feature_queue": True, "worker": True, "concurrent": True, "caller_only_negative_rejected": True},
    }
    for name in ("caller", "feature_queue", "worker", "concurrent"):
        value = allocation_counter(3, 165)
        if name == "caller":
            value.update(caller_operations=3, caller_bytes=165, other_operations=0, other_bytes=0)
        if name == "concurrent":
            value.update(process_operations=1200, process_bytes=66000, other_operations=1200, other_bytes=66000)
        calibration[name] = value
    inventories = []
    for boundary, heap in zip((20, 120, 220), (1000, 1000, 1000)):
        inventory = {"boundary": boundary, "interceptions": 0, "truncatedInterceptions": 0, "task_weak_members": 0, "interception_weak_members": 0, "reflection_available": True}
        if arm == "B":
            inventory["preparations"] = {"raw_count_before_enumeration": 2, "live_weak_keys": 0, "remaining_values": 0, "phase_payloads": 0, "events": 0, "continuations": 0, "remaining_key_sequence": 1, "phases": []}
            inventory["weak_terminal_tasks"] = {"raw_count_before_enumeration": 1, "live_members": 0}
        inventories.append(inventory)
    return {
        "calibration": calibration,
        "rows": rows,
        "full_lifetime_churn": {"diagnostic": True},
        "idle_control": {"diagnostic": True},
        "evaluator_negative_controls": {"first_100_growth": 65537, "second_100_growth": 16385, "expected": "evaluator_rejects", "caller_only_counter_negative": "reused_calibrated_counter_control"},
        "retention": {"fresh_cohort": True, "verified_cycles": 220, "interception_liveness_verified_cycles": 220, "receiver_delta": {"mutations": 220, "starts": 220, "completions": 220}, "heap_bytes": [1000, 1000, 1000], "first_100_growth": 0, "second_100_growth": 0, "inventories": inventories},
    }


def measurement_pair(index, execution_plan):
    cell = execution_plan["matrix"][index]
    summary, native = qualification_pair()
    identity = summary["identity"]
    arm = execution_plan["arms"][cell["arm"]]
    identity.update(arm=cell["arm"], tracking=cell["tracking"], mode=cell["mode"], os=cell["runtime_version"], source_revision=arm["revision"], source_sha256=arm["source_sha256"], build_sha256=arm["build_sha256"])
    native["identity"] = copy.deepcopy(identity)
    summary.update(purpose="measurement", index=index, runtime={"version": cell["runtime_version"], "buildversion": cell["runtime_build"]}, matrix_started_at=0, matrix_deadline=10800)
    if cell["mode"] == "e01-timing":
        rows = {name: timing_row(name, registered=cell["tracking"] == "registered", arm=cell["arm"]) for name in evaluator.ROWS}
        if cell["tracking"] == "registered":
            rows["metrics"] = timing_row("first_resume", registered=True, arm=cell["arm"])
            rows["metrics"]["row"] = "metrics"
            rows["metrics"]["through_flush"]["label"] = "entry through immediate feature.flush()"
        native["mode_data"] = {"timing": {"rows": rows}}
    else:
        native["mode_data"] = {"allocation": allocation_data(cell["arm"], cell["tracking"])}
    if cell["arm"] == "B":
        native["completed_task_control"]["classification"] = "CANDIDATE_PASS"
        native["completed_task_control"]["post_completion_receiver_delta"] = {"mutations": 0, "starts": 0, "completions": 0}
    if cell["tracking"] == "registered":
        native["native_roundtrip"]["metrics_applicability"] = "registered_observed"
        native["native_roundtrip"]["receipts"]["metrics"] = 1
        native["native_roundtrip"]["receiver_delta"]["metrics"] = 1
    return summary, native


def evaluate_synthetic_matrix(execution_plan, mutate=None):
    records, cells = {}, []
    for index in range(32):
        summary, native = measurement_pair(index, execution_plan)
        summary["local_result_sha256"] = "d" * 64
        name = f"cell-{index}"
        records[name] = {"summary.json": summary, "local.json": native}
        cells.append(Path(name))
    if mutate:
        mutate(records)
    def fake_read(path):
        path = Path(path)
        if path.name == "accepted-p04.json":
            return json.loads(path.read_text())
        return records[path.parent.name][path.name]
    real_digest = evaluator.digest
    def fake_digest(path):
        return "d" * 64 if Path(path).name == "local.json" else real_digest(path)
    with patch.object(evaluator, "read", side_effect=fake_read), patch.object(evaluator, "digest", side_effect=fake_digest):
        return evaluator.evaluate_matrix(execution_plan, cells)


class EvaluatorV5Tests(unittest.TestCase):
    def test_baseline_second_resume_has_two_mutations_but_one_start(self):
        for registered in (False, True):
            data=phase(1000,registered=registered,second_resume=True,arm="A")
            evaluator.phase(data,"repeat",1000,registered=registered,second_resume=True,arm="A")
            evaluator.receiver_phase(data["receiver_delta"],"receiver","second_resume_ready",1000,registered,True,"A",True)
            self.assertEqual((data["receipts"]["mutations"],data["receipts"]["starts"]),(2000,1000))
    def test_duplicate_start_missing_native_and_missing_repeat_each_reject(self):
        original=phase(1000,second_resume=True,arm="A")
        for key,value in [("starts",2000),("native_completions",999),("resume_calls",1000),("mutations",1000)]:
            data=copy.deepcopy(original);data["receipts"][key]=value
            with self.assertRaises(evaluator.EvidenceError):evaluator.phase(data,"repeat",1000,second_resume=True,arm="A")
        data=copy.deepcopy(original);data["receiver_delta"]["starts"]=2000
        with self.assertRaises(evaluator.EvidenceError):evaluator.receiver_phase(data["receiver_delta"],"receiver","second_resume_ready",1000,False,True,"A",True)
    def test_candidate_duplicate_mutation_still_rejects(self):
        data=phase(1000,second_resume=True,arm="B");data["receipts"]["mutations"]=2000
        with self.assertRaises(evaluator.EvidenceError):evaluator.phase(data,"repeat",1000,second_resume=True,arm="B")
    def test_captured_baseline_timing_format_is_diagnostic_only(self):
        raw=ROOT/"observed-baseline-timing.json"
        document=json.loads(raw.read_text())
        evaluator.timing_valid(document["mode_data"]["timing"],"A","automatic")

    def assert_inconclusive(self, summary, native, execution_plan):
        self.assertEqual(evaluator.validate_cell(summary, native, execution_plan)["status"], "INCONCLUSIVE")

    def test_qualification_control_is_valid_without_numeric_rows(self):
        summary, native = qualification_pair()
        self.assertEqual(evaluator.validate_cell(summary, native, plan())["status"], "CELL_VALID")

    def test_all_four_qualification_arm_tracking_slots_are_valid_without_numeric_rows(self):
        execution_plan = plan()
        for index, (arm, tracking) in enumerate((("A", "automatic"), ("A", "registered"), ("B", "automatic"), ("B", "registered"))):
            summary, native = qualification_pair()
            source = execution_plan["arms"][arm]
            summary["index"] = index
            summary["identity"].update(arm=arm, tracking=tracking, source_revision=source["revision"], source_sha256=source["source_sha256"], build_sha256=source["build_sha256"])
            native["identity"] = copy.deepcopy(summary["identity"])
            if tracking == "registered":
                native["native_roundtrip"]["metrics_applicability"] = "registered_observed"
                native["native_roundtrip"]["receipts"]["metrics"] = 1
                native["native_roundtrip"]["receiver_delta"]["metrics"] = 1
            if arm == "B":
                native["completed_task_control"]["classification"] = "CANDIDATE_PASS"
                native["completed_task_control"]["post_completion_receiver_delta"] = {"mutations": 0, "starts": 0, "completions": 0}
                native["mode_data"]["qualification"]["controls"]["payload_continuation"] = {"applicability": "candidate_B", "actual_data": True, "duplicate_resume": True, "nonzero_while_blocked": True, "zero_after_drain": True, "held_events": 1, "held_continuations": 1, "drained_events": 0, "drained_continuations": 0}
            self.assertEqual(evaluator.validate_cell(summary, native, execution_plan)["status"], "CELL_VALID")

    def test_missing_callback_is_inconclusive(self):
        summary, native = qualification_pair(); del native["native_roundtrip"]["receipts"]["protocol_starts"]
        self.assert_inconclusive(summary, native, plan())

    def test_stale_identity_is_inconclusive(self):
        summary, native = qualification_pair(); native["identity"]["nonce"] = "33333333-3333-4333-8333-333333333333"
        self.assert_inconclusive(summary, native, plan())

    def test_post_release_imp_mismatch_is_inconclusive(self):
        summary, native = qualification_pair(); native["teardown"]["imp_after"] = "0x2"
        self.assert_inconclusive(summary, native, plan())

    def test_baseline_repeat_requires_exact_expected_negative(self):
        summary, native = qualification_pair(); native["completed_task_control"]["post_completion_receiver_delta"]["mutations"] = 0
        self.assert_inconclusive(summary, native, plan())

    def test_qualification_rejects_numeric_mode_data(self):
        summary, native = qualification_pair(); native["mode_data"] = {"timing": {}}
        self.assert_inconclusive(summary, native, plan())

    def test_final_evaluation_time_is_bounded(self):
        summary, native = qualification_pair(); summary["finished_at"] = 21
        self.assert_inconclusive(summary, native, plan())

    def test_timing_phase_and_second_resume_controls_are_valid(self):
        execution_plan = plan(); summary, native = measurement_pair(0, execution_plan)
        self.assertEqual(evaluator.validate_cell(summary, native, execution_plan)["status"], "CELL_VALID")

    def test_timing_second_resume_double_enter_is_inconclusive(self):
        execution_plan = plan(); summary, native = measurement_pair(0, execution_plan)
        native["mode_data"]["timing"]["rows"]["second_resume_ready"]["caller_return"]["receipts"]["outstanding_enters"] = 14000
        self.assert_inconclusive(summary, native, execution_plan)

    def test_allocation_phase_and_signed_retention_controls_are_valid(self):
        execution_plan = plan(); summary, native = measurement_pair(4, execution_plan)
        self.assertEqual(evaluator.validate_cell(summary, native, execution_plan)["status"], "CELL_VALID")

    def test_allocation_rejects_full_task_cycle_only_overrun(self):
        execution_plan = plan(); summary, native = measurement_pair(4, execution_plan)
        native["mode_data"]["allocation"]["rows"]["full_task_cycle"]["denominator"] = "wrong"
        self.assert_inconclusive(summary, native, execution_plan)

    def test_numeric_budgets_reject_timing_and_full_task_cycle_allocation_excess(self):
        execution_plan = plan()
        _, baseline = measurement_pair(4, execution_plan)
        _, candidate = measurement_pair(5, execution_plan)
        baseline_row = baseline["mode_data"]["allocation"]["rows"]["full_task_cycle"]
        candidate_row = candidate["mode_data"]["allocation"]["rows"]["full_task_cycle"]
        candidate_row["allocation"]["batches"][0]["windows"][0].update(process_operations=8_000, process_bytes=1_000_000, other_operations=8_000, other_bytes=1_000_000)
        with self.assertRaises(evaluator.ThresholdError):
            evaluator.alloc_pooled_compare(baseline_row, baseline_row, candidate_row, "full-task-only")
        _, timing_a = measurement_pair(0, execution_plan)
        _, timing_b = measurement_pair(1, execution_plan)
        a_row = timing_a["mode_data"]["timing"]["rows"]["first_resume"]
        b_row = timing_b["mode_data"]["timing"]["rows"]["first_resume"]
        b_row["caller_return"]["samples_ns"] = [10_000] * 2000
        b_row["through_flush"]["samples_ns"] = [10_000] * 2000
        with self.assertRaises(evaluator.ThresholdError):
            evaluator.timing_pooled_compare(a_row, a_row, b_row, "timing")

    def test_allocation_rejects_inconsistent_signed_heap_delta(self):
        execution_plan = plan(); summary, native = measurement_pair(4, execution_plan)
        native["mode_data"]["allocation"]["retention"]["heap_bytes"] = [1000, 900, 800]
        self.assert_inconclusive(summary, native, execution_plan)

    def test_allocation_rejects_missing_calibration_and_candidate_ownership(self):
        execution_plan = plan(); summary, native = measurement_pair(4, execution_plan)
        del native["mode_data"]["allocation"]["calibration"]["passes"]["worker"]
        self.assert_inconclusive(summary, native, execution_plan)
        summary, native = measurement_pair(5, execution_plan)
        native["mode_data"]["allocation"]["retention"]["inventories"][0]["preparations"]["events"] = 1
        self.assert_inconclusive(summary, native, execution_plan)

    def test_allocation_rejects_missing_existing_cohort_receiver_or_liveness_evidence(self):
        execution_plan = plan(); summary, native = measurement_pair(4, execution_plan)
        native["mode_data"]["allocation"]["retention"]["receiver_delta"]["starts"] = 0
        self.assert_inconclusive(summary, native, execution_plan)
        summary, native = measurement_pair(4, execution_plan)
        native["mode_data"]["allocation"]["retention"]["interception_liveness_verified_cycles"] = 0
        self.assert_inconclusive(summary, native, execution_plan)

    def test_candidate_retention_budget_is_absolute_but_baseline_raw_growth_is_not(self):
        execution_plan = plan(); summary, native = measurement_pair(5, execution_plan)
        retention = native["mode_data"]["allocation"]["retention"]
        retention.update(heap_bytes=[0, 65537, 65537], first_100_growth=65537, second_100_growth=0)
        self.assertEqual(evaluator.validate_cell(summary, native, execution_plan)["status"], "FAIL")
        summary, native = measurement_pair(4, execution_plan)
        retention = native["mode_data"]["allocation"]["retention"]
        retention.update(heap_bytes=[0, 65537, 65537], first_100_growth=65537, second_100_growth=0)
        self.assertEqual(evaluator.validate_cell(summary, native, execution_plan)["status"], "CELL_VALID")

    def test_qualification_rejects_half_observed_candidate_payload_control(self):
        execution_plan = plan(); summary, native = qualification_pair()
        summary["index"] = 2
        source = execution_plan["arms"]["B"]
        summary["identity"].update(arm="B", source_revision=source["revision"], source_sha256=source["source_sha256"], build_sha256=source["build_sha256"])
        native["identity"] = copy.deepcopy(summary["identity"])
        native["completed_task_control"].update(classification="CANDIDATE_PASS", post_completion_receiver_delta={"mutations": 0, "starts": 0, "completions": 0})
        native["mode_data"]["qualification"]["controls"]["payload_continuation"] = {"applicability": "candidate_B", "actual_data": True, "duplicate_resume": True, "nonzero_while_blocked": True, "zero_after_drain": True, "held_events": 1, "held_continuations": 0, "drained_events": 0, "drained_continuations": 0}
        self.assert_inconclusive(summary, native, execution_plan)

    def test_automatic_metrics_and_explicit_native_completion_cannot_be_coerced(self):
        execution_plan = plan(); summary, native = measurement_pair(0, execution_plan)
        native["mode_data"]["timing"]["rows"]["metrics"] = timing_row("first_resume")
        native["mode_data"]["timing"]["rows"]["metrics"]["row"] = "metrics"
        self.assert_inconclusive(summary, native, execution_plan)
        summary, native = qualification_pair()
        native["native_roundtrip"]["native_completions"] = 0
        self.assert_inconclusive(summary, native, execution_plan)

    def test_completed_control_rejects_native_duplicate_and_final_release_loss(self):
        execution_plan = plan(); summary, native = qualification_pair()
        native["completed_task_control"]["native_receipts_after"]["native_completions"] = 2
        self.assert_inconclusive(summary, native, execution_plan)
        summary, native = qualification_pair()
        native["final_release"]["feature_released"] = False
        self.assert_inconclusive(summary, native, execution_plan)

    def test_full_synthetic_matrix_mechanics_are_valid(self):
        execution_plan = plan()
        verdict = evaluate_synthetic_matrix(execution_plan)
        self.assertEqual(verdict["status"], "PASS")
        self.assertEqual(verdict["cell_count"], 32)

    def test_valid_synthetic_matrix_rejects_full_task_cycle_candidate_excess(self):
        execution_plan = plan()
        for field, value in (("operations", 8_000), ("bytes", 1_000_000)):
            def mutate(records, field=field, value=value):
                window = records["cell-5"]["local.json"]["mode_data"]["allocation"]["rows"]["full_task_cycle"]["allocation"]["batches"][0]["windows"][0]
                if field == "operations":
                    window.update(process_operations=value, other_operations=value)
                else:
                    window.update(process_bytes=value, other_bytes=value)
            self.assertEqual(evaluate_synthetic_matrix(execution_plan, mutate)["status"], "FAIL", field)

    def test_valid_synthetic_matrix_rejects_timing_candidate_excess(self):
        execution_plan = plan()
        def median_only(records):
            row = records["cell-1"]["local.json"]["mode_data"]["timing"]["rows"]["first_resume"]
            row["caller_return"]["samples_ns"] = [600] * 2000
            row["through_flush"]["samples_ns"] = [600] * 2000
        def p95_only(records):
            row = records["cell-1"]["local.json"]["mode_data"]["timing"]["rows"]["first_resume"]
            samples = [1] * 1800 + [1101] * 200
            row["caller_return"]["samples_ns"] = samples
            row["through_flush"]["samples_ns"] = samples
        self.assertEqual(evaluate_synthetic_matrix(execution_plan, median_only)["status"], "FAIL", "median-only")
        self.assertEqual(evaluate_synthetic_matrix(execution_plan, p95_only)["status"], "FAIL", "p95-only")

    def test_measurement_rejects_matrix_deadline_overrun(self):
        execution_plan = plan(); summary, native = measurement_pair(0, execution_plan)
        summary["finished_at"] = 10801
        self.assert_inconclusive(summary, native, execution_plan)

    def test_plan_rejects_duplicate_matrix_cell(self):
        execution_plan = plan(); execution_plan["matrix"][1]["cell_id"] = execution_plan["matrix"][0]["cell_id"]
        summary, native = qualification_pair()
        self.assert_inconclusive(summary, native, execution_plan)


if __name__ == "__main__":
    unittest.main()
