import copy
import json
from pathlib import Path
import unittest
from acceptance_common import Rejected
import replay_contract as r
from acceptance import validate_reusable_native_sources

RUN = "exp194-unit"
IDS = {n: f"00000000-0000-0000-0000-{i:012d}" for i, n in enumerate(
    ["session", "launch", "scene-A:home", "scene-B:home", "scene-B:detail-1", "scene-A:detail-1", "scene-A:home-returned"], 1)}


def fixture(physical=False):
    scenario = json.loads(Path(__file__).with_name(r.CONTRACT).read_text())
    records = [dict(type="manifest", manifest=dict(runID=RUN, runMode="clean", validationErrors=[], scenario=scenario))]
    signals, counts, connected, current = [], {}, {}, {}

    def signal(kind, **kw):
        s = dict(kind=kind, schemaVersion=5, runID=RUN, scenarioID=r.SCENARIO, evidenceSource="probe",
                 sequence=len(signals)+1, timestampMilliseconds=1000+(len(signals)+1)*10)
        s.update(kw)
        signals.append(s)
        return s

    def context(scene, screen):
        return dict(logicalSceneID=scene, nativeSceneID="native-"+scene, screen=screen, occurrence=1)

    def view(scene, screen, returned=False):
        owner = dict(sessionID=IDS["session"], viewID=IDS[scene+":"+screen+("-returned" if returned else "")], viewName=r.NAMES[screen],
                     viewActive=True, sessionHasReplay=True)
        current[scene] = (screen, owner)
        return signal("rum-view-snapshot", evidenceSource="rum-mapper",
                      semanticContext=context(scene, screen), rumContext=owner)

    signal("rum-view-snapshot", evidenceSource="rum-mapper",
           rumContext=dict(sessionID=IDS["session"], viewID=IDS["launch"], viewName="ApplicationLaunch"))
    for i, step in enumerate(scenario["steps"]):
        kind, scene = step["kind"], step["scene"]
        signal("step-started", stepKind=kind, stepIndex=i, name=step.get("value", step.get("signal")))
        if kind == "wait-for-scene-ready":
            connected[scene] = True
            evidence = signal("scene-ready", semanticContext=context(scene, "home"))
        elif kind == "wait-for-signal":
            screen = "detail-1" if "detail-1" in step["signal"] else "home"
            evidence = view(scene, screen)
        elif kind == "open-window":
            old = copy.deepcopy(current["scene-A"][1])
            old["viewActive"] = False
            signal("rum-view-snapshot", evidenceSource="rum-mapper",
                   semanticContext=context("scene-A", "home"), rumContext=old)
            signal("scene-lifecycle", semanticContext=context("scene-A", "home"), activationState="background")
            connected["scene-B"] = True
            evidence = signal("scene-ready", semanticContext=context("scene-B", "home"))
        elif kind == "set-swiftui-path":
            evidence = signal("navigation-path-mutation", semanticContext=context(scene, step["value"]),
                              navigationPath=[step["value"]])
        elif kind == "close-window":
            if physical:
                view("scene-A", "home", returned=True)
                signal("scene-lifecycle", semanticContext=context("scene-A", "home"),
                       activationState="foreground-active")
            connected.pop(scene)
            evidence = signal("scene-lifecycle", semanticContext=context(scene, "detail-1"), scenePhase="disconnected")
        elif kind == "activate-window":
            if not physical:
                view("scene-A", "home", returned=True)
            evidence = signal("scene-lifecycle", semanticContext=context(scene, "home"), activationState="foreground-active")
        elif kind == "capture-replay-records":
            screen, owner = current[scene]
            topology = [dict(logicalSceneID=s, nativeSceneID="native-"+s,
                            activationState="foreground-active" if s == scene else "background",
                            geometry=dict(x=0, y=0, width=1000, height=700)) for s in sorted(connected)]
            def observation(name):
                return signal("assertion", evidenceSource="internal-hook", name=name, result="PASS",
                              semanticContext=context(scene, screen), rumContext=copy.deepcopy(owner),
                              replay=dict(hasReplay=True, recordsByViewID=copy.deepcopy(counts), scenes=copy.deepcopy(topology)))
            observation("baseline-"+step["value"])
            counts[owner["viewID"]] = counts.get(owner["viewID"], 0)+3
            evidence = observation(step["value"])
        signal("step-acknowledged", stepKind=kind, stepIndex=i, acknowledgedSignalSequence=evidence["sequence"])
    records.extend(dict(type="signal", signal=s) for s in signals)
    records.append(dict(type="semantic-result", runID=RUN,
                        result=dict(scenarioID=r.SCENARIO, state="PASS", matchedExpectationCount=8, issues=[])))
    return records


