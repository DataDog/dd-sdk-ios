#!/usr/bin/env python3
"""Fail-closed EXP-198 schema-v5 evaluator.

Public API: validate_cell(summary, native, execution_plan) and
evaluate_matrix(execution_plan, cell_dirs). Native evidence is never rewritten.
"""
from __future__ import annotations
import hashlib
import json
import math
import statistics
import uuid
from pathlib import Path
from typing import Any

A_REV = "62f64d7b655bdc83f3036c4ad81090a270f6202b"
B_REV = "1bdc9286c17d69d73e5e41530e6179c72a723368"
P04_SHA = "a4079a372feb4a81e9863e4bf93d4b3c01aaf6e325eccb4e11633501c911385c"
ROWS = ("unbound_first_resume", "first_resume", "second_resume_ready", "data", "metrics", "completion", "state")
# `native_completions` and `errors` are callback receipts, not expected-loop
# counters. They are required by the admitted contract and preserved shape 98c.
RECEIPT = ("operations", "native_task_lifecycles", "resume_calls", "mutations", "starts", "completions", "native_completions", "protocol_starts", "protocol_completions", "invalidations", "errors", "data_bytes", "metrics", "outstanding_enters", "outstanding_leaves", "outstanding_max")
COUNTERS = ("process_operations", "process_bytes", "caller_operations", "caller_bytes", "other_operations", "other_bytes")

class EvidenceError(Exception): pass
class ThresholdError(Exception): pass

def need(x, path, typ=None):
    if x is None: raise EvidenceError(f"missing {path}")
    if typ and (isinstance(x, bool) or not isinstance(x, typ)): raise EvidenceError(f"{path}: wrong type")
    return x

def integer(x, path, minimum=0):
    if isinstance(x, bool) or not isinstance(x, int) or x < minimum: raise EvidenceError(f"{path}: expected integer >= {minimum}")
    return x

def signed_integer(x, path):
    if isinstance(x, bool) or not isinstance(x, int): raise EvidenceError(f"{path}: expected signed integer")
    return x

def number(x, path, minimum=None):
    if isinstance(x, bool) or not isinstance(x, (int, float)) or not math.isfinite(float(x)): raise EvidenceError(f"{path}: expected finite number")
    if minimum is not None and x < minimum: raise EvidenceError(f"{path}: below {minimum}")
    return float(x)

def keys(x, expected, path):
    x = need(x, path, dict)
    if set(x) != set(expected): raise EvidenceError(f"{path}: keys mismatch")
    return x

def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for part in iter(lambda: f.read(1024 * 1024), b""): h.update(part)
    return h.hexdigest()

def read(path):
    try: return need(json.loads(Path(path).read_bytes()), str(path), dict)
    except (OSError, ValueError) as e: raise EvidenceError(f"cannot read {path}: {e}")

def uuid_value(x, path):
    if not isinstance(x, str): raise EvidenceError(f"{path}: UUID missing")
    try: parsed = uuid.UUID(x)
    except ValueError as e: raise EvidenceError(f"{path}: invalid UUID") from e
    if str(parsed) != x.lower(): raise EvidenceError(f"{path}: noncanonical UUID")

def sha(x, path, length=64):
    if not isinstance(x, str) or len(x) != length or any(c not in "0123456789abcdef" for c in x): raise EvidenceError(f"{path}: invalid SHA")

def receipt(x, path):
    x = keys(x, RECEIPT, path)
    return {k: integer(x[k], f"{path}.{k}") for k in RECEIPT}

def completed_receipt(x, path):
    x = keys(x, ("protocol_starts", "protocol_completions", "native_completions", "invalidations", "errors"), path)
    values = {k: integer(x[k], f"{path}.{k}") for k in x}
    if tuple(values[k] for k in ("protocol_starts", "protocol_completions", "native_completions", "invalidations", "errors")) != (1, 1, 1, 1, 0):
        raise EvidenceError(f"{path}: completed native receipt is not exactly once")
    return values

