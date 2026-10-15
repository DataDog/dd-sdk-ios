import copy
import json
from pathlib import Path
import unittest
from acceptance_common import Rejected
import webview_contract as w

IDS = {name: f"00000000-0000-0000-0000-{i:012d}" for i, name in enumerate(
    ["application", "session", "launch", "scene-A", "scene-B", "WebNativeA1", "WebNativeB1", "WebNativeA2"], 1)}


def fixture():
    run = "exp183-unit"
    records = [dict(type="manifest", manifest=dict(runID=run, runMode="clean", validationErrors=[],
               scenario=json.loads(Path(__file__).with_name(w.CONTRACT).read_text())))]
    signals = []

    def signal(kind, **kw):
        value = dict(kind=kind, sequence=len(signals) + 1, runID=run, scenarioID=w.SCENARIO,
                     schemaVersion=5, evidenceSource="probe", timestampMilliseconds=1000 + 10 * (len(signals) + 1))
        value.update(kw)
        signals.append(value)
        return value

    def context(owner):
        return dict(viewID=IDS[owner], sessionID=IDS["session"], viewName=owner)

    def assertion(name, owner=None, **kw):
        if owner:
            kw.update(evidenceSource="internal-hook", rumContext=context(owner))
        return signal("assertion", name=name, result="PASS", **kw)

    def view(identifier, name, scene=None):
        return signal("rum-view-snapshot", name="mapper-" + identifier, evidenceSource="rum-mapper",
                      semanticContext=dict(logicalSceneID=scene, nativeSceneID="native-" + str(scene),
                                           screen="home" if name == "ProbeHomeView" else name),
                      rumContext=dict(viewID=IDS[identifier], sessionID=IDS["session"], viewName=name,
                                      viewActive=True, sessionHasReplay=True))

    def owner(name, scene):
        assertion("web-native-start-" + name)
        view(name, name, scene)
        assertion("web-owner-" + name, name)

    view("launch", "ApplicationLaunch")
    for scene in ["scene-A", "scene-B"]:
        signal("scene-ready", semanticContext=dict(logicalSceneID=scene, nativeSceneID="native-" + scene))
        view(scene, "ProbeHomeView", scene)
    signal("step-started", stepKind="run-webview-ownership-batch")
    assertion("web-replay-ready")
    assertion("web-two-mounted-containers")
    assertion("web-document-ready-" + run + "/A/initial")
    assertion("web-document-ready-" + run + "/B/initial")
    owner("WebNativeA1", "scene-A")
    owner("WebNativeB1", "scene-B")
    assertion("web-representative-before-a", "WebNativeB1")
    for i, phase in enumerate(w.PHASES):
        if i == 2:
            assertion("web-navigation-boundary")
            owner("WebNativeA2", "scene-A")
            assertion("web-document-ready-" + run + "/A/navigation")
        if i in [3, 4, 5]:
            names = {3: ("web-detach-boundary", "web-detached"), 4: ("web-rebind-boundary", "web-rebound"),
                     5: ("web-teardown-boundary", "web-a-torn-down")}[i]
            for name in names:
                assertion(name)
        scene = w.SOURCES[i]
        native = None if scene == "detached" else "native-" + scene
        source = dict(logicalSceneID=scene, nativeSceneID=native, screen="web", phase=phase)
        boundary = assertion("web-dispatch-boundary-" + phase, w.OWNERS[i], sourceContext=source)
        browser = f"00000000-0000-0000-0000-{100 + i:012d}"
        document = run + "/" + w.DOCUMENTS[i]
        message = dict(browserViewID=browser, phase=phase, runID=run, sourceScene=scene,
                       documentID=document, url="https://" + w.HOST + "/" + document,
                       dateMilliseconds=boundary["timestampMilliseconds"] + 1, nativeSceneID=native,
                       spoofedSceneID="native-scene-B" if i in [0, 2, 3] else "native-scene-A",
                       webViewIdentity="ObjectIdentifier(A)" if i in [0, 2, 3, 4] else "ObjectIdentifier(B)")
        signal("web-bridge-message", evidenceSource="webkit-callback", name=phase, eventID=browser,
               sourceContext=source, webMessage=message, result="PASS")
    assertion("web-local-inputs-verified")
    assertion("web-batch-finished")
    records += [dict(type="signal", signal=s) for s in signals]
    records.append(dict(type="semantic-result", runID=run, result=dict(
        scenarioID=w.SCENARIO, state="PASS", matchedExpectationCount=14, issues=[])))
    return records, run


