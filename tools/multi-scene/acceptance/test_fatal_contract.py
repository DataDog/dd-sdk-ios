import copy
import json
from pathlib import Path
import unittest
from acceptance_common import Rejected
import fatal_contract as f


def uid(number):
    return f"00000000-0000-0000-0000-{number:012d}"


def fixture():
    contracts = json.loads(Path(__file__).with_name(f.CONTRACT).read_text())
    run = "exp184-unit"
    phases = []
    crash_time = 100000
    original = None
    for index, scenario in enumerate(f.SCENARIOS):
        run_id = run if index == 0 else run + "-" + str(index)
        pid, sid = 1840 + index, uid(index + 1)
        records = [dict(type="manifest", manifest=dict(runID=run_id, runMode="clean",
                   validationErrors=[], scenario=contracts[scenario]))]
        signals = []

        def add(kind, **kw):
            value = dict(kind=kind, sequence=len(signals) + 1, schemaVersion=5, runID=run_id,
                         scenarioID=scenario, evidenceSource="internal-hook", timestampMilliseconds=crash_time)
            value.update(kw)
            signals.append(value)
            records.append(dict(type="signal", signal=value))
            return value

        def assertion(name, context=None, **fatal):
            args = dict(name=name, result="PASS", fatal=dict(processID=pid, **fatal))
            if context is not None:
                args["rumContext"] = context
            return add("assertion", **args)

        def view(vid, name, scene=None, session=sid, revision=1, count=0, mutation=False):
            context = dict(sessionID=session, viewID=vid, viewName=name, viewActive=count == 0,
                           viewDocumentVersion=revision)
            observation = dict(processID=pid, documentVersion=revision, viewErrorCount=count, viewCrashCount=count)
            if mutation:
                observation.update(peerMutation="A", mutationTiming=1000)
            add("rum-view-snapshot", evidenceSource="rum-mapper", rumContext=context, fatal=observation,
                semanticContext=dict(logicalSceneID=scene, nativeSceneID="native-" + str(scene)))
            return context

        assertion("fatal-process")
        add("rum-session-started", rumContext=dict(sessionID=sid, sessionDiscarded=False), evidenceSource="rum-mapper")
        view(uid(10 + index), "ApplicationLaunch")
        if index == 0:
            a = view(uid(20), "ProbeHomeView", "scene-A")
            b = view(uid(21), "ProbeHomeView", "scene-B")
            for name, context, scene in [("fatal-owner-a", a, "scene-A"), ("fatal-owner-b", b, "scene-B")]:
                assertion(name, context)
                signals[-1]["sourceContext"] = dict(logicalSceneID=scene, nativeSceneID="native-" + scene)
            assertion("fatal-export-before", b)
            assertion("fatal-provider-before", b)
            assertion("fatal-mutation-dispatched", a)
            view(uid(20), "ProbeHomeView", "scene-A", revision=2, mutation=True)
            assertion("fatal-export-after", b)
            assertion("fatal-provider-after", b)
            assertion("fatal-capture-unchanged", a)
            assertion("fatal-injection-drained", b, documentVersion=1, viewErrorCount=0, viewCrashCount=0)
            assertion("fatal-prepare-complete")
            original = b
        else:
            current = view(uid(30 + index), "FatalRecovery")
            assertion("fatal-recovery-current", current)
            assertion("fatal-reporter-enable")
            if index == 1:
                payload = assertion("fatal-error-payload", original, originalRunID=run,
                                    nativeSource="ios", exceptionType="SIGABRT", incidentIdentifier=uid(100),
                                    crashedProcess="Probe [1840]", hasAction=False, hasContainer=False)
                payload.update(evidenceSource="rum-mapper", eventID=uid(101))
                add("rum-error", evidenceSource="rum-mapper", eventID=uid(101),
                    rumContext=dict(original, eventDateMilliseconds=crash_time),
                    error=dict(isCrash=True, source="source", type="SIGABRT (#0)"))
                view(uid(21), "ProbeHomeView", session=uid(1), revision=2, count=1)
            assertion("fatal-launch-report", launchDidCrash=index == 1)
            assertion("fatal-recovery-complete", current)
        records.append(dict(type="semantic-result", runID=run_id, result=dict(
            scenarioID=scenario, state="PASS", issues=[], matchedExpectationCount=24 if index == 0 else 10)))
        if index == 0:
            assertion("fatal-crash-boundary", original)
        phases.append(dict(scenario_id=scenario, run_id=run_id, records=records, process_id=pid,
                           installed_binary_sha256="a" * 64, data_container="/synthetic/current-install",
                           terminated=True, process_exit=-6 if index == 0 else None))
    return phases, run


def named(phases, phase, name):
    return next(r["signal"] for r in phases[phase]["records"] if r.get("signal", {}).get("name") == name)


def backend(local):
    views = []
    for value in local["view_inventory"]:
        count = int(value["view_id"] == local["original_b"]["view_id"])
        phase_index = local["session_ids"].index(value["session_id"])
        views.append(dict(value, source="ios", container_present=False, error_count=count, crash_count=count,
                          action_count=0, resource_count=0, is_active=not count, document_version=2 if count else 1,
                          run_id=local["run_ids"][phase_index]))
    error = dict(local["fatal"], source="ios", run_id=local["run_ids"][0], phase="fatal-original",
                 error_source="source", is_crash=True, container_present=False, action_present=False)
    return views, [error], [], [], 2