def phase(x, path, operations, samples=False, label=None, registered=False, second_resume=False, instrumented=True, arm="B"):
    x = need(x, path, dict)
    if x.get("expected_operations") != operations: raise EvidenceError(f"{path}: wrong denominator")
    r = receipt(x.get("receipts"), f"{path}.receipts")
    for k in ("operations", "native_task_lifecycles", "protocol_starts", "protocol_completions", "native_completions", "invalidations", "outstanding_enters", "outstanding_leaves"):
        if r[k] != operations: raise EvidenceError(f"{path}.receipts.{k}: missing callback evidence")
    expected_sdk = operations if instrumented else 0
    expected_mutations = expected_sdk * (2 if arm == "A" and second_resume else 1)
    if r["resume_calls"] != operations * (2 if second_resume else 1) or r["errors"] != 0 or r["data_bytes"] != 1024 * operations or r["metrics"] != (operations if registered else 0) or r["completions"] != expected_sdk or r["mutations"] != expected_mutations or r["starts"] != expected_sdk:
        raise EvidenceError(f"{path}.receipts: native callback totals")
    if r["outstanding_max"] > 64: raise EvidenceError(f"{path}: outstanding limit")
    if label is not None and x.get("label") != label: raise EvidenceError(f"{path}: boundary label")
    if samples:
        batches, values = need(x.get("batch_ns"), f"{path}.batch_ns", list), need(x.get("samples_ns"), f"{path}.samples_ns", list)
        if len(batches) != 7 or len(values) != 2000: raise EvidenceError(f"{path}: raw timing cardinality")
        for i, value in enumerate(batches + values): number(value, f"{path}.raw[{i}]", 1)
    return x

def receiver_phase(x, path, row, operations, registered, instrumented, arm, second_resume):
    delta = keys(need(x, path, dict), ("mutations", "starts", "completions", "body_bytes", "metrics"), path)
    expected_sdk = operations if instrumented else 0
    if row == "data": body = 1280 * expected_sdk
    elif row == "completion": body = 0
    elif row == "state": body = 0 if registered else 1024 * expected_sdk
    else: body = 1024 * expected_sdk
    mutation_start = expected_sdk * (2 if arm == "A" and second_resume else 1)
    expected = (mutation_start, expected_sdk, expected_sdk, body, operations if registered and instrumented else 0)
    if tuple(integer(delta[key], f"{path}.{key}") for key in ("mutations", "starts", "completions", "body_bytes", "metrics")) != expected:
        raise EvidenceError(f"{path}: SDK receiver receipt")

def validate_p04(plan):
    p = need(need(plan.get("reused_evidence"), "plan.reused_evidence", dict).get("p04_evidence"), "plan.p04", dict)
    if p.get("sha256") != P04_SHA or digest(need(p.get("path"), "plan.p04.path", str)) != P04_SHA: raise EvidenceError("P04 binding mismatch")
    doc = read(p["path"])
    if doc.get("status") != "PASS; S1:P04 CLOSED": raise EvidenceError("P04 status")
    decisive = need(need(doc.get("result"), "P04.result", dict).get("decisive_evidence"), "P04.decisive", dict)
    if any(decisive.get(k) != 3 for k in ("executions", "executed_cases", "selected_discovered_cases")): raise EvidenceError("P04 exact execution structure")
    if len(need(need(doc.get("definition"), "P04.definition", dict).get("selectors"), "P04.selectors", list)) != 3: raise EvidenceError("P04 selector inventory")
    if not need(need(doc.get("reused_evidence"), "P04.reused", dict).get("source_hashes"), "P04.source_hashes", dict): raise EvidenceError("P04 source hashes")
    attempts = need(doc.get("attempts"), "P04.attempts", list)
    if not attempts or not need(need(attempts[0], "P04.attempt", dict).get("run"), "P04.run", dict).get("source"):
        raise EvidenceError("P04 run source")

