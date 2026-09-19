#!/usr/bin/env python3
"""Compare automatic coverage without turning pre-existing limits into passes."""
import argparse
from collections import Counter
import json
from pathlib import Path


def require(value, message):
    if not value: raise ValueError(message)


def qualify(run, rows, receipts, summary):
    ident = run["run_id"]
    require(run.get("clean_install") is True and run.get("cleanup") is True, "install/cleanup absent")
    require(run.get("test_exit") == 0, "native UI test failed")
    require(summary.get("passedTests") == 1 and summary.get("failedTests") == 0, "test summary not one decisive pass")
    require(rows and receipts, "missing event/receipt inventory")
    require(all(row.get("run_id") == ident for row in rows + receipts), "stale run identifier")
    require([row["sequence"] for row in rows] == list(range(1, len(rows) + 1)), "missing/reordered native observation")
    launches = [row for row in rows if row["kind"] == "launch"]
    require(len(launches) == 1, "restored or duplicate launch")
    launch = launches[0]["payload"]
    require(launch["framework"] == run["framework"] and launch["layout"] == run["layout"], "wrong fixture")
    require(launch["multiple_scenes"] is False, "not a declared single-scene app")
    require(any(row["kind"] == "geometry" for row in rows), "no native geometry")
    backgrounds = [row for row in rows if row["kind"] == "native_background"]
    require(bool(backgrounds), "missing final action drain boundary")
    require(bool(run.get("installed")) and all(v.get("binaries") for v in run["installed"].values()), "installed identity absent")
    phases = [r["phase"] for r in receipts]
    require(len(phases) == len(set(phases)), "duplicate input phase")
    require(phases[0] == "launch" and "complete" in phases and phases[-1] == "terminated", "incomplete input sequence")
    expected = ["root.tap.effect", "root.toggle.effect", "root.scroll.effect", "navigate.effect",
                "detail.tap.effect", "detail.toggle.effect", "detail.scroll.effect", "present.effect", "dismiss.effect", "back.effect"]
    for prefix in (["initial", "inner"] if run["poses"] else ["initial"]):
        require(all(prefix + "." + e in phases for e in expected), "missing native outcome")
        for stage in ["root.tap", "detail.tap", "sheet.tap", "detail.return.tap", "root.return.tap"]:
            require(prefix + "." + stage + ".delivered" in phases, "missing native tap delivery")
    require(all(receipts[i]["timestamp"] <= receipts[i+1]["timestamp"] for i in range(len(receipts)-1)), "reordered boundary timestamps")
    for receipt in receipts:
        if receipt["phase"].endswith(".effect"):
            stem = receipt["phase"][:-7]
            prior = [r for r in receipts if r["phase"] == stem + ".before"]
            require(len(prior) == 1 and prior[0]["timestamp"] <= receipt["timestamp"], "effect lacks pre-input boundary")
    boundaries = [r for r in receipts if r["phase"].endswith(".before")]
    for index, boundary in enumerate(boundaries):
        target = boundary["payload"].get("target", "")
        if target and not target.endswith(".next"):
            end = boundaries[index+1]["timestamp"] if index+1 < len(boundaries) else receipts[-1]["timestamp"]
            effects = [r for r in rows if r["kind"] == "native_input" and r["payload"].get("name") == target
                       and boundary["timestamp"] <= r["timestamp"] < end]
            require(len(effects) == 1, "missing/duplicate native callback: " + target)
    final_background = next((r for r in receipts if r["phase"] == "background.before"), None)
    require(final_background is not None and any(final_background["timestamp"] <= row["timestamp"] for row in backgrounds), "background boundary was stale")
    if run["poses"]:
        for name in ["open", "close", "reopen"]:
            require("await-" + name in phases and "received-" + name in phases, "missing pose boundary")
            receipt = next(r for r in receipts if r["phase"] == "received-" + name)
            payload = receipt["payload"]
            require(payload.get("run_id") == ident and isinstance(payload.get("geometry_sequence"), int), "unqualified pose receipt")
            geometry = next((r for r in rows if r["sequence"] == payload["geometry_sequence"]), None)
            require(geometry is not None and geometry["kind"] == "geometry", "unknown pose geometry")
            requested = next(r["timestamp"] for r in receipts if r["phase"] == "await-" + name)
            require(requested <= geometry["timestamp"] <= receipt["timestamp"], "stale or late pose geometry")
    return launch


