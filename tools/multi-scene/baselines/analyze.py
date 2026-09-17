#!/usr/bin/env python3
"""Evaluate the frozen EXP-160 contract without changing its thresholds."""
import argparse
import gzip
import hashlib
import json
import math
from pathlib import Path
import statistics


def percentile(values, p):
    return sorted(values)[max(0, math.ceil(len(values) * p) - 1)]


def compatibility(result):
    failures = list(result.get("failures", []))
    rows = result.get("events", [])
    views = []
    for row in rows:
        if row["type"] == "view" and row["id"] not in [v["id"] for v in views]:
            views.append(row)
    actual = [v for v in views if v["name"] != "ApplicationLaunch"]
    if [v["name"] for v in actual] != ["Home", "Detail", "Home"]:
        failures.append("wrong occurrence inventory/order")
    if len(actual) == 3:
        for phase, view in zip(["Home1", "Detail1", "Home2"], actual):
            for kind in ["action", "resource"]:
                events = [r for r in rows if r["type"] == kind and (r.get("name") == phase or r.get("url", "").endswith("/" + phase))]
                if len(events) != 1 or events[0]["owner"] != view["id"]:
                    failures.append(kind + " wrong count/owner for " + phase)
    if len([r for r in rows if r["type"] == "action"]) != 3 or len([r for r in rows if r["type"] == "resource"]) != 3:
        failures.append("unexpected action/resource count")
    if any(r["type"] == "error" for r in rows):
        failures.append("RUM error emitted")
    return failures


def compare(a, b, absolute_median, absolute_p95, relative_median, relative_p95):
    if not a or not b:
        return {"status": "INCONCLUSIVE", "reason": "missing samples"}
    baseline = {"median_ns": statistics.median(a), "p95_ns": percentile(a, .95), "sample_count": len(a)}
    candidate = {"median_ns": statistics.median(b), "p95_ns": percentile(b, .95), "sample_count": len(b)}
    median_delta = candidate["median_ns"] - baseline["median_ns"]
    p95_delta = candidate["p95_ns"] - baseline["p95_ns"]
    median_limit = max(baseline["median_ns"] * relative_median, absolute_median)
    p95_limit = max(baseline["p95_ns"] * relative_p95, absolute_p95)
    return {"status": "PASS" if median_delta <= median_limit and p95_delta <= p95_limit else "FAIL", "baseline": baseline, "candidate": candidate, "median_delta_ns": median_delta, "p95_delta_ns": p95_delta, "median_allowed_delta_ns": median_limit, "p95_allowed_delta_ns": p95_limit}


def abba_issues(runs, mode, manifest):
    issues = []
    if [(r["arm"], r.get("order")) for r in runs] != [("baseline", 0), ("candidate", 1), ("candidate", 2), ("baseline", 3)]:
        issues.append("complete ordered ABBA quartet missing")
    metric = "filtered_touch_event_ns" if mode == "internal" else "dispatch_event_ns"
    batches = "filtered_touch_ns" if mode == "internal" else "dispatch_ns"
    for row in runs:
        if row["status"] != "MEASURED" or not row.get("clean_install"):
            issues.append("missing measured clean launch")
            continue
        data = row["result"].get("internal", {}) if mode == "internal" else row["result"]
        if row["result"].get("failures") or len(data.get(metric, [])) != 2000 or len(data.get(batches, [])) != 7 or data.get("iterations_per_batch") != 20000:
            issues.append("incomplete workload or fixture failure")
        build = manifest["builds"][row["arm"]][row["lifecycle"]]
        # Original runs bind through the frozen build table; later variants also
        # carry per-launch fingerprints. Neither may contradict that table.
        if row.get("binary_sha256", build["sha256"]) != build["sha256"] or row.get("fixture_sha256", manifest["fixture"]["sha256"]) != manifest["fixture"]["sha256"]:
            issues.append("binary or fixture identity mismatch")
        if mode == "internal" and row["arm"] == "candidate":
            if not data.get("handoff_live_context") or len(data.get("handoff_event_ns", [])) != 2000 or len(data.get("handoff_ns", [])) != 7:
                issues.append("incomplete live handoff workload")
    return sorted(set(issues))