def plan_valid(plan):
    if plan.get("schema_version") != 5 or plan.get("experiment") != "EXP-198" or plan.get("stage") != "EXECUTION_FROZEN": raise EvidenceError("execution plan identity")
    sha(plan.get("fixture_sha256"), "plan.fixture_sha256"); sha(plan.get("contract_sha256"), "plan.contract_sha256")
    arms = keys(plan.get("arms"), ("A", "B"), "plan.arms")
    for arm, revision in (("A", A_REV), ("B", B_REV)):
        item = need(arms[arm], f"plan.arm.{arm}", dict)
        if item.get("revision") != revision: raise EvidenceError(f"plan arm {arm} revision")
        sha(item.get("source_sha256"), f"plan arm {arm} source"); sha(item.get("build_sha256"), f"plan arm {arm} build")
        if not isinstance(item.get("uuid"), str) or not item["uuid"]:
            raise EvidenceError(f"plan arm {arm} UUID evidence")
        if not isinstance(item.get("app_members"), dict) or not item["app_members"]: raise EvidenceError(f"plan arm {arm} members")
    matrix = need(plan.get("matrix"), "plan.matrix", list)
    if len(matrix) != 32 or len({x.get("cell_id") for x in matrix if isinstance(x, dict)}) != 32: raise EvidenceError("matrix cardinality")
    runtimes = []
    actual = []
    for x in matrix:
        x = need(x, "plan.cell", dict)
        for k in ("cell_id", "runtime_id", "runtime_version", "runtime_build", "tracking", "mode", "arm", "quartet", "ordinal"): need(x.get(k), f"plan.cell.{k}")
        r = (x["runtime_id"], x["runtime_version"], x["runtime_build"])
        if r not in runtimes: runtimes.append(r)
        actual.append((x["quartet"], x["ordinal"], x["arm"], x["runtime_id"], x["tracking"], x["mode"]))
    if len(runtimes) != 2: raise EvidenceError("runtime cardinality")
    expected = []
    for rid, _, _ in runtimes:
        for tracking in ("automatic", "registered"):
            for mode in ("e01-timing", "e01-alloc-retention"):
                expected += [(f"{rid}:{tracking}:{mode}", n, arm, rid, tracking, mode) for n, arm in enumerate(("A", "B", "B", "A"))]
    if sorted(actual) != sorted(expected): raise EvidenceError("matrix ABBA shape")
    validate_p04(plan)
    return plan

def cell_for(summary, plan):
    identity, index = need(summary.get("identity"), "summary.identity", dict), integer(summary.get("index"), "summary.index")
    if summary.get("purpose") == "qualification":
        slots = (("A", "automatic"), ("A", "registered"), ("B", "automatic"), ("B", "registered"))
        if index >= 4 or identity.get("mode") != "qualify" or identity.get("os") != "17.5" or (identity.get("arm"), identity.get("tracking")) != slots[index]: raise EvidenceError("qualification slot")
        return {"cell_id": f"qualification-{index}", "arm": slots[index][0], "tracking": slots[index][1], "mode": "qualify", "runtime_version": "17.5", "runtime_build": "21F79"}
    if summary.get("purpose") != "measurement" or index >= 32: raise EvidenceError("measurement index")
    cell = plan["matrix"][index]
    if any(identity.get(k) != cell[k] for k in ("arm", "tracking")) or identity.get("mode") != cell["mode"]: raise EvidenceError("matrix identity")
    return cell

