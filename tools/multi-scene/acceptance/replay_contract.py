"""F05 simulator slice: real native Replay record production across actual scene lifecycle."""
import json
import uuid
from pathlib import Path
from acceptance_common import require, require_identity, require_before, unique

SCENARIO = "replay.native-recording.navigation-teardown-serial"
CONTRACT = "replay-scenario-contract.json"
PHASES = ["replay-a-before-peer", "replay-b-after-open",
          "replay-b-after-navigation", "replay-a-after-teardown"]
SCENES = ["scene-A", "scene-B", "scene-B", "scene-A"]
SCREENS = ["home", "home", "detail-1", "detail-1"]
NAMES = {"home": "ProbeHomeView", "detail-1": "ProbeDetailView"}
MINIMUM_TESTS = 205


def valid_uuid(value):
    try:
        return isinstance(value, str) and str(uuid.UUID(value)) == value.lower()
    except (ValueError, AttributeError):
        return False


def validate_local(records, run_id):
    manifest = unique([r["manifest"] for r in records if r["type"] == "manifest"], "manifest")
    require(manifest.get("runID") == run_id and manifest.get("runMode") == "clean"
            and not manifest.get("validationErrors"), "stale/invalid Replay manifest")
    scenario = json.loads(Path(__file__).with_name(CONTRACT).read_text())
    require_identity(manifest.get("scenario"), scenario, "Replay scenario")
    signals = [r["signal"] for r in records if r["type"] == "signal"]
    require(signals and all(s.get("runID") == run_id and s.get("scenarioID") == SCENARIO
                           and s.get("schemaVersion") == 5 for s in signals), "stale Replay signals")
    require([s["sequence"] for s in signals] == list(range(1, len(signals) + 1)), "signal sequence")
    require(all(type(s.get("timestampMilliseconds")) is int and s["timestampMilliseconds"] > 0
                for s in signals), "native timestamp")
    terminal = unique([r for r in records if r["type"] == "semantic-result"], "terminal")
    result = terminal.get("result", {})
    require(terminal.get("runID") == run_id and result.get("scenarioID") == SCENARIO,
            "stale terminal")
    require(result.get("state") == "PASS" and result.get("matchedExpectationCount") == 8
            and result.get("issues") == [], "native scenario did not pass", "FAIL")
    require(not any(s.get("result") == "FAIL" for s in signals), "native assertion failed", "FAIL")
    require(not any(s.get("kind") in ["web-bridge-message", "rum-action", "rum-resource", "rum-error"]
                    for s in signals), "unexpected browser/work/error evidence", "FAIL")
    starts = [s for s in signals if s.get("kind") == "step-started"]
    acks = [s for s in signals if s.get("kind") == "step-acknowledged"]
    require(len(starts) == len(acks) == len(scenario["steps"]), "incomplete native steps")
    for index, (step, start, ack) in enumerate(zip(scenario["steps"], starts, acks)):
        require(start.get("stepIndex") == ack.get("stepIndex") == index
                and start.get("stepKind") == ack.get("stepKind") == step["kind"], "step identity")
        require_before(start, ack, "step acknowledgement")
        evidence = next((s for s in signals if s["sequence"] == ack.get("acknowledgedSignalSequence")), None)
        require(evidence is not None and evidence["sequence"] < ack["sequence"], "missing/late acknowledgement")
        if index + 1 < len(starts):
            require_before(ack, starts[index + 1], "next command before prior boundary")
        if step["kind"] not in ["wait-for-scene-ready", "wait-for-signal"]:
            require_before(start, evidence, "stale evidence reused for command")

    views = [s for s in signals if s.get("kind") == "rum-view-snapshot"]
    inventory = {}
    for s in views:
        c = s.get("rumContext", {})
        require(s.get("evidenceSource") == "rum-mapper" and valid_uuid(c.get("viewID"))
                and valid_uuid(c.get("sessionID")), "independent mapper identity", "FAIL")
        item = {"view_id": c["viewID"], "session_id": c["sessionID"], "name": c.get("viewName")}
        require(c["viewID"] not in inventory or inventory[c["viewID"]] == item, "mutated view identity", "FAIL")
        inventory[c["viewID"]] = item
    require(sorted(v["name"] for v in inventory.values()) ==
            ["ApplicationLaunch", "ProbeDetailView", "ProbeDetailView", "ProbeHomeView", "ProbeHomeView", "ProbeHomeView"],
            "complete native owner inventory", "FAIL")
    sessions = {v["session_id"] for v in inventory.values()}
    require(len(sessions) == 1, "foreign native session", "FAIL")
    session = sessions.pop()

    native = {}
    for scene in ["scene-A", "scene-B"]:
        ready = [s for s in signals if s.get("kind") == "scene-ready"
                 and s.get("semanticContext", {}).get("logicalSceneID") == scene]
        require(ready and len({s.get("semanticContext", {}).get("nativeSceneID") for s in ready}) == 1,
                "missing or replaced native scene", "FAIL")
        native[scene] = ready[0]["semanticContext"]["nativeSceneID"]
        require(native[scene], "empty scene identity")
    require(len(set(native.values())) == 2, "native scene alias", "FAIL")
    disconnect = unique([s for s in signals if s.get("kind") == "scene-lifecycle"
                         and s.get("semanticContext", {}).get("logicalSceneID") == "scene-B"
                         and s.get("scenePhase") == "disconnected"], "actual peer disconnect")
    require(disconnect.get("semanticContext", {}).get("nativeSceneID") == native["scene-B"],
            "disconnect wrong scene", "FAIL")
    require_before(starts[9], disconnect, "disconnect precedes request")
    require_before(disconnect, starts[11], "navigation before OS disconnect")
    # The serial platform transition backgrounds A, then reveals a fresh Home
    # before the explicit Detail navigation. Admit only that bounded occurrence.
    backgrounds = [s for s in signals if s.get("kind") == "scene-lifecycle"
                   and s.get("semanticContext", {}).get("logicalSceneID") == "scene-A"
                   and s.get("semanticContext", {}).get("nativeSceneID") == native["scene-A"]
                   and s.get("activationState") == "background"
                   and starts[3]["sequence"] < s["sequence"] < starts[10]["sequence"]]
    require(backgrounds, "returned Home without actual A background", "FAIL")
    homes = [s for s in views if s.get("semanticContext", {}).get("logicalSceneID") == "scene-A"
             and s.get("semanticContext", {}).get("screen") == "home"]
    original = [s for s in homes if s["sequence"] < starts[3]["sequence"]]
    returned = [s for s in homes if starts[10]["sequence"] < s["sequence"] < starts[11]["sequence"]
                and s.get("rumContext", {}).get("viewActive") is True]
    require(original and returned, "missing original/foreground Home", "FAIL")
    old_id, new_id = original[-1]["rumContext"]["viewID"], returned[0]["rumContext"]["viewID"]
    require(old_id != new_id and {s["rumContext"]["viewID"] for s in homes} == {old_id, new_id},
            "returned Home is reused or unexplained", "FAIL")
    require(any(s["rumContext"]["viewID"] == old_id and s["rumContext"].get("viewActive") is False
                and starts[3]["sequence"] < s["sequence"] < starts[10]["sequence"] for s in homes),
            "old Home never stopped before foreground return", "FAIL")
    active = [s for s in signals if s.get("kind") == "scene-lifecycle"
              and s.get("semanticContext", {}).get("logicalSceneID") == "scene-A"
              and s.get("activationState") == "foreground-active"
              and starts[10]["sequence"] < s["sequence"] < starts[11]["sequence"]]
    require(active, "missing actual A reactivation before Detail", "FAIL")
    observations, previous = [], {}
    for i, phase in enumerate(PHASES):
        baseline = unique([s for s in signals if s.get("name") == "baseline-" + phase], "baseline " + phase)
        after = unique([s for s in signals if s.get("name") == phase and s.get("replay") is not None],
                       "recording " + phase)
        step_index = [2, 5, 8, 13][i]
        require_before(starts[step_index], baseline, "baseline before command")
        require_before(baseline, after, "growth before baseline")
        require(acks[step_index].get("acknowledgedSignalSequence") == after["sequence"],
                "Replay completion not acknowledged")
        known = [s for s in views if s["sequence"] < baseline["sequence"]
                 and s.get("semanticContext", {}).get("logicalSceneID") == SCENES[i]
                 and s.get("semanticContext", {}).get("screen") == SCREENS[i]
                 and s.get("rumContext", {}).get("viewActive") is True]
        require(known, "owner guard has no preceding mapper", "FAIL")
        owner = known[-1]["rumContext"]
        require(owner.get("sessionHasReplay") is True and owner.get("viewName") == NAMES[SCREENS[i]],
                "wrong/Replay-disabled owner", "FAIL")
        expected_labels = ["scene-A"] if i in [0, 3] else ["scene-A", "scene-B"]
        for event in [baseline, after]:
            require(event.get("kind") == "assertion" and event.get("evidenceSource") == "internal-hook"
                    and event.get("result") == "PASS", "invalid observation source", "FAIL")
            c = event.get("rumContext", {})
            require(all(c.get(k) == owner.get(k) for k in ["viewID", "sessionID", "viewName"])
                    and c.get("sessionHasReplay") is True, "observation owner differs", "FAIL")
            require(event.get("semanticContext", {}).get("nativeSceneID") == native[SCENES[i]],
                    "observation native source differs", "FAIL")
            replay = event["replay"]
            require(replay.get("hasReplay") is True, "Replay disabled", "FAIL")
            counters = replay.get("recordsByViewID")
            require(isinstance(counters, dict) and set(counters) <= set(inventory)
                    and all(type(v) is int and v >= 0 for v in counters.values()),
                    "foreign or malformed native record counters", "FAIL")
            require(all(counters.get(k, 0) >= v for k, v in previous.items()), "native counters regressed", "FAIL")
            previous = counters
            topology = replay.get("scenes", [])
            require([s.get("logicalSceneID") for s in topology] == expected_labels, "wrong live topology", "FAIL")
            for item in topology:
                require(item.get("nativeSceneID") == native[item["logicalSceneID"]], "aliased topology", "FAIL")
                require(item.get("activationState") in ["foreground-active", "foreground-inactive", "background"],
                        "unattached native scene", "FAIL")
                if item["logicalSceneID"] == SCENES[i]:
                    require(item["activationState"] == "foreground-active", "recording scene not active", "FAIL")
                geometry = item.get("geometry", {})
                require(geometry.get("width", 0) > 0 and geometry.get("height", 0) > 0,
                        "missing live geometry", "FAIL")
        count_before = baseline["replay"]["recordsByViewID"].get(owner["viewID"], 0)
        count_after = after["replay"]["recordsByViewID"].get(owner["viewID"], 0)
        require(count_after > count_before, "hasReplay without new native recording", "FAIL")
        if i == 0:
            require_before(after, starts[3], "recording after expansion")
        if i == 2:
            require_before(after, starts[9], "recording after teardown request")
        if i == 3:
            require_before(disconnect, baseline, "post-teardown observation is early")
        observations.append({"phase": phase, "view_id": owner["viewID"], "before": count_before,
                             "after": count_after, "topology": after["replay"]["scenes"]})
    require(len({o["view_id"] for o in observations}) == 4, "destination occurrence reused", "FAIL")
    return {"state": "PASS", "session_id": session, "view_ids": sorted(inventory),
            "views": list(inventory.values()), "recording_checkpoints": observations,
            "scope": "Native recorder coexistence; no scene-correct Replay or physical acceptance"}


def validate_backend(local, run_id, views, actions, resources, errors, crashes):
    require(errors == crashes == 0 and actions.get("count") == resources.get("count") == 0,
            "unexpected backend work/error/crash", "FAIL")
    rows = views.get("rows", [])
    require(views.get("count") == len(rows) == len(local["views"]), "complete backend inventory", "FAIL")
    for expected in local["views"]:
        row = unique([v for v in rows if v.get("view_id") == expected["view_id"]], "backend view")
        require(all(row.get(k) == v for k, v in expected.items())
                and row.get("run_id") == run_id, "backend owner/run mismatch", "FAIL")
        if expected["name"] != "ApplicationLaunch":
            require(row.get("has_replay") is True, "backend view lacks Replay", "FAIL")
    return {"state": "PASS", "view_count": len(rows), "native_recording_checkpoints": 4,
            "error_crash_count": 0, "physical_gate_closed": False}
