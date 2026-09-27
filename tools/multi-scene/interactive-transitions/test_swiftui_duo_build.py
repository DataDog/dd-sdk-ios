import copy
import io
import json
from pathlib import Path
import tempfile
import tarfile
import unittest
from unittest.mock import patch

import swiftui_duo_build as subject


class SourceIsolation(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name); self.client = self.root/'client'; self.client.mkdir()
        self.project = self.client/'Transitions.xcodeproj'; self.project.mkdir()
        (self.project/'project.pbxproj').write_text('frozen project')
        (self.client/'CredentialInclude.xcconfig').write_text('#include "' +
            str(subject.shared.REPO/'xcconfigs/Datadog.local.xcconfig') + '"\n')
        self.spec = dict(packages={'SDK': {'path': '../sdk'}}, targets={})
        for framework in ['UIKit', 'SwiftUI']:
            self.spec['targets'][framework+'Transitions'] = dict(
                sources=[dict(path=n) for n in ['Observation.swift', 'HumanObservation.swift',
                    'TransitionObservation.swift', framework+'App.swift']],
                dependencies=[dict(package='SDK', product=n) for n in ['DatadogCore', 'DatadogRUM']])
        self.write_spec()
        self.graph = dict(objects={'sdk': dict(isa='XCLocalSwiftPackageReference', relativePath='../sdk'),
                                   'file': dict(isa='PBXFileReference', path='SwiftUIApp.swift', sourceTree='<group>')})

    def write_spec(self):
        (self.client/'project.json').write_text(json.dumps(self.spec))

    def assert_rejected(self, call):
        with self.assertRaises(subject.shared.Rejected): call()

    def test_container_paths_are_accepted(self):
        self.assertEqual(subject.project_boundary(self.root, self.graph)['paths'], ['../sdk', 'SwiftUIApp.swift'])

    def test_absolute_checkout_source_is_rejected(self):
        self.graph['objects']['file']['path'] = str(subject.shared.REPO/'DatadogRUM/Sources/RUMMonitor.swift')
        self.assert_rejected(lambda: subject.project_boundary(self.root, self.graph))

    def test_relative_escape_is_rejected(self):
        self.graph['objects']['file']['path'] = '../../foreign.swift'
        self.assert_rejected(lambda: subject.project_boundary(self.root, self.graph))

    def test_symlink_escape_is_rejected(self):
        (self.client/'SwiftUIApp.swift').symlink_to('/tmp/foreign.swift')
        self.assert_rejected(lambda: subject.project_boundary(self.root, self.graph))

    def test_unbound_local_sdk_is_rejected(self):
        self.graph['objects']['sdk']['relativePath'] = '../other-sdk'
        self.assert_rejected(lambda: subject.project_boundary(self.root, self.graph))

    def test_remote_dependency_is_rejected(self):
        self.graph['objects']['sdk']['isa'] = 'XCRemoteSwiftPackageReference'
        self.assert_rejected(lambda: subject.project_boundary(self.root, self.graph))

    def test_script_phase_is_rejected(self):
        self.graph['objects']['script'] = dict(isa='PBXShellScriptBuildPhase')
        self.assert_rejected(lambda: subject.project_boundary(self.root, self.graph))

    def test_extra_compiled_fixture_is_rejected(self):
        self.spec['targets']['SwiftUITransitions']['sources'].append(dict(path='CurrentObserver.swift')); self.write_spec()
        self.assert_rejected(lambda: subject.project_boundary(self.root, self.graph))

    def test_specification_cannot_use_other_worktree(self):
        self.spec['packages']['SDK']['path'] = '/other/worktree'; self.write_spec()
        self.assert_rejected(lambda: subject.project_boundary(self.root, self.graph))

    def test_qualified_fixture_replaces_current_observer_exactly(self):
        source = self.root/'qualified'; source.mkdir()
        for name in subject.FILES:
            (source/name).write_text('qualified '+name); (self.client/name).write_text('current '+name)
        expected = subject.fixture(source); subject.copy_fixture(source, self.client, expected)
        self.assertEqual(subject.fixture(self.client), expected)

    def test_foreign_fixture_file_is_rejected(self):
        for name in subject.FILES: (self.client/name).write_text(name)
        (self.client/'CurrentObserver.swift').write_text('wrong source')
        self.assert_rejected(lambda: subject.fixture(self.client))

    def test_source_and_target_cannot_alias(self):
        for name in subject.FILES: (self.client/name).write_text(name)
        self.assert_rejected(lambda: subject.copy_fixture(self.client, self.client, subject.fixture(self.client)))

    def test_sdk_bytes_must_match_git_archive(self):
        stream = io.BytesIO()
        with tarfile.open(fileobj=stream, mode='w') as archive:
            info = tarfile.TarInfo('DatadogRUM/Sources/Example.swift'); info.size = 4
            archive.addfile(info, io.BytesIO(b'code'))
        raw = stream.getvalue(); (self.root/'source.tar').write_bytes(raw)
        sdk = self.root/'sdk'; path = sdk/'DatadogRUM/Sources/Example.swift'; path.parent.mkdir(parents=True)
        path.write_bytes(b'code'); (sdk/'Package.swift').write_text('local package')
        with patch.object(subject.shared, 'capture') as capture:
            capture.return_value.stdout = raw
            self.assertEqual(subject.archive_binding(self.root, 'candidate')['archived_files'], 1)
            path.write_bytes(b'worktree contamination')
            self.assert_rejected(lambda: subject.archive_binding(self.root, 'candidate'))