def identity_valid(summary, native, plan, cell):
    fields = ("run_id", "nonce", "arm", "tracking", "mode", "os", "source_revision", "source_sha256", "fixture_sha256", "build_sha256", "contract_sha256")
    s, n = keys(summary.get("identity"), fields, "summary.identity"), keys(native.get("identity"), fields, "native.identity")
    if s != n: raise EvidenceError("host/native identity")
    uuid_value(s["run_id"], "run_id"); uuid_value(s["nonce"], "nonce")
    if s["run_id"] == s["nonce"]: raise EvidenceError("same run and nonce")
    arm = plan["arms"][cell["arm"]]
    want = {"arm":cell["arm"], "tracking":cell["tracking"], "mode":cell["mode"], "os":cell["runtime_version"], "source_revision":arm["revision"], "source_sha256":arm["source_sha256"], "fixture_sha256":plan["fixture_sha256"], "build_sha256":arm["build_sha256"], "contract_sha256":plan["contract_sha256"]}
    if any(s[k] != v for k, v in want.items()): raise EvidenceError("identity differs from plan")
    if summary.get("state") != "LOCAL_COMPLETE" or native.get("status") != "LOCAL_COMPLETE": raise EvidenceError("raw capture state")
    if any(k in native for k in ("synthetic_pass", "fixture_specific_status", "numeric_verdict", "host_rewritten_rows")): raise EvidenceError("forbidden native verdict")
    for k in ("started_at", "capture_finished_at", "finished_at", "launch_started_at_ns", "result_mtime_ns", "cell_deadline", "window_deadline"): number(summary.get(k), f"summary.{k}", 0)
    if summary["capture_finished_at"] < summary["started_at"] or summary["finished_at"] < summary["capture_finished_at"] or summary["result_mtime_ns"] < summary["launch_started_at_ns"] or summary["capture_finished_at"] > summary["cell_deadline"] or summary["finished_at"] > summary["cell_deadline"]: raise EvidenceError("time boundary")
    if summary["result_mtime_ns"] > int(summary["capture_finished_at"] * 1_000_000_000) or summary.get("native_launches") != 1:
        raise EvidenceError("result freshness or native launch count")
    runtime, device = need(summary.get("runtime"), "summary.runtime", dict), need(summary.get("device"), "summary.device", dict)
    if runtime.get("version") != cell["runtime_version"] or runtime.get("buildversion") != cell.get("runtime_build") or not device:
        raise EvidenceError("runtime/device binding")
    if cell["mode"] != "qualify":
        if summary.get("matrix_started_at") is None or summary.get("matrix_deadline") is None or summary["matrix_deadline"] - summary["matrix_started_at"] != 10800 or summary["finished_at"] - summary["matrix_started_at"] > 10800:
            raise EvidenceError("matrix time boundary")
    host, cleanup = need(summary.get("host"), "summary.host", dict), need(summary.get("cleanup"), "summary.cleanup", dict)
    for k in ("preflight", "clean_install", "installed_binary_match", "no_competing_workload", "cleanup", "timebox"):
        if host.get(k) is not True: raise EvidenceError(f"host.{k}")
    for k in ("container_absent", "process_absent", "binding_restored", "protected_unchanged", "source_unchanged", "helpers_unchanged"):
        if cleanup.get(k) is not True: raise EvidenceError(f"cleanup.{k}")
    if cleanup.get("errors") != []: raise EvidenceError("cleanup errors")

def common_valid(native, arm, tracking):
    roundtrip = need(native.get("native_roundtrip"), "native.roundtrip", dict)
    if not isinstance(roundtrip.get("task_identity"), str) or not roundtrip["task_identity"] or roundtrip.get("prepared_header") is not None and not isinstance(roundtrip.get("prepared_header"), str) or roundtrip.get("native_body_bytes") != 1024 or roundtrip.get("receiver_body_bytes") != 1024 or roundtrip.get("native_completions") != 1 or roundtrip.get("native_errors") != 0: raise EvidenceError("roundtrip identity/body")
    r = receipt(roundtrip.get("receipts"), "roundtrip.receipts")
    if any(r[k] != 1 for k in ("operations", "native_task_lifecycles", "protocol_starts", "protocol_completions", "invalidations", "completions", "native_completions")) or r["errors"] != 0: raise EvidenceError("roundtrip callback counts")
    delta = keys(roundtrip.get("receiver_delta"), ("mutations", "starts", "completions", "body_bytes", "metrics"), "roundtrip.receiver_delta")
    for key in delta: integer(delta[key], f"roundtrip.receiver_delta.{key}")
    if roundtrip.get("metrics_applicability") != ("automatic_inapplicable" if tracking == "automatic" else "registered_observed"): raise EvidenceError("roundtrip metrics applicability")
    if tracking == "registered" and (r["metrics"], delta["metrics"]) != (1, 1): raise EvidenceError("registered metrics receipt")
    completed = need(native.get("completed_task_control"), "completed", dict)
    if any(completed.get(k) is not True for k in ("isolated_feature", "completed_before_repeat", "repeat_resume_attempted")) or completed.get("numeric_credit") is not False: raise EvidenceError("completed control isolation")
    for k in ("native_receipts_before", "native_receipts_after"):
        completed_receipt(completed.get(k), f"completed.{k}")
    expected = ("EXPECTED_BASELINE_NEGATIVE", (1, 1, 0)) if arm == "A" else ("CANDIDATE_PASS", (0, 0, 0))
    delta = need(completed.get("post_completion_receiver_delta"), "completed.delta", dict)
    if completed.get("classification") != expected[0] or tuple(delta.get(k) for k in ("mutations", "starts", "completions")) != expected[1]: raise EvidenceError("completed arm discriminator")
    teardown = need(native.get("teardown"), "teardown", dict)
    if teardown.get("selector") != "resume" or teardown.get("equal") is not True or not teardown.get("class") or teardown.get("imp_before") != teardown.get("imp_after") or teardown.get("imp_before") in (None, "", "0", "0x0"): raise EvidenceError("IMP restoration")
    post = need(teardown.get("native_receipt"), "teardown.receipt", dict)
    if (post.get("native_completions"), post.get("native_body_bytes"), post.get("native_invalidation")) != (1, 1024, 1): raise EvidenceError("post-release native forwarding")
    release = need(native.get("final_release"), "final_release", dict)
    if any(release.get(k) is not True for k in ("feature_alive_before_release", "provider_alive_before_release", "handler_alive_before_release", "feature_released", "provider_released", "handler_released")): raise EvidenceError("vacuous final release")

