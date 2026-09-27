import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import swiftui_duo_runtime as runtime


class FreshSession(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup); self.root = Path(self.temp.name)
        self.hierarchy = self.root/'hierarchy.txt'; self.hierarchy.write_text('Application bundle identifier: com.apple.springboard\n')
        self.setup = dict(device='duo', started_at=1, deadline=100)
        self.start = dict(started_at=2, finished_at=3, actual_return={'structuredContent': dict(deviceUUID='duo',
            deviceIsSimulator=True, interactionSessionKey='fresh')})
        self.probe = dict(started_at=4, finished_at=5, command='', interaction_session_key='fresh',
            actual_return={'structuredContent': dict(applicationState='Running', hierarchyPath=str(self.hierarchy),
                screenshotPath=str(self.root/'capture.png'))})

    def check(self, now=6): return runtime.session_ready(self.setup, self.start, self.probe, now=now)
    def test_fresh_current_home_is_accepted(self): self.check()
    def test_foreign_session_is_rejected(self):
        self.probe['interaction_session_key'] = 'previous'
        with self.assertRaises(runtime.shared.Rejected): self.check()
    def test_foreign_device_is_rejected(self):
        self.start['actual_return']['structuredContent']['deviceUUID'] = 'ordinary'
        with self.assertRaises(runtime.shared.Rejected): self.check()
    def test_expired_original_setup_is_rejected(self):
        with self.assertRaises(runtime.shared.Rejected): self.check(now=101)
    def test_old_observation_is_rejected(self):
        with self.assertRaises(runtime.shared.Rejected): self.check(now=66)
    def test_capture_before_session_is_rejected(self):
        self.probe['started_at'] = 1
        with self.assertRaises(runtime.shared.Rejected): self.check()
    def test_nonempty_setup_cannot_be_readiness(self):
        self.probe['command'] = 'b h'
        with self.assertRaises(runtime.shared.Rejected): self.check()
    def test_other_application_is_not_home(self):
        self.hierarchy.write_text('Application bundle identifier: com.example.other\n')
        with self.assertRaises(runtime.shared.Rejected): self.check()


class ActualFoldState(unittest.TestCase):
    def setUp(self):
        self.raw = dict(info=dict(outcome='success', commandType='devicectl.device.info.displays', arguments=['--device', 'duo']),
            result=dict(displays=[dict(uniqueId='00000000-0000-4000-8000-000000000001', active=True, nativeSize=[100, 200],
                pointScale=2, currentOrientation='rot0', backlightState='activeOn'),
                dict(uniqueId='00000000-0000-4000-8000-000000000002', active=False, nativeSize=[200, 200])]))
    def test_actual_outer_display_is_closed(self): runtime.actual_closed(self.raw, 'duo')
    def test_sidebar_label_cannot_substitute_display(self):
        self.raw['result'] = dict(sidebar='Closed')
        with self.assertRaises(Exception): runtime.actual_closed(self.raw, 'duo')
    def test_open_display_is_rejected(self):
        self.raw['result']['displays'][0]['nativeSize'] = [300, 300]
        with self.assertRaises(runtime.shared.Rejected): runtime.actual_closed(self.raw, 'duo')
    def test_foreign_display_return_is_rejected(self):
        with self.assertRaises(Exception): runtime.actual_closed(self.raw, 'other')


