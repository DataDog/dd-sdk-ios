"""EXP-193: exact ownership across a finite native adaptive split sequence."""
import argparse
import json
from pathlib import Path

def is_marker_work(signal):
    return (signal["kind"] == "rum-resource" or
            (signal["kind"] == "rum-action" and signal.get("action", {}).get("type") == "custom"))


SCENARIO = "swiftui.split.adaptive-accepted-state"
# Name, accepted screen, generation, size class, native dimensions, fresh geometry.
PHASES = [
    ("empty-inner", "split-empty", 0, "regular", (669, 951), False),
    ("empty-outer", "split-empty", 0, "compact", (678, 466), True),
    ("empty-inner-return", "split-empty", 0, "regular", (669, 951), True),
    ("detail1", "detail-1", 1, "regular", (669, 951), False),
    ("resize-detail1-regular", "detail-1", 1, "regular", (900, 675), True),
    ("resize-detail1-compact", "detail-1", 1, "compact", (400, 700), True),
    ("resize-detail1-return", "detail-1", 1, "regular", (900, 675), True),
    ("detail1-inner", "detail-1", 1, "regular", (669, 951), True),
    ("detail1-outer", "detail-1", 1, "compact", (678, 466), True),
    ("detail1-inner-return", "detail-1", 1, "regular", (669, 951), True),
    ("detail2", "detail-2", 2, "regular", (669, 951), False),
    ("placeholder", "placeholder", 3, "regular", (669, 951), False),
    ("detail1-return", "detail-1", 4, "regular", (669, 951), False),
    ("clear", "split-empty", 5, "regular", (669, 951), False),
]
MANIFEST = {
    "identifier": SCENARIO, "trackingMode": "navigation-occurrence",
    "layout": "split-selection", "defaultRunMode": "clean", "initialWindows": ["scene-A"],
    "requiredCapabilities": ["regular-width", "resizable-window"],
    "steps": [{"kind": "wait-for-scene-ready", "scene": "scene-A"}],
    "completionConditions": [{"kind": "scene-ready", "scene": "scene-A"}],
    "expectedSemanticTimeline": [],
}
POSE_PHASES = PHASES[:4] + PHASES[8:]
RESIZE_PHASES = [PHASES[0], PHASES[3]] + PHASES[4:7]

PHYSICAL_RESIZE_PHASES = [
    ("empty-physical-full", "split-empty", 0, "regular", (1194, 834), False),
    ("detail1-physical-full", "detail-1", 1, "regular", (1194, 834), False),
    ("detail1-physical-compact", "detail-1", 1, "compact", (592, 834), True),
    ("detail1-physical-return", "detail-1", 1, "regular", (1194, 834), True),
]


def phase_specs(mode):
    return {"full": PHASES, "pose": POSE_PHASES, "resize": RESIZE_PHASES, "physical-resize": PHYSICAL_RESIZE_PHASES}[mode]


def marker_name(mode, ordinal):
    return ("adaptive-resize-" + str(ordinal - 2) if mode in ("resize", "physical-resize") and ordinal >= 3
            else "adaptive-marker-" + str(ordinal))