def controls_valid(data, arm):
    controls = need(data.get("controls"), "controls", dict)
    for k in ("task_hold", "feature_hold"):
        if need(controls.get(k), f"controls.{k}", dict).get("held") is not True or controls[k].get("released") is not True: raise EvidenceError(f"controls.{k}")
    payload = need(controls.get("payload_continuation"), "controls.payload", dict)
    if arm == "A":
        if payload.get("applicability") != "unsupported_on_A": raise EvidenceError("baseline coordinator applicability")
    elif (payload.get("applicability"), payload.get("actual_data"), payload.get("duplicate_resume"), payload.get("nonzero_while_blocked"), payload.get("zero_after_drain")) != ("candidate_B", True, True, True, True):
        raise EvidenceError("candidate payload drain")
    elif any(payload.get(key) != 0 for key in ("drained_events", "drained_continuations")) or any(integer(payload.get(key), f"controls.payload.{key}") <= 0 for key in ("held_events", "held_continuations")):
        raise EvidenceError("candidate event/continuation discriminator")

def timing_valid(data, arm, tracking):
    rows = keys(need(data.get("rows"), "timing.rows", dict), ROWS, "timing.rows")
    for name, row in rows.items():
        if name == "metrics" and tracking == "automatic":
            if row != {"row": "metrics", "applicability":"registered_delegate_only"}: raise EvidenceError("automatic metrics timing")
            continue
        if row.get("row") != name or row.get("instrumentation") != ("sdk_unbound" if name == "unbound_first_resume" else "instrumented"): raise EvidenceError(f"timing.{name} identity")
        work = need(row.get("workload"), f"timing.{name}.workload", dict)
        if any(work.get(k) != v for k,v in {"discarded_warmup_operations":1000,"measured_batches":7,"operations_per_batch":1000,"measured_operations":7000,"individual_samples":2000}.items()): raise EvidenceError(f"timing.{name} workload")
        registered = tracking == "registered"
        instrumented = name != "unbound_first_resume"
        phase(row.get("warmup"), f"timing.{name}.warmup", 1000, registered=registered, second_resume=name == "second_resume_ready", instrumented=instrumented, arm=arm)
        receiver_phase(row["warmup"].get("receiver_delta"), f"timing.{name}.warmup.receiver_delta", name, 1000, registered, instrumented, arm, name == "second_resume_ready")
        a = phase(row.get("caller_return"), f"timing.{name}.caller", 7000, True, "caller entry to return", registered=registered, second_resume=name == "second_resume_ready", instrumented=instrumented, arm=arm)
        receiver_phase(a.get("receiver_delta"), f"timing.{name}.caller.receiver_delta", name, 7000, registered, instrumented, arm, name == "second_resume_ready")
        flush_label = "entry through immediate feature.flush()"
        if name in ("unbound_first_resume", "first_resume"):
            flush_label = "resume through immediate feature flush (already-enqueued SDK work); held start and final flush outside timer"
        elif name == "second_resume_ready":
            flush_label = "second resume through immediate feature flush"
        b = phase(row.get("through_flush"), f"timing.{name}.flush", 7000, True, flush_label, registered=registered, second_resume=name == "second_resume_ready", instrumented=instrumented, arm=arm)
        receiver_phase(b.get("receiver_delta"), f"timing.{name}.flush.receiver_delta", name, 7000, registered, instrumented, arm, name == "second_resume_ready")
        if name == "second_resume_ready":
            for x in (a,b):
                if tuple(x["receipts"][k] for k in ("resume_calls","outstanding_enters","outstanding_leaves")) != (14000,7000,7000): raise EvidenceError("second resume balance")