class ReplayContractTests(unittest.TestCase):
    def test_physical_close_return_and_simulator_timing_remain_distinct(self):
        actual = r.validate_physical_local(fixture(physical=True), RUN)
        self.assertEqual(actual["return_contract"], "physical-close-return")
        self.assertEqual(len(actual["views"]), 6)
        self.assertEqual(len(actual["recording_checkpoints"]), 4)
        with self.assertRaises(Rejected):
            r.validate_local(fixture(physical=True), RUN)
        with self.assertRaises(Rejected):
            r.validate_physical_local(fixture(), RUN)

    def test_physical_return_rejects_missing_or_stale_os_evidence(self):
        cases = ["no-background", "old-home-live", "reused-home", "wrong-native",
                 "no-foreground", "fake-foreground", "before-close", "after-close",
                 "stopped-return", "background-again", "missing-disconnect", "stale-run"]
        for case in cases:
            with self.subTest(case=case):
                records = fixture(physical=True)
                signals = [x["signal"] for x in records if x["type"] == "signal"]
                home = next(s for s in signals if s.get("rumContext", {}).get("viewID") == IDS["scene-A:home-returned"])
                active = next(s for s in signals if s["kind"] == "scene-lifecycle" and s.get("activationState") == "foreground-active")
                old_stop = next(s for s in signals if s.get("rumContext", {}).get("viewActive") is False)
                if case == "no-background":
                    next(s for s in signals if s.get("activationState") == "background")["activationState"] = "foreground-inactive"
                elif case == "old-home-live": old_stop["rumContext"]["viewActive"] = True
                elif case == "reused-home": home["rumContext"]["viewID"] = IDS["scene-A:home"]
                elif case == "wrong-native": active["semanticContext"]["nativeSceneID"] = "native-scene-B"
                elif case == "no-foreground": active["activationState"] = "foreground-inactive"
                elif case == "fake-foreground": active["kind"] = "assertion"
                elif case in ["before-close", "after-close"]:
                    boundary = next(s for s in signals if s["kind"] == ("step-started" if case == "before-close" else "step-acknowledged") and s.get("stepIndex") == 9)
                    # Preserve contiguous signal/ack identities while moving the actual observations.
                    moved = [home, active]
                    signals = [s for s in signals if s not in moved]
                    at = signals.index(boundary) + (case == "after-close")
                    signals[at:at] = moved
                    remap = {s["sequence"]: i+1 for i, s in enumerate(signals)}
                    for s in signals:
                        s["sequence"] = remap[s["sequence"]]
                        if "acknowledgedSignalSequence" in s:
                            s["acknowledgedSignalSequence"] = remap[s["acknowledgedSignalSequence"]]
                    records = [records[0]] + [dict(type="signal", signal=s) for s in signals] + [records[-1]]
                elif case in ["stopped-return", "background-again"]:
                    late = next(s for s in signals if s["kind"] == "scene-lifecycle" and s.get("activationState") == "foreground-active" and s is not active)
                    if case == "stopped-return":
                        late.update(kind="rum-view-snapshot", evidenceSource="rum-mapper", rumContext=copy.deepcopy(home["rumContext"]))
                        late["rumContext"]["viewActive"] = False
                    else: late["activationState"] = "background"
                elif case == "missing-disconnect": next(s for s in signals if s.get("scenePhase") == "disconnected")["scenePhase"] = "ready"
                elif case == "stale-run": home["runID"] = "exp196-old"
                with self.assertRaises(Rejected):
                    r.validate_physical_local(records, RUN)

    def test_reuse_rejects_changed_added_or_removed_native_input(self):
        before = {"files": {"DatadogRUM/Sources/A.swift": "one", "Package.swift": "two",
                            "tools/multi-scene/acceptance/replay_contract.py": "old"}}
        after = copy.deepcopy(before)
        after["files"]["tools/multi-scene/acceptance/replay_contract.py"] = "new"
        validate_reusable_native_sources(before, after)
        for kind in ["changed", "added", "removed"]:
            candidate = copy.deepcopy(after)
            if kind == "changed": candidate["files"]["Package.swift"] = "different"
            if kind == "added": candidate["files"]["DatadogRUM/Sources/B.swift"] = "new"
            if kind == "removed": candidate["files"].pop("DatadogRUM/Sources/A.swift")
            with self.subTest(kind=kind), self.assertRaises(Rejected):
                validate_reusable_native_sources(before, candidate)

    def test_complete_native_recording_contract(self):
        actual = r.validate_local(fixture(), RUN)
        self.assertEqual(len(actual["recording_checkpoints"]), 4)
        self.assertEqual(len(actual["views"]), 6)

    def test_rejects_false_recording_and_topology_evidence(self):
        for name in ["disabled", "stagnant", "foreign-record", "foreign-session", "wrong-owner",
                     "aliased-scene", "inactive-source", "empty-geometry", "late-baseline",
                     "missing-disconnect", "fake-disconnect", "missing-ack", "stale-manifest",
                     "restored-run", "stale-signal", "changed-scenario", "unexpected-browser",
                     "wrong-mapper-origin", "extra-view", "late-ack", "no-background", "no-reactivation", "old-home-live", "reused-home"]:
            with self.subTest(name=name):
                records = fixture()
                signals = [s["signal"] for s in records if s["type"] == "signal"]
                after = next(s for s in signals if s.get("name") == r.PHASES[0] and "replay" in s)
                before = next(s for s in signals if s.get("name") == "baseline-"+r.PHASES[0])
                disconnect = next(s for s in signals if s.get("scenePhase") == "disconnected")
                if name == "no-background":
                    next(s for s in signals if s.get("activationState")=="background")["activationState"]="foreground-inactive"
                elif name == "no-reactivation":
                    next(s for s in signals if s["kind"]=="scene-lifecycle" and s.get("activationState")=="foreground-active")["activationState"]="foreground-inactive"
                elif name == "old-home-live":
                    next(s for s in signals if s.get("rumContext",{}).get("viewActive") is False)["rumContext"]["viewActive"]=True
                elif name == "reused-home":
                    next(s for s in signals if s.get("rumContext",{}).get("viewID")==IDS["scene-A:home-returned"])["rumContext"]["viewID"]=IDS["scene-A:home"]
                elif name == "disabled": after["replay"]["hasReplay"] = False
                elif name == "stagnant": after["replay"]["recordsByViewID"] = {}
                elif name == "foreign-record": after["replay"]["recordsByViewID"]["foreign"] = 1
                elif name == "foreign-session": after["rumContext"]["sessionID"] = IDS["launch"]
                elif name == "wrong-owner": after["rumContext"]["viewID"] = IDS["scene-B:home"]
                elif name == "aliased-scene": after["replay"]["scenes"][0]["nativeSceneID"] = "native-scene-B"
                elif name == "inactive-source": after["replay"]["scenes"][0]["activationState"] = "background"
                elif name == "empty-geometry": after["replay"]["scenes"][0]["geometry"]["width"] = 0
                elif name == "late-baseline": before["name"], after["name"] = after["name"], before["name"]
                elif name == "missing-disconnect": disconnect.pop("scenePhase")
                elif name == "fake-disconnect": disconnect["kind"] = "assertion"
                elif name == "missing-ack": next(s for s in signals if s["kind"] == "step-acknowledged")["kind"] = "assertion"
                elif name == "stale-manifest": records[0]["manifest"]["runID"] = "old"
                elif name == "restored-run": records[0]["manifest"]["runMode"] = "restoration"
                elif name == "stale-signal": after["runID"] = "old"
                elif name == "changed-scenario": records[0]["manifest"]["scenario"]["steps"].append({"kind":"wait-for-scene-ready","scene":"scene-B"})
                elif name == "unexpected-browser": before["kind"] = "web-bridge-message"
                elif name == "wrong-mapper-origin": next(s for s in signals if s["kind"]=="rum-view-snapshot")["evidenceSource"] = "probe"
                elif name == "extra-view":
                    before.update(kind="rum-view-snapshot", evidenceSource="rum-mapper",
                                  rumContext=dict(viewID="00000000-0000-0000-0000-000000000099",sessionID=IDS["session"],viewName="Extra"))
                elif name == "late-ack": next(s for s in signals if s["kind"]=="step-acknowledged")["acknowledgedSignalSequence"] = signals[-1]["sequence"]
                with self.assertRaises(Rejected):
                    r.validate_local(records, RUN)

    def test_backend_exact_inventory_and_failure_controls(self):
        local = r.validate_local(fixture(), RUN)
        valid = {"count":6, "rows":[dict(v, run_id=RUN, has_replay=True) for v in local["views"]]}
        zero = {"count":0,"rows":[]}
        self.assertEqual(r.validate_backend(local, RUN, valid, zero, zero, 0, 0)["state"], "PASS")
        for key in ["run_id", "session_id", "name", "view_id", "has_replay", "missing", "error", "crash", "resource"]:
            with self.subTest(key=key):
                rows = copy.deepcopy(valid)
                args = [local, RUN, rows, zero, zero, 0, 0]
                if key == "missing": rows["rows"].pop()
                elif key == "error": args[5]=1
                elif key == "crash": args[6]=1
                elif key == "resource": args[4]={"count":1}
                else: rows["rows"][1][key]=False if key=="has_replay" else "wrong"
                with self.assertRaises(Rejected):
                    r.validate_backend(*args)


if __name__ == "__main__":
    unittest.main()