class DestinationBinding(unittest.TestCase):
    def setUp(self):
        runtime = 'com.apple.CoreSimulator.SimRuntime.iOS-27-1'
        self.inventory = dict(devices={runtime: [dict(udid='Duo', name='iPhone Duo', state='Booted',
            isAvailable=True, deviceTypeIdentifier='com.apple.CoreSimulator.SimDeviceType.iPhone-Duo')]},
            runtimes=[dict(identifier=runtime, version='27.1', buildversion='fixture-build', isAvailable=True)])

    def test_duo_destination_is_bound(self):
        self.assertEqual(subject.destination(self.inventory)['device']['udid'], 'Duo')

    def test_ordinary_capture_destination_is_not_duo(self):
        next(iter(self.inventory['devices'].values()))[0]['deviceTypeIdentifier'] = 'ordinary-iPad'
        with self.assertRaises(subject.shared.Rejected): subject.destination(self.inventory)

    def test_shutdown_destination_is_not_ready(self):
        next(iter(self.inventory['devices'].values()))[0]['state'] = 'Shutdown'
        with self.assertRaises(subject.shared.Rejected): subject.destination(self.inventory)

    def test_ambiguous_duo_is_rejected(self):
        values = next(iter(self.inventory['devices'].values())); values.append(copy.deepcopy(values[0]))
        with self.assertRaises(subject.shared.Rejected): subject.destination(self.inventory)

    def test_unavailable_runtime_is_rejected(self):
        self.inventory['runtimes'][0]['isAvailable'] = False
        with self.assertRaises(subject.shared.Rejected): subject.destination(self.inventory)


class QualificationProvenance(unittest.TestCase):
    def setUp(self):
        self.ref = dict(path='/qualified/plan.json', sha256='plan')
        self.identity = dict(framework='SwiftUI', layout='stack', tracking='automatic', source='A', fixture='fixture')
        self.outcome = dict(plan=self.ref, candidate_executed=False, backend_queried=False, release_acceptance=False,
                            gate_closures=[], summary={'sha256': 'summary'}, quiescence={'sha256': 'quiet'})
        self.plan = dict(device=dict(udid='ordinary', runtime='27.0', deviceTypeIdentifier='iPad', state='Shutdown'))
        self.summary = dict(identity=self.identity, state='PASS', scenario='PASS', evidence='PASS', cleanup='PASS',
                            release_acceptance=False, restored_at=5, cleanup_deadline=10)
        self.native = dict(identity=self.identity)
        self.cleanup = dict(state='PASS', task_pid_absent=True, native_runner=self.outcome['summary'],
                            quiescence=self.outcome['quiescence'], device=self.plan['device'])
        self.quiet = dict(native_identity=self.identity, plan_sha256='plan', worker_stopped=True, runner_stopped=True,
                          tool_pending=None, local_pending=None, all_published_requests_complete=True)

    def check(self):
        subject.qualification_identity(self.outcome, self.plan, self.summary, self.native, self.cleanup, self.quiet,
                                       source='A', fixture_id='fixture', plan_ref=self.ref)

    def test_exact_ordinary_qualification_is_accepted(self): self.check()

    def test_wrong_capture_dimensions_are_rejected(self):
        for key, value in dict(framework='UIKit', layout='split', tracking='manual', source='B', fixture='new').items():
            with self.subTest(key=key):
                previous = self.identity[key]; self.identity[key] = value
                with self.assertRaises(subject.shared.Rejected): self.check()
                self.identity[key] = previous

    def test_outcome_cannot_claim_different_scope(self):
        for key in ['candidate_executed', 'backend_queried', 'release_acceptance']:
            with self.subTest(key=key):
                self.outcome[key] = True
                with self.assertRaises(subject.shared.Rejected): self.check()
                self.outcome[key] = False

    def test_foreign_outcome_plan_is_rejected(self):
        self.outcome['plan'] = dict(path='/other/plan.json', sha256='other')
        with self.assertRaises(subject.shared.Rejected): self.check()

    def test_pending_input_cannot_certify_reuse(self):
        self.quiet['tool_pending'] = 'unknown effect'
        with self.assertRaises(subject.shared.Rejected): self.check()

    def test_incomplete_cleanup_cannot_certify_reuse(self):
        self.summary['cleanup'] = 'INCOMPLETE'
        with self.assertRaises(subject.shared.Rejected): self.check()


if __name__ == '__main__': unittest.main()