def counters(x, path):
    x = keys(x, COUNTERS, path); out = {k:integer(x[k], f"{path}.{k}") for k in COUNTERS}
    if out["other_operations"] != out["process_operations"]-out["caller_operations"] or out["other_bytes"] != out["process_bytes"]-out["caller_bytes"]: raise EvidenceError(f"{path}: other counters")
    return out

def allocation_valid(data, arm, tracking):
    calibration = need(data.get("calibration"), "allocation.calibration", dict)
    if any(calibration.get(key) is not True for key in ("completed", "calibration_before_unbound", "lock_free")):
        raise EvidenceError("allocation calibration state")
    calibration_passes = {
        "caller": (3, 165, 3, 165, 0, 0),
        "feature_queue": (3, 165, 0, 0, 3, 165),
        "worker": (3, 165, 0, 0, 3, 165),
        "concurrent": (1200, 66000, 0, 0, 1200, 66000),
    }
    passes = keys(calibration.get("passes"), ("caller", "feature_queue", "worker", "concurrent", "caller_only_negative_rejected"), "allocation.calibration.passes")
    if passes["caller_only_negative_rejected"] is not True:
        raise EvidenceError("allocation calibration caller-only negative")
    for name, expected in calibration_passes.items():
        if passes[name] is not True:
            raise EvidenceError(f"allocation calibration {name} pass")
        observed = counters(need(calibration.get(name), f"calibration.{name}", dict), f"calibration.{name}")
        if tuple(observed[key] for key in COUNTERS) != expected:
            raise EvidenceError(f"allocation calibration {name} observed counters")
    rows = keys(need(data.get("rows"), "allocation.rows", dict), ROWS+("full_task_cycle",), "allocation.rows")
    for name,row in rows.items():
        if name == "metrics" and tracking == "automatic":
            if row != {"row": "metrics", "applicability":"registered_delegate_only"}: raise EvidenceError("automatic metrics allocation")
            continue
        if row.get("row") != name: raise EvidenceError(f"allocation.{name} identity")
        if name == "full_task_cycle":
            if row.get("denominator") != "successful_tasks" or row.get("budget_applies") is not True: raise EvidenceError("full task denominator")
        elif row.get("instrumentation") != ("sdk_unbound" if name == "unbound_first_resume" else "instrumented"):
            raise EvidenceError(f"allocation.{name} instrumentation")
        work = need(row.get("workload"), f"allocation.{name}.workload", dict)
        if any(work.get(k) != v for k,v in {"discarded_warmup_operations":1000,"measured_batches":7,"operations_per_batch":1000,"measured_operations":7000}.items()): raise EvidenceError(f"allocation.{name} workload")
        registered = tracking == "registered"; instrumented = name != "unbound_first_resume"
        phase(row.get("warmup"), f"allocation.{name}.warmup",1000, registered=registered, second_resume=name == "second_resume_ready", instrumented=instrumented, arm=arm); measured = phase(row.get("allocation"), f"allocation.{name}.measured",7000, registered=registered, second_resume=name == "second_resume_ready", instrumented=instrumented, arm=arm)
        batches = need(measured.get("batches"), f"allocation.{name}.batches", list)
        if len(batches) != 7: raise EvidenceError(f"allocation.{name} batches")
        for i,batch in enumerate(batches):
            if batch.get("expected_operations") != 1000: raise EvidenceError("allocation batch denominator")
            phase(batch, f"allocation.{name}.batch[{i}]", 1000, registered=registered, second_resume=name == "second_resume_ready", instrumented=instrumented, arm=arm)
            windows, denoms = need(batch.get("windows"),"windows",list), need(batch.get("window_denominators"),"denoms",list)
            if len(windows)!=16 or len(denoms)!=16 or sum(denoms)!=1000 or any(integer(x,"denom",1)>64 for x in denoms): raise EvidenceError("allocation windows")
            for j,x in enumerate(windows): counters(x,f"allocation.window[{i}][{j}]")
    retention = need(data.get("retention"),"retention",dict)
    for key in ("full_lifetime_churn", "idle_control"):
        diagnostic = need(data.get(key), f"allocation.{key}", dict)
        if diagnostic.get("diagnostic") is not True or diagnostic.get("budget_applies") is True:
            raise EvidenceError(f"allocation.{key} must stay raw-only")
    if retention.get("fresh_cohort") is not True or retention.get("verified_cycles") != 220 or retention.get("interception_liveness_verified_cycles") != 220: raise EvidenceError("retention cohort")
    receiver_delta = keys(retention.get("receiver_delta"), ("mutations", "starts", "completions"), "retention.receiver_delta")
    if any(receiver_delta[key] != 220 for key in receiver_delta):
        raise EvidenceError("retention receiver liveness")
    heaps = need(retention.get("heap_bytes"), "retention.heap_bytes", list)
    if len(heaps) != 3: raise EvidenceError("retention raw heap cardinality")
    heaps = [integer(value, f"retention.heap_bytes[{index}]") for index, value in enumerate(heaps)]
    inventories=need(retention.get("inventories"),"retention.inventories",list)
    if len(inventories)!=3 or [x.get("boundary") for x in inventories] != [20,120,220]: raise EvidenceError("retention boundaries")
    for inv in inventories:
        if inv.get("reflection_available") is not True or any(inv.get(k)!=0 for k in ("interceptions","truncatedInterceptions","task_weak_members","interception_weak_members")): raise EvidenceError("common retained ownership")
        if arm=="B":
            preparations = keys(inv.get("preparations"), ("raw_count_before_enumeration", "live_weak_keys", "remaining_values", "phase_payloads", "events", "continuations", "remaining_key_sequence", "phases"), "retention.preparations")
            terminal = keys(inv.get("weak_terminal_tasks"), ("raw_count_before_enumeration", "live_members"), "retention.terminal_tasks")
            for key, value in preparations.items():
                if key != "phases": integer(value, f"retention.preparations.{key}")
            if not isinstance(preparations["phases"], list) or any(not isinstance(phase_name, str) for phase_name in preparations["phases"]): raise EvidenceError("retention phases")
            for key, value in terminal.items(): integer(value, f"retention.terminal_tasks.{key}")
            if any(preparations[key] != 0 for key in ("live_weak_keys", "remaining_values", "phase_payloads", "events", "continuations")) or terminal["live_members"] != 0:
                raise EvidenceError("candidate retained ownership")
        elif "preparations" in inv or "weak_terminal_tasks" in inv: raise EvidenceError("baseline candidate reflection")
    for k, derived, budget in (("first_100_growth", heaps[1] - heaps[0], 65536), ("second_100_growth", heaps[2] - heaps[1], 16384)):
        if signed_integer(retention.get(k), f"retention.{k}") != derived: raise EvidenceError(f"retention {k} does not equal raw heap delta")
        if arm == "B" and derived > budget: raise ThresholdError(f"retention {k} budget")