def summarize(run, rows, receipts):
    events = [r["payload"] for r in rows if r["kind"] == "rum"]
    views = {}; actions = []; errors = []
    for e in events:
        kind = e.get("type")
        if kind == "view":
            view = e["view"]; ident = view["id"]
            if ident not in views:
                views[ident] = {"name": view.get("name"), "url": view.get("url"), "date": e.get("date"), "index": len(views)}
        elif kind == "action": actions.append(e)
        elif kind == "error": errors.append(e)
    require(not any(e["action"]["type"] == "custom" for e in actions), "manual action contaminated automatic comparison")
    dates = sorted((r["timestamp"], r["phase"][:-7]) for r in receipts if r["phase"].endswith(".before") and r["phase"] != "background.before")
    automatic = [e for e in actions if e["action"]["type"] != "application_start"]
    coverage = []
    for index, (start, phase) in enumerate(dates):
        end = dates[index + 1][0] if index + 1 < len(dates) else next(r["timestamp"] for r in receipts if r["phase"] == "complete")
        selected = [e for e in automatic if start <= e["date"] / 1000 < end]
        coverage.append({"phase": phase, "actions": [{"type": e["action"]["type"], "name": e["action"].get("target", {}).get("name"),
            "owner_index": views.get(e["view"]["id"], {}).get("index"), "owner_name": views.get(e["view"]["id"], {}).get("name"),
            "id": e["action"]["id"], "view_id": e["view"]["id"]} for e in selected]})
    assigned = {a["id"] for row in coverage for a in row["actions"]}
    initial_end = next((r["timestamp"] for r in receipts if r["phase"] == "await-open"), receipts[-1]["timestamp"])
    initial_views = [v for v in views.values() if v["date"] / 1000 < initial_end]
    return {"run_id": run["run_id"], "cell": [run["build"], run["device"], run["framework"], run["layout"]],
            "views": list(views.values()), "initial_views": initial_views, "view_count": len(views), "automatic_action_count": len(automatic),
            "action_types": dict(Counter(e["action"]["type"] for e in automatic)), "coverage": coverage,
            "missing_action_phases": [c["phase"] for c in coverage if not c["actions"]],
            "duplicate_action_ids": [k for k,v in Counter(e["action"]["id"] for e in automatic).items() if v > 1],
            "unknown_action_owners": [e["action"]["id"] for e in automatic if e["view"]["id"] not in views],
            "unassigned_actions": [e["action"]["id"] for e in automatic if e["action"]["id"] not in assigned],
            "errors": errors, "native_appearances": [r["payload"]["screen"] for r in rows if r["kind"] == "native_appear"],
            "geometry": [r for r in rows if r["kind"] == "geometry"], "proof": "LOCAL_MAPPER"}


def normalized(value, family, initial_only=False):
    if family == "views": return [(v["name"], v["url"]) for v in value["initial_views"] if initial_only] if initial_only else [(v["name"], v["url"]) for v in value["views"]]
    # IDs vary across runs; occurrence ordinal preserves fresh/retained ownership.
    return [(c["phase"], [(a["type"], a["name"], a["owner_index"], a["owner_name"]) for a in c["actions"]]) for c in value["coverage"] if not initial_only or c["phase"].startswith("initial.")]


def compare(before, after, family, initial_only=False):
    faults = [k for k in ["duplicate_action_ids", "unknown_action_owners", "unassigned_actions", "errors"] if after[k]]
    if faults: return {"status": "REVIEW_REQUIRED", "reasons": faults}
    if normalized(before, family, initial_only) != normalized(after, family, initial_only):
        return {"status": "DIFFERENCE_REQUIRES_CLASSIFICATION", "before": normalized(before, family, initial_only), "after": normalized(after, family, initial_only)}
    limitation = bool(after["missing_action_phases"]) if family == "actions" else after["view_count"] == 0 or any("Fallback" in (v["name"] or "") for v in after["views"])
    return {"status": "UNCHANGED_LIMITATION" if limitation else "UNCHANGED_OBSERVED_COVERAGE"}


def analyze(attempt):
    m = json.loads((attempt / "manifest.json").read_text()); result = {"experiment": "EXP-195", "cells": [], "comparisons": [], "boundary": "Local mapper comparison; not backend or physical proof"}
    accepted = {}
    for run in m["runs"]:
        d = Path(run["directory"])
        try:
            rows = [json.loads(l) for l in (d / "events.jsonl").read_text().splitlines()]
            receipts = json.loads((d / "receipts.json").read_text()); summary = json.loads((d / "test-summary.json").read_text())
            build = m["builds"][run["build"]]
            require(all(run["installed"][fw] == build["apps"][fw]["identity"] for fw in ["UIKit", "SwiftUI"]), "frozen/installed code mismatch")
            launch = qualify(run, rows, receipts, summary)
            require(launch["build_sdk"] == "iphonesimulator" + build["sdk"], "wrong build SDK")
            item = summarize(run, rows, receipts); item["state"] = "QUALIFIED_INPUT"
            accepted[tuple(item["cell"])] = item
        except (ValueError, KeyError, FileNotFoundError) as e:
            item = {"run_id": run["run_id"], "cell": [run["build"], run["device"], run["framework"], run["layout"]], "state": "UNQUALIFIED_INPUT", "reason": str(e)}
        result["cells"].append(item)
    for key, current in accepted.items():
        build, device, fw, layout = key
        arm, sdk = build.split("-")
        comparisons = []
        if sdk == "27.1": comparisons.append(("rebuild", (arm + "-26.5", device, fw, layout)))
        if arm == "candidate": comparisons.append(("SDK change", ("baseline-" + sdk, device, fw, layout)))
        if device == "duo": comparisons.append(("device plus OS patch", (build, "regular", fw, layout)))
        for axis, baseline_key in comparisons:
            if baseline_key in accepted:
                for family in ["views", "actions"]:
                    result["comparisons"].append({"axis": axis, "family": family, "before_cell": baseline_key, "after_cell": key, **compare(accepted[baseline_key], current, family, initial_only=axis == "device plus OS patch")})
    return result

if __name__ == "__main__":
    p=argparse.ArgumentParser();p.add_argument("attempt", type=Path);p.add_argument("--output",type=Path,required=True);a=p.parse_args()
    result=analyze(a.attempt);a.output.write_text(json.dumps(result,indent=2)+"\n")
    print(json.dumps({"cells":len(result["cells"]), "states":dict(Counter(c["state"] for c in result["cells"])),"comparisons":len(result["comparisons"])}))