class FatalContractTests(unittest.TestCase):
    def setUp(self):
        self.phases, self.run = fixture()

    def reject(self):
        with self.assertRaises(Rejected):
            f.validate_local(self.phases, self.run)

    def test_full_three_process_contract(self):
        local = f.validate_local(self.phases, self.run)
        self.assertEqual(local["native_expectations"], 44)
        self.assertEqual(f.validate_backend(local, self.run, *backend(local))["state"], "PASS")

    def test_reused_phase_identifier(self):
        self.phases[2]["run_id"] = self.phases[1]["run_id"]
        self.reject()

    def test_restored_manifest_run(self):
        self.phases[1]["records"][0]["manifest"]["runID"] = self.run
        self.reject()

    def test_stale_binary_or_install(self):
        for field in ["installed_binary_sha256", "data_container"]:
            with self.subTest(field=field):
                self.phases, self.run = fixture()
                self.phases[1][field] += "old"
                self.reject()

    def test_wrong_frozen_contract(self):
        self.phases[0]["records"][0]["manifest"]["scenario"]["steps"].reverse()
        self.reject()

    def test_process_reuse(self):
        self.phases[1]["process_id"] = self.phases[0]["process_id"]
        self.reject()

    def test_normal_or_unconfirmed_exit(self):
        for code in [None, 0]:
            self.phases[0]["process_exit"] = code
            self.reject()

    def test_premature_crash(self):
        records = self.phases[0]["records"]
        records[-1], records[-2] = records[-2], records[-1]
        self.reject()

    def test_late_guard(self):
        guard = named(self.phases, 0, "fatal-export-after")
        guard["sequence"] = 999
        self.reject()

    def test_peer_substitutes_export(self):
        named(self.phases, 0, "fatal-export-after")["rumContext"] = named(self.phases, 0, "fatal-owner-a")["rumContext"]
        self.reject()

    def test_missing_peer_mapper_witness(self):
        for record in self.phases[0]["records"]:
            record.get("signal", {}).get("fatal", {}).pop("mutationTiming", None)
        self.reject()

    def test_captured_value_drifts(self):
        named(self.phases, 0, "fatal-capture-unchanged")["rumContext"] = named(self.phases, 0, "fatal-owner-b")["rumContext"]
        self.reject()

    def test_recovery_owner_substitution(self):
        current = named(self.phases, 1, "fatal-recovery-current")["rumContext"]
        error = next(r["signal"] for r in self.phases[1]["records"] if r.get("signal", {}).get("kind") == "rum-error")
        error["rumContext"] = current
        self.reject()

    def test_missing_or_duplicate_error(self):
        for duplicate in [False, True]:
            self.phases, self.run = fixture()
            records = self.phases[1]["records"]
            error = next(r for r in records if r.get("signal", {}).get("kind") == "rum-error")
            if duplicate:
                records.insert(-1, copy.deepcopy(error))
            else:
                records.remove(error)
            self.reject()

    def test_absent_or_contradictory_consumption_ack(self):
        for value in [None, True]:
            named(self.phases, 2, "fatal-launch-report")["fatal"]["launchDidCrash"] = value
            self.reject()

    def test_stale_report_origin_and_process(self):
        for field, value in [("originalRunID", "stale"), ("crashedProcess", "Probe [1]"),
                             ("exceptionType", "SIGSEGV"), ("nativeSource", "browser"),
                             ("incidentIdentifier", None), ("hasContainer", True)]:
            with self.subTest(field=field):
                self.phases, self.run = fixture()
                named(self.phases, 1, "fatal-error-payload")["fatal"][field] = value
                self.reject()

    def test_updated_document_must_follow_injected_revision(self):
        named(self.phases, 0, "fatal-injection-drained")["fatal"]["documentVersion"] = 18
        self.reject()

    def test_backend_owner_and_metadata_mutations(self):
        local = f.validate_local(self.phases, self.run)
        for field, value in [("view_id", uid(20)), ("session_id", uid(2)), ("event_id", uid(102)),
                             ("run_id", "recovery"), ("source", "browser"), ("incident_id", uid(103)),
                             ("is_crash", False), ("action_present", True), ("phase", None)]:
            with self.subTest(field=field):
                values = backend(local)
                values[1][0][field] = value
                with self.assertRaises(Rejected):
                    f.validate_backend(local, self.run, *values)

    def test_backend_count_ownership_and_completeness(self):
        local = f.validate_local(self.phases, self.run)
        for mutation in ["missing-view", "extra-error", "peer-count", "reused-run", "wrong-document"]:
            with self.subTest(mutation=mutation):
                views, errors, actions, resources, count = backend(local)
                if mutation == "missing-view":
                    views.pop()
                elif mutation == "extra-error":
                    errors.append(copy.deepcopy(errors[0]))
                elif mutation == "peer-count":
                    views[0]["crash_count"] = 1
                elif mutation == "reused-run":
                    next(v for v in views if v["name"] == "FatalRecovery")["run_id"] = self.run
                else:
                    next(v for v in views if v["crash_count"] == 1)["document_version"] = 4
                with self.assertRaises(Rejected):
                    f.validate_backend(local, self.run, views, errors, actions, resources, count)


if __name__ == "__main__":
    unittest.main()