def validate_cell(summary, native, execution_plan):
    try:
        plan=plan_valid(need(execution_plan,"plan",dict)); cell=cell_for(summary,plan)
        if native.get("schema_version")!=5: raise EvidenceError("native schema")
        identity_valid(summary,native,plan,cell); common_valid(native,cell["arm"],cell["tracking"])
        mode_data=keys(native.get("mode_data"), ({"qualification"} if cell["mode"]=="qualify" else ({"timing"} if cell["mode"]=="e01-timing" else {"allocation"})),"native.mode_data")
        if cell["mode"]=="qualify": controls_valid(need(mode_data["qualification"],"qualification",dict),cell["arm"])
        elif cell["mode"]=="e01-timing": timing_valid(need(mode_data["timing"],"timing",dict),cell["arm"],cell["tracking"])
        else: allocation_valid(need(mode_data["allocation"],"allocation",dict),cell["arm"],cell["tracking"])
        return {"cell_id":cell["cell_id"],"status":"CELL_VALID","numeric":"NOT_RUN","errors":[]}
    except ThresholdError as e: return {"status":"FAIL","numeric":"NOT_RUN","errors":[str(e)]}
    except EvidenceError as e: return {"status":"INCONCLUSIVE","numeric":"NOT_RUN","errors":[str(e)]}

def stats(values):
    values=sorted(number(x,"sample",1) for x in values); return statistics.median(values),values[math.ceil(.95*len(values))-1]
def timing_compare(a,b,label):
    for boundary in ("caller_return","through_flush"):
        am,ap=stats(a[boundary]["samples_ns"]); bm,bp=stats(b[boundary]["samples_ns"])
        if bm-am>max(.1*am,500) or bp-ap>max(.2*ap,1000): raise ThresholdError(f"{label}:{boundary} timing budget")
