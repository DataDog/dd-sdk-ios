import copy
import hashlib
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import time
import unittest
from unittest.mock import patch

import capture_sequence as sequence
import swiftui_duo_runtime as runtime
import swiftui_foreground_contract as contract
import swiftui_foreground_runtime as foreground
from capture_io import encoded
from test_s2_local_contract import sample


class Inventory(unittest.TestCase):
    def setUp(self):
        self.rows = []
        for index, (key, active) in enumerate([('previous', False), ('current', True)], 1):
            event = dict(type='view', date=index, application={'id': runtime.driver.ownership.APP_ID},
                service=runtime.driver.ownership.SERVICE, source='ios', session={'id': 'session', 'type': 'user'},
                view={'id': key, 'name': key, 'url': '/'+key, 'is_active': active}, _dd={'document_version': 1})
            self.rows.append(dict(sequence=index, run_id='run', kind='rum', payload=event))
        self.owner = dict(id='current', mapper_sequence=2, session='session', name='current', path='/current')
    def check(self):
        with patch.object(runtime.driver.ownership, 'launch_identity'):
            return contract.inventory(self.rows, {'run_id': 'run'}, self.owner)
    def test_current_view_is_retained_active(self):
        self.assertTrue(self.check()['views']['current']['event']['view']['is_active'])
    def test_false_stop_and_extra_active_view_reject(self):
        for index in [0, 1]:
            with self.subTest(index=index):
                self.setUp(); self.rows[index]['payload']['view']['is_active'] = index == 0
                with self.assertRaises(runtime.shared.Rejected): self.check()
    def test_foreign_run_session_source_or_current_owner_reject(self):
        mutations = [lambda: self.rows[0].update(run_id='old'),
            lambda: self.rows[0]['payload']['session'].update(id='other'),
            lambda: self.rows[0]['payload'].update(service='other'),
            lambda: self.owner.update(id='previous'), lambda: self.owner.update(mapper_sequence=1)]
        for mutate in mutations:
            self.setUp(); mutate()
            with self.assertRaises(runtime.shared.Rejected): self.check()
    def test_missing_revision_and_duplicate_event_reject(self):
        self.rows[0]['payload']['_dd']['document_version'] = 2
        with self.assertRaises(runtime.shared.Rejected): self.check()
        self.setUp(); self.rows.append(copy.deepcopy(self.rows[1])); self.rows[-1]['sequence'] = 3
        with self.assertRaises(runtime.shared.Rejected): self.check()


class Projection(unittest.TestCase):
    def setUp(self):
        self.events, self.transitions = sample()
        self.events['views']['two']['event']['view']['is_active'] = True
    def check(self):
        return contract.projection(self.events, self.transitions,
            identity=dict(run_id='run', tracking='automatic'), active=dict(id='two'))
    def test_complete_projection_preserves_active_occurrence(self):
        result = self.check(); self.assertEqual(result['current'], 1)
        self.assertTrue(result['views'][1]['active']); self.assertFalse(result['release_acceptance'])
    def test_extra_or_foreign_callback_rejects(self):
        event = next(iter(self.events['accepted'].values()))['event']; event['context']['transition_run'] = 'old'
        with self.assertRaises(runtime.shared.Rejected): self.check()
    def test_changed_pair_counts_or_owner_reject(self):
        a = self.check()
        for key in ['current', 'views', 'actions', 'transitions']:
            b = copy.deepcopy(a)
            if key == 'current': b[key] = 0
            elif key == 'views': b[key][1]['active'] = False
            elif key == 'actions': b[key][0]['owner'] = 99
            else: b[key]['pop.cancel']['relation'] = 'fresh'
            with self.subTest(key=key), self.assertRaises(runtime.shared.Rejected): contract.paired(a, b)
    def test_unknown_native_rows_and_background_are_not_allowed(self):
        for kind in ['native_background', 'restored_run', 'new_control']:
            self.assertNotIn(kind, contract.NATIVE_KINDS)


