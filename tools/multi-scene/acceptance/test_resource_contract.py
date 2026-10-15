import copy
import json
from pathlib import Path
import unittest
from acceptance_common import Rejected
import resource_contract as r


def fixture():
    run_id = "exp176-unit-run"
    contract = json.loads(Path(__file__).with_name(r.CONTRACT).read_text())
    records = [{"type": "manifest", "manifest": dict(runID=run_id, runMode="clean", validationErrors=[], scenario=contract)}]
    signals = []

    def signal(kind, **fields):
        s = dict(kind=kind, sequence=len(signals) + 1, runID=run_id, scenarioID=r.SCENARIO,
                 schemaVersion=5, evidenceSource="probe")
        s.update(fields)
        signals.append(s)
        return s

    def view(view_id, name, session="old", scene=None, screen=None):
        return signal("rum-view-snapshot", evidenceSource="rum-mapper",
                      semanticContext=dict(logicalSceneID=scene, screen=screen),
                      rumContext=dict(viewID=view_id, sessionID=session, viewName=name, viewActive=True))

    def assertion(name, context=None):
        fields = dict(name=name, result="PASS")
        if context:
            fields.update(evidenceSource="internal-hook", rumContext=context)
        return signal("assertion", **fields)

    view("launch", "ApplicationLaunch")
    for scene in ["scene-A", "scene-B"]:
        signal("scene-ready", semanticContext=dict(logicalSceneID=scene, nativeSceneID="native-" + scene))
        view(scene, "ProbeHomeView", scene=scene, screen="home")
    signal("step-started", stepKind="run-resource-ownership-batch", stepIndex=4)
    old_a = dict(viewID="scene-A", sessionID="old")
    old_b = dict(viewID="scene-B", sessionID="old")
    assertion("resource-owner-a", old_a)
    assertion("resource-owner-b", old_b)
    for phase in r.PHASES:
        assertion("resource-start-" + phase, old_b if phase == r.LEGACY else old_a)
    for phase in r.AUTO:
        assertion("transport-paused-" + phase)
    assertion("resource-all-started")
    assertion("resource-foreground-ready")
    signal("assertion", name="resource-a-owner-retired", result="PASS", evidenceSource="internal-hook",
           activationState="background", semanticContext=dict(nativeSceneID="native-scene-A"), rumContext=old_a)
    view("next-b", "Resource Next B")
    assertion("resource-navigation-finished")
    view("new-b", "Resource New B", "new")
    assertion("resource-new-owner-b", dict(viewID="new-b", sessionID="new"))
    assertion("resource-release-boundary")
    for phase in r.PHASES:
        error = phase in r.FAILURES
        url = "https://resource-probe.invalid/" + run_id + "/" + phase
        status = 200 if phase in r.AUTO else (0 if error else 201)
        payload = dict(id=phase)
        if error:
            payload.update(resourceURL=url, resourceStatusCode=status, source="network", isCrash=False)
        else:
            payload.update(url=url, statusCode=status, method={r.SWIFT[0]: "POST", r.SWIFT[2]: "PUT"}.get(phase, "GET"),
                           durationNanoseconds=10000, size=2 if phase in r.AUTO else 55)
        signal("rum-error" if error else "rum-resource", name=phase, evidenceSource="rum-mapper",
               rumContext=old_b if phase == r.LEGACY else old_a,
               sourceContext=dict(logicalSceneID="scene-A"), **{"error" if error else "resource": payload})
    for phase in r.AUTO:
        assertion("transport-finished-" + phase)
    signal("rum-action", name=r.PEER, evidenceSource="rum-mapper", rumContext=dict(viewID="new-b", sessionID="new"),
           action=dict(id="peer", type="tap", target=r.PEER, resourceCount=0, errorCount=0))
    assertion("resource-local-owners-verified")
    assertion("resource-batch-finished")
    records.extend(dict(type="signal", signal=s) for s in signals)
    records.append(dict(type="semantic-result", runID=run_id,
                        result=dict(scenarioID=r.SCENARIO, state="PASS", matchedExpectationCount=22, issues=[])))
    return records, run_id