def timing_environment_compare(a,b,label):
    for boundary in ("caller_return","through_flush"):
        am,ap=stats(a[boundary]["samples_ns"]); bm,bp=stats(b[boundary]["samples_ns"])
        if abs(bm-am)>max(.1*am,500) or abs(bp-ap)>max(.2*ap,1000): raise ThresholdError(f"{label}:{boundary} A/A environment drift")
def alloc_mean(row):
    ops=bytes_=0
    for batch in row["allocation"]["batches"]:
        for w in batch["windows"]: ops+=w["process_operations"]; bytes_+=w["process_bytes"]
    return ops/7000,bytes_/7000
def alloc_compare(a,b,label):
    ao,ab=alloc_mean(a);bo,bb=alloc_mean(b)
    if bo-ao>max(.05*ao,1) or bb-ab>max(.05*ab,64): raise ThresholdError(f"{label} allocation budget")
def alloc_environment_compare(a,b,label):
    ao,ab=alloc_mean(a);bo,bb=alloc_mean(b)
    if abs(bo-ao)>max(.05*ao,1) or abs(bb-ab)>max(.05*ab,64): raise ThresholdError(f"{label} A/A environment drift")

def timing_pooled_compare(a1,a2,b,label):
    for boundary in ("caller_return","through_flush"):
        am,ap=stats(a1[boundary]["samples_ns"]+a2[boundary]["samples_ns"]); bm,bp=stats(b[boundary]["samples_ns"])
        if bm-am>max(.1*am,500) or bp-ap>max(.2*ap,1000): raise ThresholdError(f"{label}:{boundary} timing budget")

def alloc_pooled_compare(a1,a2,b,label):
    a1o,a1b=alloc_mean(a1); a2o,a2b=alloc_mean(a2); bo,bb=alloc_mean(b); ao,ab=(a1o+a2o)/2,(a1b+a2b)/2
    if bo-ao>max(.05*ao,1) or bb-ab>max(.05*ab,64): raise ThresholdError(f"{label} allocation budget")

def evaluate_matrix(execution_plan, cell_dirs):
    try:
        plan=plan_valid(need(execution_plan,"plan",dict))
        if len(cell_dirs)!=32: raise EvidenceError("matrix cell count")
        discovered={}; results=[]
        for directory in map(Path,cell_dirs):
            summary,native=read(directory/"summary.json"),read(directory/"local.json")
            if summary.get("local_result_sha256")!=digest(directory/"local.json"): raise EvidenceError("raw local bytes differ")
            verdict=validate_cell(summary,native,plan); results.append({**verdict,"path":str(directory)})
            if verdict["status"]!="CELL_VALID": return {"status":verdict["status"],"numeric":"NOT_RUN","cell_results":results}
            if summary.get("purpose")!="measurement" or verdict["cell_id"] in discovered: raise EvidenceError("non-measurement or duplicate cell")
            discovered[verdict["cell_id"]]=native
        if set(discovered)!={x["cell_id"] for x in plan["matrix"]}: raise EvidenceError("matrix discovered set")
        for quartet in {x["quartet"] for x in plan["matrix"]}:
            q=sorted((x for x in plan["matrix"] if x["quartet"]==quartet),key=lambda x:x["ordinal"]); mode=q[0]["mode"]; key="timing" if mode=="e01-timing" else "allocation"
            for row in ROWS+(("full_task_cycle",) if key=="allocation" else ()):
                if row=="metrics" and q[0]["tracking"]=="automatic": continue
                values=[discovered[x["cell_id"]]["mode_data"][key]["rows"][row] for x in q]
                compare=timing_environment_compare if key=="timing" else alloc_environment_compare
                pooled=timing_pooled_compare if key=="timing" else alloc_pooled_compare
                compare(values[0],values[3],f"{quartet}:{row}:A/A"); pooled(values[0],values[3],values[1],f"{quartet}:{row}:B1-vs-pooled-A"); pooled(values[0],values[3],values[2],f"{quartet}:{row}:B2-vs-pooled-A")
        return {"status":"PASS","numeric":"P01_P02_P03_QUALIFIED","cell_count":32,"cell_results":results}
    except ThresholdError as e: return {"status":"FAIL","numeric":"NOT_RUN","errors":[str(e)]}
    except EvidenceError as e: return {"status":"INCONCLUSIVE","numeric":"NOT_RUN","errors":[str(e)]}
