import copy
import unittest

import adaptive_split_contract as contract


def fixture(mode="full"):
    run = "adaptive-unit"
    records = [dict(type="manifest", manifest=dict(
        schemaVersion=3, runID=run, runMode="clean", validationErrors=[],
        scenario=copy.deepcopy(contract.MANIFEST)))]
    if mode == "resize":
        records[0]["manifest"]["scenario"]["identifier"] = "swiftui.split.adaptive-resize"
    signals, phases = [], []
    context = dict(logicalSceneID="scene-A", nativeSceneID="native-A")

    def signal(kind, **values):
        item = dict(kind=kind, sequence=len(signals) + 1, runID=run,
                    scenarioID=records[0]["manifest"]["scenario"]["identifier"], schemaVersion=5, evidenceSource="probe")
        item.update(values)
        signals.append(item)
        return item

    def owner(screen, generation):
        return dict(viewID="owner-" + str(generation), sessionID="session",
                    viewName=contract.NAMES[screen])

    def pair(name, screen, generation):
        for kind in ("action", "resource"):
            signal("rum-" + kind, name=name, evidenceSource="rum-mapper",
                   eventID=name + "-" + kind, rumContext=owner(screen, generation),
                   sourceContext=dict(context, screen=screen, phase=name),
                   **({"action": {"type": "custom"}} if kind == "action" else {}))

    last_generation = None
    for ordinal, (name, screen, generation, size_class, dimensions, _) in enumerate(contract.phase_specs(mode), 1):
        request = len(signals)
        if generation != last_generation:
            if generation:
                signal("navigation-path-mutation", semanticContext=dict(context, screen=screen),
                       navigationPath=[] if screen == "split-empty" else [screen], mutation=generation)
            signal("rum-view-snapshot", evidenceSource="rum-mapper",
                   semanticContext=dict(context, screen=screen),
                   rumContext=dict(owner(screen, generation), viewActive=True))
            if generation:
                pair("adaptive-commit-" + str(generation), screen, generation)
            pair("adaptive-materialized-" + str(generation), screen, generation)
            last_generation = generation
        geometry = signal("scene-geometry", semanticContext=dict(context, screen=screen),
                          navigationPath=[] if screen == "split-empty" else [screen],
                          activationState="foreground-active", horizontalSizeClass=size_class,
                          geometry=dict(width=dimensions[0], height=dimensions[1], x=0, y=0))
        if mode == "resize" and ordinal >= 3:
            signal("assertion", name="adaptive-resize-guard-" + str(ordinal - 2),
                   acknowledgedSignalSequence=geometry["sequence"], result="PASS",
                   geometry=copy.deepcopy(geometry["geometry"]), activationState="foreground-active",
                   horizontalSizeClass=size_class, navigationPath=["detail-1"],
                   semanticContext=dict(context, screen=screen))
        pair(contract.marker_name(mode, ordinal), screen, generation)
        phases.append(dict(name=name, request_sequence=request,
                           geometry_sequence=geometry["sequence"], end_sequence=len(signals)))
    records += [dict(type="signal", signal=s) for s in signals]
    return records, phases, run


def named(records, name, kind="rum-action"):
    return next(r["signal"] for r in records if r.get("signal", {}).get("name") == name
                and r["signal"]["kind"] == kind)


def backend(native):
    rows = [dict(type="view", view=dict(id=identifier), session_id=native["session_id"],
                 run_id=native["run_id"]) for identifier in native["native_view_ids"]]
    for work in native["work"]:
        row = dict(type=work["type"], view=dict(id=work["view_id"]),
                   session_id=native["session_id"], run_id=native["run_id"],
                   context={"probe.phase": work["phase"]})
        row[work["type"]] = dict(id=work["event_id"])
        rows.append(row)
    return rows