def backend(local, run_id):
    resources, errors = [], []
    for e in local["completions"]:
        row = dict(e, run_id=run_id)
        if e["kind"] == "error":
            row.update(error_source="network", is_crash=False)
            errors.append(row)
        else:
            resources.append(row)
    return [resources, errors, [dict(v, run_id=run_id) for v in local["views"]],
            [dict(local["peer"], run_id=run_id)], 0]


class ResourceContractTests(unittest.TestCase):
    def setUp(self):
        self.records, self.run_id = fixture()

    def signals(self):
        return [v["signal"] for v in self.records if v["type"] == "signal"]

    def named(self, name):
        return next(s for s in self.signals() if s.get("name") == name)

    def rejects(self, message):
        with self.assertRaisesRegex(Rejected, message):
            r.validate_local(self.records, self.run_id)

    def test_complete_local_and_backend(self):
        local = r.validate_local(self.records, self.run_id)
        self.assertEqual(r.validate_backend(local, self.run_id, *backend(local, self.run_id))["state"], "PASS")

    def test_stale_contract_with_same_counts(self):
        self.records[0]["manifest"]["scenario"]["completionConditions"][0]["scene"] = "scene-B"
        self.rejects("fixture contract")

    def test_consumed_readiness(self):
        self.records[0]["manifest"]["scenario"]["steps"][3] = dict(kind="wait-for-scene-ready", scene="scene-B")
        self.rejects("consumed twice")

    def test_stale_run(self):
        self.signals()[0]["runID"] = "previous"
        self.rejects("stale signal")

    def test_missing_sequence(self):
        self.signals()[3]["sequence"] += 1
        self.rejects("signal sequence")

    def test_app_pass_cannot_hide_wrong_owner(self):
        self.named(r.SWIFT[0])["rumContext"] = dict(viewID="scene-B", sessionID="old")
        self.rejects("exact completion owner")

    def test_new_session_cannot_steal_old_completion(self):
        self.named(r.AUTO[0])["rumContext"] = dict(viewID="new-b", sessionID="new")
        self.rejects("exact completion owner")

    def test_legacy_fallback_must_be_b(self):
        self.named(r.LEGACY)["rumContext"] = dict(viewID="scene-A", sessionID="old")
        self.rejects("exact completion owner")

    def test_internal_hook_cannot_replace_mapper_prerequisite(self):
        next(s for s in self.signals() if s["kind"] == "rum-view-snapshot")["evidenceSource"] = "internal-hook"
        self.rejects("non-mapper view")

    def test_inactive_prerequisite(self):
        next(s for s in self.signals() if s.get("rumContext", {}).get("viewID") == "scene-A")["rumContext"]["viewActive"] = False
        with self.assertRaises(Rejected) as error:
            r.validate_local(self.records, self.run_id)
        self.assertEqual(error.exception.state, "INCONCLUSIVE")

    def test_start_snapshot_must_match_mapper(self):
        self.named("resource-owner-a")["rumContext"] = dict(viewID="foreign", sessionID="old")
        self.rejects("independent mapper")

    def reorder(self, first, second):
        signals = self.signals()
        a, b = signals.index(self.named(first)), signals.index(self.named(second))
        signals[a], signals[b] = signals[b], signals[a]
        for index, s in enumerate(signals):
            s["sequence"] = index + 1
        self.records = [self.records[0]] + [dict(type="signal", signal=s) for s in signals] + [self.records[-1]]

    def test_late_start_assertion(self):
        self.reorder("resource-start-" + r.SWIFT[0], "resource-release-boundary")
        self.rejects("critical boundary")

    def test_completion_before_release(self):
        self.reorder(r.SWIFT[0], "resource-release-boundary")
        self.rejects("critical boundary")

    def test_verification_before_completion(self):
        self.reorder(r.SWIFT[0], "resource-local-owners-verified")
        self.rejects("critical boundary")

    def test_duplicate_completion(self):
        value = copy.deepcopy(self.named(r.SWIFT[0]))
        value["sequence"] = len(self.signals()) + 1
        self.records.insert(-1, dict(type="signal", signal=value))
        self.rejects("missing/duplicate/unexpected")

    def test_lost_response_headers(self):
        self.named(r.AUTO[1])["error"]["resourceStatusCode"] = 0
        self.rejects("response status")

    def test_wrong_metrics(self):
        self.named(r.SWIFT[0])["resource"]["size"] = 0
        self.rejects("Resource size")

    def test_missing_duration(self):
        self.named(r.AUTO[0])["resource"]["durationNanoseconds"] = 0
        self.rejects("duration")

    def test_later_action_correlation(self):
        self.named(r.SWIFT[0])["rumContext"] = dict(viewID="scene-A", sessionID="old", actionIDs=["peer"])
        self.rejects("later action")

    def test_old_resource_increments_peer(self):
        self.named(r.PEER)["action"]["resourceCount"] = 1
        self.rejects("contaminated peer")

    def test_old_error_increments_peer(self):
        self.named(r.PEER)["action"]["errorCount"] = 1
        self.rejects("contaminated peer")

    def test_foreground_precondition_must_follow_captured_starts(self):
        self.reorder("resource-foreground-ready", "resource-all-started")
        self.rejects("critical boundary")

    def test_lifecycle_markers_require_prior_mapper_evidence(self):
        for name, marker in [("Resource Next B", "resource-navigation-finished"),
                             ("Resource New B", "resource-new-owner-b")]:
            with self.subTest(view=name):
                self.records, self.run_id = fixture()
                signals = self.signals()
                mapped = next(s for s in signals if s.get("rumContext", {}).get("viewName") == name)
                a, b = signals.index(mapped), signals.index(self.named(marker))
                signals[a], signals[b] = signals[b], signals[a]
                for index, value in enumerate(signals):
                    value["sequence"] = index + 1
                self.records = [self.records[0]] + [dict(type="signal", signal=value) for value in signals] + [self.records[-1]]
                self.rejects("preceded mapper evidence")

    def test_owner_ending_between_batch_and_start_is_inconclusive(self):
        signals = self.signals()
        prior = copy.deepcopy(next(s for s in signals if s.get("rumContext", {}).get("viewID") == "scene-A"))
        prior["rumContext"]["viewActive"] = False
        signals.insert(signals.index(self.named("resource-start-" + r.SWIFT[0])), prior)
        for index, value in enumerate(signals):
            value["sequence"] = index + 1
        self.records = [self.records[0]] + [dict(type="signal", signal=value) for value in signals] + [self.records[-1]]
        with self.assertRaises(Rejected) as error:
            r.validate_local(self.records, self.run_id)
        self.assertEqual(error.exception.state, "INCONCLUSIVE")
        self.assertIn("ended before Resource start", str(error.exception))

    def test_backend_mutations(self):
        local = r.validate_local(self.records, self.run_id)
        mutations = [(0, "view_id", "wrong"), (0, "duration_ns", 1), (0, "size", 0),
                     (1, "status", 404), (1, "action_ids", ["peer"]), (2, "run_id", "old"),
                     (2, "name", "unexpected"), (3, "resource_count", 1), (3, "error_count", 1)]
        for collection, field, value in mutations:
            with self.subTest(collection=collection, field=field):
                rows = backend(local, self.run_id)
                rows[collection][0][field] = value
                with self.assertRaises(Rejected):
                    r.validate_backend(local, self.run_id, *rows)

    def test_backend_missing_duplicate_and_crash(self):
        local = r.validate_local(self.records, self.run_id)
        for index in range(5):
            with self.subTest(collection=index):
                rows = backend(local, self.run_id)
                if index == 4:
                    rows[index] = 1
                else:
                    rows[index].append(rows[index][0])
                with self.assertRaises(Rejected):
                    r.validate_backend(local, self.run_id, *rows)