class WorkerCleanup(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup); self.root = Path(self.temp.name).resolve()
        (self.root/'plan.json').write_text('{}'); (self.root/'cells/SwiftUI/input').mkdir(parents=True)
        self.summary = dict(scenario='PASS', identity={'pid': 1})
        binding = dict(root=str(self.root), framework='SwiftUI', session_key='fresh', device='duo',
            process_identity={'pid': 1, 'start': 'now'}, identity=self.summary['identity'], plan_sha256=runtime.shared.sha(self.root/'plan.json'))
        path = self.root/'sessions/SwiftUI/sequence/binding.json'; path.parent.mkdir(parents=True); path.write_text(json.dumps(binding))
        started = dict(root=str(self.root), plan_sha256=binding['plan_sha256'], matrix_sha256='matrix', pid=2,
            process_identity={'pid': 2, 'start': 'now'}, argv=['runner'], log_path='/log', started_at=1)
        (self.root/'runner-started.json').write_text(json.dumps(started))
        terminal = dict(started, runner_stopped=True, started_receipt_sha256=runtime.shared.sha(self.root/'runner-started.json'), finished_at=3)
        (self.root/'runner-terminal.json').write_text(json.dumps(terminal))
        self.worker = dict(plan_sha256=runtime.shared.sha(self.root/'plan.json'), worker_stopped=True,
            runner_stopped=True, all_published_requests_complete=True, root=str(self.root), framework='SwiftUI',
            session_key='fresh', device='duo', process_identity=binding['process_identity'], native_identity=binding['identity'],
            sequence_binding=runtime.builds.reference(path), runner_terminal=runtime.builds.reference(self.root/'runner-terminal.json'),
            finished_at=4, tool_pending=None, local_pending=None, actual_sequence_return=dict(state='TERMINAL', completed=11))
    def check(self):
        with patch.object(runtime.driver, 'process_identity', return_value=None), patch.object(runtime.sequence, 'progress', return_value=11):
            return runtime.worker_quiet(self.root, self.summary, self.worker)
    def test_returned_complete_worker_is_accepted(self): self.check()
    def test_progress_reads_bound_sequence_not_last_prompt(self):
        folder = self.root/'cells/SwiftUI/input/pop.before'; folder.mkdir(); (folder/'prompt.json').write_text('{}')
        with patch.object(runtime.driver, 'process_identity', return_value=None), patch.object(runtime.q, 'completed_input'), \
                patch.object(runtime.sequence, 'progress', return_value=11) as progress:
            runtime.worker_quiet(self.root, self.summary, self.worker)
        self.assertEqual(progress.call_args.args[1], self.root/'sessions/SwiftUI/sequence')
    def test_active_input_worker_cannot_authorize_cleanup(self):
        self.worker['worker_stopped'] = False
        with self.assertRaises(runtime.shared.Rejected): self.check()
    def test_pending_tool_cannot_authorize_cleanup(self):
        self.worker['tool_pending'] = dict(command='mt')
        with self.assertRaises(runtime.shared.Rejected): self.check()
    def test_native_runner_not_stopped_blocks_cleanup(self):
        self.worker['runner_stopped'] = False
        with self.assertRaises(runtime.shared.Rejected): self.check()
    def test_live_runner_blocks_cleanup(self):
        with patch.object(runtime.driver, 'process_identity', return_value={'pid': 2, 'start': 'now'}):
            with self.assertRaises(runtime.shared.Rejected): runtime.worker_quiet(self.root, self.summary, self.worker)
    def test_foreign_sequence_binding_blocks_cleanup(self):
        self.worker['sequence_binding']['sha256'] = 'other'
        with self.assertRaises(runtime.shared.Rejected): self.check()
    def test_foreign_process_binding_blocks_cleanup(self):
        self.worker['process_identity'] = {'pid': 99, 'start': 'other'}
        with self.assertRaises(runtime.shared.Rejected): self.check()
    def test_pending_publication_cannot_authorize_cleanup(self):
        self.worker['actual_sequence_return']['local_pending'] = dict(stage='publish')
        with self.assertRaises(runtime.shared.Rejected): self.check()
    def test_incomplete_sequence_is_not_success(self):
        self.worker['actual_sequence_return']['completed'] = 10
        with self.assertRaises(runtime.shared.Rejected): self.check()
    def test_published_prompt_without_return_blocks_cleanup(self):
        folder = self.root/'cells/SwiftUI/input/pop.before'; folder.mkdir(); (folder/'prompt.json').write_text('{}')
        with self.assertRaises(runtime.shared.Rejected): self.check()


class MatrixStop(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup); self.root = Path(self.temp.name)
        self.plan = dict(cell='SwiftUI-automatic-B', matrix={'path':str(self.root/'matrix.json')})
        self.matrix = dict(cells=runtime.builds.CELLS)
        self.prior = self.root/'runs/SwiftUI-automatic-A/cells/SwiftUI'; self.prior.mkdir(parents=True)
        self.summary = dict(state='PASS', scenario='PASS', evidence='PASS', cleanup='PASS'); self.write()
        self.target = self.root/'runs/SwiftUI-automatic-B'; self.target.mkdir()
    def write(self): (self.prior/'summary.json').write_text(json.dumps(self.summary))
    def check(self): runtime.predecessor(self.target, self.plan, self.matrix)
    def test_complete_a_allows_only_matching_b(self): self.check()
    def test_each_incomplete_verdict_stops_matrix(self):
        for key in self.summary:
            with self.subTest(key=key):
                self.summary[key] = 'INCOMPLETE'; self.write()
                with self.assertRaises(runtime.shared.Rejected): self.check()
                self.summary[key] = 'PASS'
    def test_consumed_cell_cannot_retry(self):
        (self.target/'sessions/SwiftUI').mkdir(parents=True)
        with self.assertRaises(runtime.shared.Rejected): self.check()


class DiagnosticTiming(unittest.TestCase):
    def test_only_known_ceiling_is_removed(self):
        raw = b"before\nrequire(type(registered['payload']['duration_ns']) is int and 0 <= registered['payload']['duration_ns'] <= 2_000_000, 'registration observer exceeded callback budget')\nafter\n"
        result = runtime.render_oracle(raw)
        self.assertIn(b"is int and registered['payload']['duration_ns'] >= 0", result)
        self.assertTrue(result.startswith(b'before\n')); self.assertTrue(result.endswith(b'\nafter\n'))
    def test_unknown_or_duplicate_ceiling_is_rejected(self):
        with self.assertRaises(runtime.shared.Rejected): runtime.render_oracle(b'unknown')


if __name__ == '__main__': unittest.main()