class AdaptiveSplitContractTests(unittest.TestCase):
    def test_complete_native_and_backend_sequence(self):
        records, phases, run = fixture()
        result = contract.validate_native(records, phases, run)
        self.assertEqual((result["phases"], len(result["owners"]), len(result["work"])), (14, 6, 50))
        self.assertEqual(contract.validate_backend(result, backend(result))["work_count"], 50)

    def test_finite_pose_and_resize_variants(self):
        for mode, counts in [("pose", (10, 6, 42)), ("resize", (5, 2, 16))]:
            records, phases, run = fixture(mode)
            native = contract.validate_native(records, phases, run, mode)
            self.assertEqual((native["phases"], len(native["owners"]), len(native["work"])), counts)
            self.assertEqual(contract.validate_backend(native, backend(native))["work_count"], counts[2])

    def test_resize_guard_must_precede_work_and_match_live_geometry(self):
        for change in ("late", "receipt", "geometry", "background", "churn"):
            records, phases, run = fixture("resize")
            guard = named(records, "adaptive-resize-guard-1", "assertion")
            if change == "late":
                action = named(records, "adaptive-resize-1")
                guard["sequence"], action["sequence"] = action["sequence"], guard["sequence"]
                records[1:] = sorted(records[1:], key=lambda r: r["signal"]["sequence"])
            elif change == "receipt":
                guard["acknowledgedSignalSequence"] = 1
            elif change == "geometry":
                guard["geometry"]["width"] = 400
            elif change == "background":
                guard["activationState"] = "background"
            else:
                named(records, "adaptive-resize-1")["rumContext"]["viewID"] = "new-owner"
            with self.subTest(change=change), self.assertRaises(ValueError):
                contract.validate_native(records, phases, run, "resize")

    def test_automatic_tap_with_merged_marker_attributes_is_not_custom_work(self):
        records, phases, run = fixture()
        tap = copy.deepcopy(named(records, "adaptive-marker-2"))
        tap["action"]["type"] = "tap"
        tap["eventID"] = "automatic-tap"
        tap["sequence"] = len(records)
        records.append(dict(type="signal", signal=tap))
        result = contract.validate_native(records, phases, run)
        self.assertEqual(len(result["work"]), 50)
        tap["action"]["type"] = "custom"
        with self.assertRaises(ValueError):
            contract.validate_native(records, phases, run)

    def test_stale_run_schema_and_changed_manifest(self):
        for change in ("run", "schema", "steps"):
            records, phases, run = fixture()
            if change == "run":
                records[0]["manifest"]["runID"] = "restored"
            elif change == "schema":
                records[-1]["signal"]["schemaVersion"] = 4
            else:
                records[0]["manifest"]["scenario"]["steps"].append(
                    dict(kind="wait-for-scene-ready", scene="scene-A"))
            with self.subTest(change=change), self.assertRaises(ValueError):
                contract.validate_native(records, phases, run)

    def test_structural_swapped_and_churning_owners(self):
        for change in ("structural", "swapped", "churn", "reuse", "wrong-view-context"):
            records, phases, run = fixture()
            event = named(records, "adaptive-marker-6")
            if change == "structural":
                event["rumContext"]["viewName"] = "NavigationStackHostingController<AnyView>"
            elif change == "swapped":
                event["rumContext"]["viewID"] = "owner-2"
            elif change == "churn":
                event["rumContext"]["viewID"] = "resize-owner"
            elif change == "reuse":
                for record in records:
                    if record.get("signal", {}).get("rumContext", {}).get("viewID") == "owner-4":
                        record["signal"]["rumContext"]["viewID"] = "owner-1"
            else:
                view = next(r["signal"] for r in records if
                            r.get("signal", {}).get("kind") == "rum-view-snapshot" and
                            r["signal"]["rumContext"]["viewID"] == "owner-1")
                view["semanticContext"]["screen"] = "detail-2"
            with self.subTest(change=change), self.assertRaises(ValueError):
                contract.validate_native(records, phases, run)

    def test_late_or_stale_geometry_and_route(self):
        for change in ("late-geometry", "stale-geometry", "late-route"):
            records, phases, run = fixture()
            if change == "late-geometry":
                geometry = records[phases[1]["geometry_sequence"]]["signal"]
                action = named(records, "adaptive-marker-2")
                geometry["sequence"], action["sequence"] = action["sequence"], geometry["sequence"]
                records[1:] = sorted(records[1:], key=lambda r: r["signal"]["sequence"])
                phases[1]["geometry_sequence"] = geometry["sequence"]
            elif change == "stale-geometry":
                phases[1]["request_sequence"] = phases[1]["geometry_sequence"]
            else:
                mutation = next(r["signal"] for r in records if r.get("signal", {}).get("mutation") == 1)
                action = named(records, "adaptive-commit-1")
                mutation["sequence"], action["sequence"] = action["sequence"], mutation["sequence"]
                records[1:] = sorted(records[1:], key=lambda r: r["signal"]["sequence"])
            with self.subTest(change=change), self.assertRaises(ValueError):
                contract.validate_native(records, phases, run)

    def test_unexpected_background_and_missing_or_duplicate_work(self):
        for change in ("background", "missing", "duplicate", "native", "route"):
            records, phases, run = fixture()
            if change == "background":
                records[phases[5]["geometry_sequence"]]["signal"]["activationState"] = "background"
            elif change == "missing":
                named(records, "adaptive-marker-6", "rum-resource")["name"] = "unrelated"
            elif change == "duplicate":
                named(records, "adaptive-marker-6")["name"] = "adaptive-marker-5"
            elif change == "native":
                named(records, "adaptive-marker-6")["sourceContext"]["nativeSceneID"] = "other"
            else:
                records[phases[5]["geometry_sequence"]]["signal"]["navigationPath"] = []
            with self.subTest(change=change), self.assertRaises(ValueError):
                contract.validate_native(records, phases, run)

    def test_backend_missing_duplicate_stale_swapped_or_error(self):
        records, phases, run = fixture()
        native = contract.validate_native(records, phases, run)
        for change in ("missing", "duplicate", "stale", "swapped", "error"):
            rows = backend(native)
            if change == "missing":
                rows.pop()
            elif change == "duplicate":
                rows[-1] = copy.deepcopy(rows[-2])
            elif change == "stale":
                rows[-1]["run_id"] = "restored"
            elif change == "swapped":
                rows[-1]["view"]["id"] = "owner-1"
            else:
                rows.append(dict(type="error", session_id=native["session_id"], run_id=run))
            with self.subTest(change=change), self.assertRaises(ValueError):
                contract.validate_backend(native, rows)


if __name__ == "__main__":
    unittest.main()