def named(records, name):
    return next(r["signal"] for r in records if r.get("signal", {}).get("name") == name)


def backend(local, run):
    rows = [dict(v, run_id=run, application_id=IDS["application"], source="ios",
                 container_present=False, leaked_internal_attribute=False) for v in local["views"]]
    rows += [dict(v, run_id=run, application_id=IDS["application"], leaked_internal_attribute=False,
                  has_replay=True, is_active=False, action_count=0, resource_count=0, error_count=0,
                  time_spent=1000000, long_task_count=0, loading_type="initial_load",
                  format_version=2, document_version=1) for v in local["browser_views"]]
    return rows


def check_backend(local, run, rows):
    return w.validate_backend(local, run, rows, [], [], 0, 0)


def resequence(records):
    for i, r in enumerate(r for r in records if r["type"] == "signal"):
        r["signal"]["sequence"] = i + 1


class WebViewContractTests(unittest.TestCase):
    def test_exact_local_and_backend_contract(self):
        records, run = fixture()
        local = w.validate_local(records, run)
        self.assertEqual(local["assertions"], 14)
        self.assertEqual(local["browser_views"][3]["container_id"], None)
        self.assertEqual(check_backend(local, run, backend(local, run))["correlated_browser_view_count"], 5)

    def test_stale_fixture_and_consumed_readiness(self):
        for mode in ["readiness", "completion", "runtime"]:
            records, run = fixture()
            scenario = records[0]["manifest"]["scenario"]
            if mode == "readiness":
                scenario["steps"].append(dict(kind="wait-for-scene-ready", scene="scene-B"))
            elif mode == "completion":
                scenario["completionConditions"].pop()
            else:
                scenario["runtimeOptions"]["automaticallyNavigates"] = True
            with self.assertRaises(Rejected, msg=mode):
                w.validate_local(records, run)

    def test_stale_manifest_signal_and_terminal(self):
        for location, key, value in [("manifest", "runID", "restored"), ("manifest", "runMode", "restored"),
                                     ("signal", "runID", "old"), ("signal", "schemaVersion", 4),
                                     ("signal", "scenarioID", "old"), ("terminal", "runID", "old")]:
            records, run = fixture()
            row = records[0]["manifest"] if location == "manifest" else records[-1] if location == "terminal" else named(records, w.PHASES[0])
            row[key] = value
            with self.assertRaises(Rejected):
                w.validate_local(records, run)

    def test_weak_app_verdict_or_failed_assertion(self):
        for mode in ["state", "count", "issues", "assertion"]:
            records, run = fixture()
            if mode == "assertion":
                named(records, "web-two-mounted-containers")["result"] = "FAIL"
            else:
                key, value = {"state": ("state", "INCONCLUSIVE"), "count": ("matchedExpectationCount", 13),
                              "issues": ("issues", ["missing"])}[mode]
                records[-1]["result"][key] = value
            with self.assertRaises(Rejected):
                w.validate_local(records, run)

    def test_each_critical_guard_after_boundary(self):
        pairs = [("web-replay-ready", "web-native-start-WebNativeA1"),
                 ("web-owner-WebNativeA1", w.PHASES[0]),
                 ("web-representative-before-a", w.PHASES[0]),
                 ("web-document-ready-exp183-unit/A/navigation", w.PHASES[2]),
                 ("web-detach-boundary", w.PHASES[3]), ("web-rebind-boundary", w.PHASES[4]),
                 ("web-teardown-boundary", w.PHASES[5]), ("web-local-inputs-verified", "web-batch-finished")]
        pairs += [("web-dispatch-boundary-" + p, p) for p in w.PHASES]
        for guard, after in pairs:
            records, run = fixture()
            a = next(r for r in records if r.get("signal", {}).get("name") == guard)
            b = next(r for r in records if r.get("signal", {}).get("name") == after)
            ai, bi = records.index(a), records.index(b)
            records[ai], records[bi] = records[bi], records[ai]
            resequence(records)
            with self.assertRaises(Rejected, msg=guard):
                w.validate_local(records, run)

    def test_callback_acknowledgement_before_next_mutation(self):
        for callback, guard in [(w.PHASES[0], "web-dispatch-boundary-" + w.PHASES[1]),
                                (w.PHASES[1], "web-navigation-boundary"),
                                (w.PHASES[2], "web-detach-boundary"),
                                (w.PHASES[3], "web-rebind-boundary"),
                                (w.PHASES[4], "web-teardown-boundary")]:
            records, run = fixture()
            a = next(r for r in records if r.get("signal", {}).get("name") == callback)
            b = next(r for r in records if r.get("signal", {}).get("name") == guard)
            ai, bi = records.index(a), records.index(b)
            records[ai], records[bi] = records[bi], records[ai]
            resequence(records)
            with self.assertRaises(Rejected, msg=callback):
                w.validate_local(records, run)

    def test_replay_owner_must_be_live_and_independently_mapped(self):
        for field, value in [("sessionHasReplay", False), ("viewActive", False), ("viewID", IDS["WebNativeB1"])]:
            records, run = fixture()
            named(records, "mapper-WebNativeA1")["rumContext"][field] = value
            with self.assertRaises(Rejected):
                w.validate_local(records, run)
        records, run = fixture()
        named(records, "mapper-WebNativeA1")["evidenceSource"] = "probe"
        with self.assertRaises(Rejected):
            w.validate_local(records, run)

    def test_actual_native_scene_cannot_be_replaced_with_peer_label(self):
        for location in ["sourceContext", "webMessage"]:
            records, run = fixture()
            named(records, w.PHASES[0])[location]["nativeSceneID"] = "native-scene-B"
            with self.assertRaises(Rejected):
                w.validate_local(records, run)

    def test_callback_input_cannot_substitute_for_receiver_output(self):
        for key, value in [("evidenceSource", "rum-mapper"), ("rumContext", {"viewID": IDS["WebNativeA1"]})]:
            records, run = fixture()
            named(records, w.PHASES[0])[key] = value
            with self.assertRaises(Rejected):
                w.validate_local(records, run)

    def test_malformed_stale_and_foreign_callback_fields(self):
        cases = [("runID", "old"), ("browserViewID", "bad"), ("sourceScene", "scene-B"),
                 ("phase", w.PHASES[1]), ("documentID", "restored/A/initial"),
                 ("url", "https://wrong.invalid/"), ("spoofedSceneID", "native-scene-A"),
                 ("dateMilliseconds", True), ("dateMilliseconds", 1), ("dateMilliseconds", 999999999),
                 ("webViewIdentity", "")]
        for field, value in cases:
            records, run = fixture()
            named(records, w.PHASES[0])["webMessage"][field] = value
            with self.assertRaises(Rejected, msg=field):
                w.validate_local(records, run)

    def test_timestamp_must_follow_pre_dispatch_guard(self):
        records, run = fixture()
        named(records, w.PHASES[0])["webMessage"]["dateMilliseconds"] = named(records, "web-dispatch-boundary-" + w.PHASES[0])["timestampMilliseconds"]
        with self.assertRaises(Rejected):
            w.validate_local(records, run)

    def test_detached_callback_cannot_inherit_native_container(self):
        for mode in ["actual", "owner"]:
            records, run = fixture()
            if mode == "actual":
                named(records, w.PHASES[3])["webMessage"]["nativeSceneID"] = "native-scene-B"
            else:
                named(records, "web-dispatch-boundary-" + w.PHASES[3])["rumContext"] = {"viewID": IDS["WebNativeB1"]}
            with self.assertRaises(Rejected):
                w.validate_local(records, run)

    def test_navigation_and_rebind_keep_same_instance(self):
        for index in [2, 3, 4, 5]:
            records, run = fixture()
            named(records, w.PHASES[index])["webMessage"]["webViewIdentity"] = "ObjectIdentifier(replacement)"
            with self.assertRaises(Rejected, msg=str(index)):
                w.validate_local(records, run)

    def test_browser_ids_must_be_unique(self):
        records, run = fixture()
        first = named(records, w.PHASES[0])["eventID"]
        named(records, w.PHASES[1])["eventID"] = first
        named(records, w.PHASES[1])["webMessage"]["browserViewID"] = first
        with self.assertRaises(Rejected):
            w.validate_local(records, run)

    def test_missing_extra_or_reordered_callback(self):
        for mode in ["missing", "extra", "reorder"]:
            records, run = fixture()
            rows = [r for r in records if r.get("signal", {}).get("kind") == "web-bridge-message"]
            if mode == "missing":
                records.remove(rows[3])
            elif mode == "extra":
                records.insert(-1, copy.deepcopy(rows[0]))
            else:
                a, b = records.index(rows[0]), records.index(rows[1])
                records[a], records[b] = records[b], records[a]
            resequence(records)
            with self.assertRaises(Rejected):
                w.validate_local(records, run)

    def test_foreign_peer_container_and_detached_null_object(self):
        records, run = fixture()
        local = w.validate_local(records, run)
        for index, field, value in [(6, "container_id", IDS["WebNativeB1"]),
                                    (8, "container_id", IDS["WebNativeA1"]),
                                    (9, "container_id", IDS["WebNativeB1"]),
                                    (9, "container_present", True),
                                    (10, "container_id", IDS["WebNativeA2"]),
                                    (11, "container_source", "android")]:
            rows = backend(local, run)
            rows[index][field] = value
            with self.assertRaises(Rejected):
                check_backend(local, run, rows)

    def test_backend_stale_identity_private_leak_and_type_coercion(self):
        records, run = fixture()
        local = w.validate_local(records, run)
        for field, value in [("application_id", "browser-app"), ("session_id", "browser-session"),
                             ("run_id", "restored"), ("leaked_internal_attribute", True),
                             ("source", "ios"), ("has_replay", 1), ("is_active", 0),
                             ("time_spent", "1000000"), ("action_count", False), ("error_count", 1),
                             ("document_id", "restored"), ("long_task_count", 1), ("format_version", "2"),
                             ("document_version", 2), ("loading_type", "route_change")]:
            rows = backend(local, run)
            rows[6][field] = value
            with self.assertRaises(Rejected, msg=field):
                check_backend(local, run, rows)

    def test_backend_complete_inventory_required(self):
        records, run = fixture()
        local = w.validate_local(records, run)
        for mode in ["missing", "duplicate", "extra", "foreign"]:
            rows = backend(local, run)
            if mode == "missing":
                rows.pop()
            elif mode == "duplicate":
                rows[-1] = copy.deepcopy(rows[-2])
            elif mode == "extra":
                rows.append(copy.deepcopy(rows[0]))
            else:
                rows[-1]["view_id"] = IDS["application"]
            with self.assertRaises(Rejected):
                check_backend(local, run, rows)

    def test_unexpected_backend_families_or_crash_rejected(self):
        records, run = fixture()
        local = w.validate_local(records, run)
        for args in [([{}], [], 0, 0), ([], [{}], 0, 0), ([], [], 1, 0), ([], [], 0, 1),
                     ([], [], False, 0)]:
            with self.assertRaises(Rejected):
                w.validate_backend(local, run, backend(local, run), *args)