NAMES = {"split-empty": "ProbeSplitEmptyView", "detail-1": "ProbeSplitDetailView",
         "detail-2": "ProbeSplitDetailView", "placeholder": "ProbeSplitPlaceholderView"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique(rows, label):
    require(len(rows) == 1, label + " must occur exactly once")
    return rows[0]


def validate_native(records, phases, run_id, mode="full"):
    specs = phase_specs(mode)
    scenario = "swiftui.split.adaptive-resize" if mode in ("resize", "physical-resize") else SCENARIO
    manifest_contract = dict(MANIFEST, identifier=scenario)
    accepted_screens = ("detail-1",) if mode in ("resize", "physical-resize") else (
        "detail-1", "detail-2", "placeholder", "detail-1", "split-empty"
    )
    manifest = unique([r["manifest"] for r in records if r["type"] == "manifest"], "manifest")
    require(manifest["runID"] == run_id and manifest["runMode"] == "clean", "stale manifest")
    require(not manifest["validationErrors"] and manifest["scenario"]["identifier"] == scenario,
            "wrong scenario or invalid manifest")
    require(manifest.get("schemaVersion") == 3, "manifest schema")
    require(all(manifest["scenario"].get(k) == v for k, v in manifest_contract.items()), "changed scenario")
    signals = [r["signal"] for r in records if r["type"] == "signal"]
    require(all(s.get("schemaVersion") == 5 for s in signals), "signal schema")
    require([s["sequence"] for s in signals] == list(range(1, len(signals) + 1)), "incomplete sequence")
    require(all(s["runID"] == run_id and s["scenarioID"] == scenario for s in signals), "stale signal")
    require([p["name"] for p in phases] == [p[0] for p in specs], "finite phase sequence changed")
    require(not any(s["kind"] == "rum-error" for s in signals), "unexpected RUM error")
    native_ids = {s["semanticContext"]["nativeSceneID"] for s in signals
                  if s.get("semanticContext", {}).get("nativeSceneID")}
    require(len(native_ids) == 1, "native scene identity changed")
    native_id = next(iter(native_ids))
    require(all(s.get("activationState") not in ("background", "unattached")
                for s in signals if s["kind"] in ("scene-lifecycle", "scene-geometry")),
            "background/disconnect requires a separate lifecycle contract")
    owners, session_ids = {}, set()
    pairs = {}
    for s in signals:
        if is_marker_work(s) and s.get("name", "").startswith("adaptive-"):
            require(s["evidenceSource"] == "rum-mapper", "non-mapper work")
            key = (s["name"], s["kind"])
            require(key not in pairs, "duplicate adaptive work")
            pairs[key] = s
            session_ids.add(s["rumContext"]["sessionID"])
    require(len(session_ids) == 1, "session identity changed")

    def pair(name, screen, generation):
        action = pairs.get((name, "rum-action"))
        resource = pairs.get((name, "rum-resource"))
        require(action is not None and resource is not None, "missing work pair " + name)
        for event in (action, resource):
            context = event["sourceContext"]
            require(context["logicalSceneID"] == "scene-A" and context["nativeSceneID"] == native_id
                    and context["screen"] == screen, "wrong work source " + name)
            rum = event["rumContext"]
            snapshots = [s for s in signals if s["kind"] == "rum-view-snapshot"
                         and s["rumContext"]["viewID"] == rum["viewID"]]
            require(snapshots and all(
                s["evidenceSource"] == "rum-mapper" and
                s.get("semanticContext", {}).get("logicalSceneID") == "scene-A" and
                s.get("semanticContext", {}).get("nativeSceneID") == native_id and
                s.get("semanticContext", {}).get("screen") == screen
                for s in snapshots), "wrong semantic view owner " + name)
            require(rum["viewName"] == NAMES[screen], "structural/wrong view owner " + name)
            owner = owners.setdefault(generation, rum["viewID"])
            require(owner == rum["viewID"], "owner changed without accepted commit " + name)
        require(action["sequence"] < resource["sequence"], "resource precedes action")
        return action, resource

    previous_end = 0
    for ordinal, (phase, spec) in enumerate(zip(phases, specs), 1):
        name, screen, generation, size_class, dimensions, fresh = spec
        require(previous_end <= phase["request_sequence"] < phase["end_sequence"], "phase ordering")
        action, resource = pair(marker_name(mode, ordinal), screen, generation)
        require(phase["request_sequence"] < action["sequence"] < resource["sequence"]
                <= phase["end_sequence"], "marker outside measured phase")
        geometry = unique([s for s in signals if s["sequence"] == phase["geometry_sequence"]],
                          "geometry receipt")
        require(geometry["kind"] in ("scene-ready", "scene-lifecycle", "scene-geometry")
                and geometry["evidenceSource"] == "probe", "geometry source")
        require(geometry["sequence"] < action["sequence"], "late geometry")
        require(not fresh or geometry["sequence"] > phase["request_sequence"], "stale geometry")
        require(geometry["horizontalSizeClass"] == size_class and
                (geometry["geometry"]["width"], geometry["geometry"]["height"]) == dimensions,
                "wrong measured geometry " + name)
        if mode in ("resize", "physical-resize") and ordinal >= 3:
            guard = unique([s for s in signals if s["kind"] == "assertion"
                            and s.get("name") == "adaptive-resize-guard-" + str(ordinal - 2)],
                           "resize live guard")
            require(geometry["sequence"] < guard["sequence"] < action["sequence"]
                    and guard["acknowledgedSignalSequence"] == geometry["sequence"],
                    "late or detached resize guard")
            require(guard.get("result") == "PASS" and guard["evidenceSource"] == "probe"
                    and guard["geometry"] == geometry["geometry"]
                    and guard["horizontalSizeClass"] == size_class
                    and guard["activationState"] == "foreground-active"
                    and guard["navigationPath"] == ["detail-1"]
                    and guard["semanticContext"]["nativeSceneID"] == native_id,
                    "wrong resize live state")
        route = [s for s in signals if s["sequence"] < action["sequence"] and
                 s["kind"] in ("navigation-path-mutation", "scene-ready", "scene-lifecycle", "scene-geometry")
                 and s.get("semanticContext", {}).get("logicalSceneID") == "scene-A"]
        expected_route = [] if screen == "split-empty" else [screen]
        require(route and route[-1]["navigationPath"] == expected_route, "stale route before work")
        previous_end = phase["end_sequence"]

    require(len(owners) == len(accepted_screens) + 1 and len(set(owners.values())) == len(owners), "reused occurrence after commit/return")
    for generation, screen in enumerate(accepted_screens, 1):
        mutation = unique([s for s in signals if s["kind"] == "navigation-path-mutation"
                           and s.get("mutation") == generation], "accepted mutation")
        action, _ = pair("adaptive-commit-" + str(generation), screen, generation)
        require(mutation["sequence"] < action["sequence"], "late accepted route")
        require(mutation["navigationPath"] == ([] if screen == "split-empty" else [screen]),
                "wrong accepted route")
    for generation, screen in enumerate(("split-empty",) + accepted_screens):
        pair("adaptive-materialized-" + str(generation), screen, generation)
    require(len(pairs) == 2 * (len(specs) + len(accepted_screens) * 2 + 1), "unexpected/missing adaptive work")
    first_marker = pairs[("adaptive-marker-1", "rum-action")]["sequence"]
    require(not any(s["kind"] == "rum-view-snapshot" and s["sequence"] >= first_marker
                    and s["rumContext"].get("viewActive") is True
                    and s["rumContext"]["viewID"] not in owners.values()
                    for s in signals), "unexpected active view after acceptance begins")
    views = {s["rumContext"]["viewID"] for s in signals if s["kind"] == "rum-view-snapshot"}
    require(set(owners.values()) <= views, "missing native view owner")
    return {"state": "PASS", "run_id": run_id, "session_id": next(iter(session_ids)),
            "native_scene_id": native_id, "owners": owners, "native_view_ids": sorted(views),
            "work": [{"type": s["kind"].removeprefix("rum-"), "phase": s["name"],
                      "event_id": s["eventID"], "view_id": s["rumContext"]["viewID"]}
                     for s in pairs.values()], "phases": len(specs), "mode": mode}


def validate_backend(native, rows):
    require(all(r["session_id"] == native["session_id"] and r["run_id"] == native["run_id"]
                for r in rows), "backend run/session identity")
    require(not any(r["type"] == "error" for r in rows), "backend error")
    views = [r for r in rows if r["type"] == "view"]
    require(len(views) == len(native["native_view_ids"]) and
            {r["view"]["id"] for r in views} == set(native["native_view_ids"]), "incomplete view inventory")
    work = [r for r in rows if r["type"] in ("action", "resource")]
    require(len(work) == len(native["work"]), "incomplete backend work")
    for expected in native["work"]:
        row = unique([r for r in work if r["type"] == expected["type"]
                      and r[expected["type"]]["id"] == expected["event_id"]], "backend event")
        require(row["view"]["id"] == expected["view_id"], "backend wrong owner")
        require(row["context"].get("probe.phase") == expected["phase"], "backend wrong phase")
    return {"state": "PASS", "view_count": len(views), "work_count": len(work)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("records", type=Path)
    parser.add_argument("phases", type=Path)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--backend", type=Path)
    parser.add_argument("--mode", choices=("full", "pose", "resize", "physical-resize"), default="full")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    records = [json.loads(line) for line in args.records.read_text().splitlines() if line.strip()]
    result = validate_native(records, json.loads(args.phases.read_text()), args.run_id, args.mode)
    if args.backend:
        result["backend"] = validate_backend(result, json.loads(args.backend.read_text()))
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"state": result["state"], "phases": result["phases"]}))


if __name__ == "__main__":
    main()