def focused_reentrancy(data):
    value = data.get("focused", {})
    required = {"oracle": "full-RUMCoreContext-Equatable-and-handoff-fields-v1", "iterations": 10000,
                "live_home_context": True, "original_dispatches": 20000,
                "expected_dispatches": 20000, "boundary_checks": 90000,
                "caught_throws": 10000, "errors": 0, "timing_claim": False}
    if not value:
        return "INCONCLUSIVE"
    return "PASS" if not data.get("failures") and all(value.get(k) == v for k, v in required.items()) else "FAIL"


def analyze(manifest):
    result = {key: manifest[key] for key in ["experiment", "created_at", "revisions", "definition_sha256", "fixture", "xcode", "builds", "devices", "invalid_attempts"]}
    result["verification"] = manifest.get("verification", {})
    result["source_fingerprints"] = {arm: {k: v for k, v in data["sdk_sources"].items() if k != "files"} for arm, data in manifest["arms"].items()}
    result["compatibility"] = []
    result["performance"] = {}
    result["runs"] = manifest["runs"]
    result["commands"] = manifest["commands"]
    result["fixture_smoke"] = manifest.get("fixture_smoke", [])
    gates = {}
    for run in manifest["runs"]:
        if run["mode"] not in ["automatic", "manual"]:
            continue
        failures = compatibility(run["result"]) if run["status"] == "MEASURED" else [run["reason"]]
        if run["status"] == "MEASURED":
            data = run["result"]
            if run["lifecycle"] == "Legacy" and data["has_scene_manifest"]:
                failures.append("legacy app acquired scene lifecycle")
            if run["lifecycle"] == "Scene" and (not data["has_scene_manifest"] or data["scene_count"] != 1):
                failures.append("ordinary app did not have exactly one scene")
        result["compatibility"].append({"arm": run["arm"], "lifecycle": run["lifecycle"], "os": run["os"], "mode": run["mode"], "status": "INCONCLUSIVE" if run["status"] != "MEASURED" else "FAIL" if failures else "PASS", "failures": failures, "run_id": run["run_id"]})
    for gate, predicate, required in [("C01", lambda r: r["lifecycle"] == "Scene" and r["mode"] == "automatic", 4), ("C02", lambda r: r["lifecycle"] == "Scene" and r["mode"] == "manual", 4), ("C03", lambda r: r["lifecycle"] == "Legacy", 8)]:
        subset = [r for r in result["compatibility"] if predicate(r)]
        gates[gate] = "PASS" if len(subset) == required and all(r["status"] == "PASS" for r in subset) else "FAIL" if any(r["status"] == "FAIL" for r in subset) else "INCONCLUSIVE"
    custom_results, retention_results, reentrancy_results = [], [], []
    for os_version in manifest["devices"]:
        all_by_os = [r for r in manifest["runs"] if r["os"] == os_version]
        by_os = [r for r in all_by_os if r["status"] == "MEASURED"]
        performance = {}
        for mode, metric in [("disabled", "dispatch_event_ns"), ("dispatch", "dispatch_event_ns"), ("internal", "filtered_touch_event_ns")]:
            samples = {}
            for arm in ["baseline", "candidate"]:
                runs = [r for r in by_os if r["mode"] == mode and r["arm"] == arm]
                samples[arm] = [v for r in runs for v in (r["result"].get("internal", {}) if mode == "internal" else r["result"]).get(metric, [])]
            performance[mode] = compare(samples["baseline"], samples["candidate"], 500, 1000, .10, .20)
            issues = abba_issues([r for r in all_by_os if r["mode"] == mode], mode, manifest)
            performance[mode]["integrity"] = {"status": "PASS" if not issues else "INCONCLUSIVE", "issues": issues}
            if issues: performance[mode]["status"] = "INCONCLUSIVE"
        internal = [r for r in by_os if r["mode"] == "internal"]
        candidate = [r["result"]["internal"] for r in internal if r["arm"] == "candidate"]
        performance["handoff"] = compare([v for r in candidate for v in r["filtered_touch_event_ns"]], [v for r in candidate for v in r["handoff_event_ns"]], 5000, 10000, 0, 0)
        for allocation_key in ["allocations", "handoff_allocations"]:
            allocation = {arm: [r["result"]["internal"].get(allocation_key, {}) for r in internal if r["arm"] == arm] for arm in ["baseline", "candidate"]}
            if all(len(values) == 2 and all(r.get("calibrated") for r in values) for values in allocation.values()):
                metrics = {arm: {"count_per_event": statistics.median(r["count"] / r["events"] for r in values), "bytes_per_event": statistics.median(r["requested_bytes"] / r["events"] for r in values)} for arm, values in allocation.items()}
                delta_count = metrics["candidate"]["count_per_event"] - metrics["baseline"]["count_per_event"]
                delta_bytes = metrics["candidate"]["bytes_per_event"] - metrics["baseline"]["bytes_per_event"]
                metrics["status"] = "PASS" if delta_count <= max(.05 * metrics["baseline"]["count_per_event"], 1) and delta_bytes <= max(.05 * metrics["baseline"]["bytes_per_event"], 64) else "FAIL"
                metrics["excess_count_per_event"] = delta_count
                metrics["excess_bytes_per_event"] = delta_bytes
                performance[allocation_key] = metrics
            else:
                performance[allocation_key] = {"status": "INCONCLUSIVE", "reason": "counter missing or calibration failed", "raw": allocation}
        for run in internal:
            value = run["result"]["internal"]
            compat = value["compatibility"]
            custom_results.append({"os": os_version, "arm": run["arm"], "status": "PASS" if compat["custom_calls"] == compat["expected_calls"] and compat["nop_nil_callbacks"] == 1 else "FAIL", **compat})
            if run["arm"] == "candidate":
                nested = value["reentrancy"]
                reentrancy_results.append({"os": os_version, "status": "PASS" if nested["errors"] == 0 and nested["original_dispatches"] == nested["expected_dispatches"] and value.get("handoff_live_context") else "FAIL", **nested})
                retained = value["retention"]
                heap = retained["heap_bytes"]
                registry = retained["registry_after_200"]
                retained_pass = retained["surviving_controller_references"] == 0 and all(v == 0 for v in registry.values()) and heap[1] - heap[0] <= 65536 and heap[2] - heap[1] <= 16384
                retention_results.append({"os": os_version, "status": "PASS" if retained_pass else "FAIL", "first_100_heap_delta": heap[1] - heap[0], "second_100_heap_delta": heap[2] - heap[1], **retained})
        if performance["internal"]["integrity"]["issues"]:
            for key in ["handoff", "allocations", "handoff_allocations"]:
                performance[key]["status"] = "INCONCLUSIVE"
        result["performance"][os_version] = performance
    def combine(values, expected):
        return "FAIL" if "FAIL" in values else "PASS" if len(values) == expected and set(values) == {"PASS"} else "INCONCLUSIVE"
    gates["C04"] = combine([r["status"] for r in custom_results], 8)
    gates["C05"] = combine([r["status"] for r in result["compatibility"] if r["os"] == "26.5"] + [r["status"] for r in custom_results if r["os"] == "26.5"], 12)
    gates["C06"] = "ENVIRONMENT BLOCKED"
    gates["P01"] = combine([p[key]["status"] for p in result["performance"].values() for key in ["disabled", "dispatch", "internal", "handoff"]], 8)
    gates["P02"] = combine([p[k]["status"] for p in result["performance"].values() for k in ["allocations", "handoff_allocations"]], 4)
    gates["P03"] = combine([r["status"] for r in retention_results], 4)
    focused = [{"os": r["os"], "run_id": r["run_id"], "status": focused_reentrancy(r["result"]) if r["status"] == "MEASURED" else "INCONCLUSIVE", **r.get("result", {}).get("focused", {})} for r in manifest["runs"] if r["mode"] == "focused"]
    gates["P04"] = combine([r["status"] for r in focused], 2)
    if {r["os"] for r in focused} != set(manifest["devices"]): gates["P04"] = "INCONCLUSIVE"
    lifecycle = []
    for mode in ["lifecycle-automatic", "lifecycle-manual"]:
        matched = {r["arm"]: r for r in manifest["runs"] if r["mode"] == mode and r["status"] == "MEASURED"}
        if set(matched) != {"baseline", "candidate"}:
            lifecycle.append({"mode": mode, "status": "INCONCLUSIVE", "reason": "missing actual OS lifecycle pair"})
            continue
        signatures = {}
        for arm, run in matched.items():
            data = run["result"]
            rows = data["events"]
            views = []
            for row in rows:
                if row["type"] == "view" and row["name"] != "ApplicationLaunch" and row["id"] not in [v["id"] for v in views]:
                    views.append(row)
            identifiers = {v["id"]: i for i, v in enumerate(views)}
            signatures[arm] = {
                "view_names": [v["name"] for v in views],
                "owners": [{"kind": r["type"], "phase": r.get("name", r.get("url", "")), "view_occurrence": identifiers.get(r["owner"], -1)} for r in rows if r["type"] in ["action", "resource"]],
                "view_was_stopped": [any(r.get("id") == v["id"] and r["type"] == "view" and r.get("active") is False for r in rows) for v in views],
                "notifications": [r["name"] for r in rows if r["type"] == "lifecycle"],
                "failures": data["failures"],
                "scene_manifest": data["has_scene_manifest"],
            }
        passed = signatures["baseline"] == signatures["candidate"] and not signatures["baseline"]["failures"] and not signatures["baseline"]["scene_manifest"]
        lifecycle.append({"mode": mode, "os": "26.5", "status": "PASS" if passed else "FAIL", "signatures": signatures, "run_ids": {a: r["run_id"] for a, r in matched.items()}})
    if any(r["status"] == "FAIL" for r in lifecycle):
        gates["C03"] = "FAIL"
        gates["C05"] = "FAIL"
    elif any(r["status"] != "PASS" for r in lifecycle):
        gates["C03"] = "INCONCLUSIVE"
        if gates["C05"] == "PASS": gates["C05"] = "INCONCLUSIVE"
    if not manifest.get("verification", {}).get("passed"):
        gates = {gate: "INCONCLUSIVE" if value == "PASS" else value for gate, value in gates.items()}
    result.update(gates=gates, custom_nop=custom_results, retention=retention_results, reentrancy=focused, initial_scene_label_reentrancy=reentrancy_results, legacy_lifecycle=lifecycle)
    result["limitations"] = ["Simulator Release microbenchmarks, not physical-device performance proof.", "Timing records per-event clock overhead in both arms; batch means are also retained.", "Allocation counter observes successful heap allocations on the fixed workload thread, including realloc; it excludes VM allocations and unrelated threads.", "Retention uses injected scene identifiers and posted disconnect on the actual handler; real OS scene and SwiftUI host teardown remain unproven.", "iOS 15 deployment compilation does not prove iOS 15 runtime compatibility.", "No backend ingestion claim: mapper events are the compatibility oracle; fixture endpoint is loopback with a dummy token."]
    return result