class Scope(unittest.TestCase):
    def test_source_manifest_does_not_depend_on_foreground_import_order(self):
        script = ('import json; import swiftui_duo_runtime as r; a=r.helpers(); '
                  'import swiftui_foreground_runtime; b=r.helpers(); '
                  'assert a==b; print(json.dumps(a))')
        result = subprocess.run([sys.executable, '-B', '-c', script], cwd=Path(__file__).parent,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        names = json.loads(result.stdout)
        for name in ['swiftui_foreground_contract.py', 'swiftui_foreground_runtime.py', 'test_swiftui_foreground.py']:
            self.assertIn('tools/multi-scene/interactive-transitions/'+name, names)
    def test_default_sequence_still_requires_home(self):
        self.assertEqual(sequence.phases(dict(framework='UIKit', phase_count=11)), sequence.PHASES)
    def test_foreground_requires_explicit_swiftui_ten_phase_binding(self):
        bound = dict(framework='SwiftUI', scope=foreground.SCOPE, phase_count=10)
        self.assertEqual(sequence.phases(bound), tuple(s[0] for s in runtime.STEPS))
        for delta in [dict(framework='UIKit'), dict(scope='other'), dict(phase_count=11), dict(scope=None)]:
            with self.subTest(delta=delta), self.assertRaises(runtime.shared.Rejected): sequence.phases(dict(bound, **delta))
    def test_saved_baseline_cannot_be_repeated(self):
        self.assertEqual(foreground.CELLS, ['SwiftUI-automatic-B', 'SwiftUI-manual-A', 'SwiftUI-manual-B'])
    def test_stack_has_all_ten_effects_and_no_home_input(self):
        calls = []
        class Capture:
            deadline = 100; device = 'device'; binding = {}; evidence = []
            def ensure_root(self, *args): pass
            def perform(self, step): calls.append(step['phase'])
            def interactive(self, phase): calls.append(phase)
            def snapshot(self, phase, deadline): calls.append(phase); return {}, Path('/fixture')
            def read_display(self, *args): return '{}'
            def select_display(self, *args): return {}
        with patch.object(runtime, 'actual_closed'), patch.object(runtime.driver.human_fold, 'screen'):
            foreground.Collector.stack(Capture())
        self.assertEqual(calls, [s[0] for s in runtime.STEPS]+['foreground.end'])


class IdlePublication(unittest.TestCase):
    def test_delivered_idle_request_and_proof_have_identical_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); documents = root/'documents'; documents.mkdir()
            out = root/'out'; out.mkdir(); binding = dict(root='root', scene='scene', window='window')
            summary = dict(identity=dict(run_id='run', pid=123), documents=str(documents), binding=binding, process_identity={})
            original = runtime.atomic
            def write(path, raw, **kwargs):
                original(path, raw, **kwargs)
                if path.name != 'human-snapshot-request.json': return
                self.assertEqual(raw, (out/'cleanup-proof/request.json').read_bytes())
                request = json.loads(raw)
                payload = dict(phase='cleanup.idle', request_id=request['request_id'], request_sha256=hashlib.sha256(raw).hexdigest(),
                    transition=dict(active_transition='nil', armed=[]), topology=dict(bound_root='root', bound_scene='scene',
                        bound_window='window', root_alive=True, window_alive=True, bound_root_unchanged=True))
                prefix = encoded(dict(sequence=1, run_id='run', kind='human_snapshot', payload=payload))
                (documents/'events.jsonl').write_bytes(prefix)
                (documents/('events-checkpoint-'+request['request_id']+'.json')).write_bytes(encoded(dict(success=True,
                    run_id='run', request_id=request['request_id'], byte_count=len(prefix), sha256=hashlib.sha256(prefix).hexdigest())))
            with patch.object(runtime, 'atomic', side_effect=write), patch.object(runtime.driver.ownership, 'launch_identity'):
                runtime.cleanup_idle(out, summary, time.time()+30)
            self.assertEqual(json.loads((out/'cleanup-proof/idle.json').read_bytes())['state'], 'AUTOMATIC_INPUT_RETURNED_NATIVE_IDLE')


if __name__ == '__main__': unittest.main()