def write_results(attempt, output):
    manifest = json.loads((attempt / "manifest.json").read_text())
    result = analyze(manifest)
    output.parent.mkdir(parents=True, exist_ok=True)
    raw_path = output.with_name(output.stem + "-samples.json")
    raw = {"runs": result["runs"], "invalid_attempts": result["invalid_attempts"], "fixture_smoke": result.pop("fixture_smoke", []), "fixture_history": manifest.get("fixture_history", [])}
    raw_path.write_text(json.dumps(raw, separators=(",", ":")) + "\n")
    logs_path = attempt / "build-logs.json.gz"
    logs = {str(p.relative_to(attempt)): p.read_text() for p in sorted(attempt.glob("*/*.log"))}
    logs_path.write_bytes(gzip.compress(json.dumps(logs).encode(), mtime=0))
    result["raw_data_file"] = raw_path.name
    result["build_logs"] = {"local_artifact": str(logs_path), "count": len(logs), "sha256": hashlib.sha256(logs_path.read_bytes()).hexdigest(), "disposition": "Local diagnostic artifact only; not committed", "logs": [{"path": str(attempt / name), "sha256": hashlib.sha256(text.encode()).hexdigest()} for name, text in logs.items()]}
    result["runs"] = [{k: v for k, v in row.items() if k != "result"} for row in result["runs"]]
    result["invalid_attempts"] = [{k: v for k, v in row.items() if k != "runs"} for row in result["invalid_attempts"]]
    output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result["gates"], indent=2))
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("attempt", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    write_results(args.attempt, args.output)


if __name__ == "__main__":
    main()
