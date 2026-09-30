"""Offline discriminators for display/readiness ordering; no native work."""
import copy
import hashlib
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import time
import unittest

import fold_readiness as fold


RUN = 'offline-fold-control'
BINDING = dict(scene='scene', window='window', root='root')
DISPLAY = dict(uniqueId='inner', active=True, primary=False, nativeSize=[2007, 2853],
               currentOrientation='rot90', pointScale=3)


def row(sequence, kind, payload):
    return dict(sequence=sequence, kind=kind, payload=payload, run_id=RUN)


def geometry(sequence, sizes=((951, 669),), scene='scene'):
    return row(sequence, 'geometry', dict(scenes=[dict(id=scene, activation=0,
        windows=[dict(width=w, height=h) for w, h in sizes])]))


def raw(rows):
    return b''.join(json.dumps(value, sort_keys=True).encode() + b'\n' for value in rows)


BASE = [row(1, 'launch', {}), row(2, 'human_window_binding', BINDING),
        row(3, 'human_snapshot', {}), geometry(4, ((466, 678),))]


class Harness:
    def __init__(self, inputs=None):
        self.now, self.snapshots, self.displays = 0, 0, 0
        self.inputs = list(inputs if inputs is not None else [raw(BASE + [geometry(5)])])
        self.files = {}
        self.gate = fold.Readiness(prefix=raw(BASE), before_sequence=3, run=RUN,
                                   binding=BINDING, display=DISPLAY)
        self.display = copy.deepcopy(DISPLAY)
        self.snapshot_row = row(6, 'human_snapshot', dict(owned_size=[951, 669]))
        self.snapshot_raw = raw(BASE + [geometry(5), self.snapshot_row])
        self.fail_snapshot = False
        self.late_snapshot = False
        self.stalled_display = False
        self.operation_deadlines = []
        self.process_changed = False

    def read(self):
        if len(self.inputs) > 1:
            return self.inputs.pop(0)
        return self.inputs[0]

    def pause(self, duration):
        self.now += duration

    def live(self, deadline):
        if self.process_changed:
            raise ValueError('process changed')

    def snapshot(self, deadline):
        self.snapshots += 1
        self.operation_deadlines.append(deadline)
        if self.fail_snapshot:
            raise ValueError('snapshot failed')
        if self.late_snapshot:
            self.now = deadline
        return self.snapshot_row, self.snapshot_raw

    def actual(self, deadline):
        self.displays += 1
        self.operation_deadlines.append(deadline)
        if self.stalled_display:
            self.now = deadline
        return self.display

    def owned(self, row, binding, display):
        fold.require(binding == BINDING and fold.matches(row['payload']['owned_size'], 3, display),
                     'owned window did not resize')

    def persist(self, name, data):
        assert name not in self.files
        self.files[name] = data

    def collect(self):
        return fold.collect(self.gate, read_events=self.read, snapshot=self.snapshot,
            actual_display=self.actual, validate_owner=self.owned, persist=self.persist,
            live=self.live, deadline=1, post_hint_seconds=.25,clock=lambda:self.now, pause=self.pause)


class ReadinessControls(unittest.TestCase):
    def test_waits_for_new_geometry_then_captures_once(self):
        harness = Harness([raw(BASE), raw(BASE + [geometry(5)])])
        self.assertEqual(harness.collect(), harness.snapshot_row)
        self.assertEqual((harness.snapshots, harness.displays), (1, 1))
        self.assertEqual(harness.files['geometry-events.jsonl'], raw(BASE + [geometry(5)]))
        self.assertFalse(json.loads(harness.files['owned-readiness.json'])['scenario_credit'])

    def test_unchanged_geometry_expires_without_capture(self):
        harness = Harness([raw(BASE)])
        with self.assertRaisesRegex(ValueError, 'GEOMETRY_READINESS_DEADLINE_EXPIRED'):
            harness.collect()
        self.assertEqual((harness.snapshots, harness.displays), (0, 0))
        self.assertEqual(json.loads(harness.files['readiness-stop.json'])['deadline'], 1)

    def test_old_geometry_and_old_matches_cannot_supply_readiness(self):
        base = BASE[:3] + [geometry(4)]
        gate = fold.Readiness(prefix=raw(base), before_sequence=3, run=RUN,
                              binding=BINDING, display=DISPLAY)
        self.assertIsNone(gate.observe(raw(base)))
        self.assertIsNone(gate.observe(raw(base + [geometry(5), geometry(6, ((466, 678),))])))

    def test_partial_line_is_never_read_as_complete_geometry(self):
        harness = Harness([raw(BASE) + raw([geometry(5)])[:-1]])
        with self.assertRaisesRegex(ValueError, 'GEOMETRY_READINESS_DEADLINE_EXPIRED'):
            harness.collect()
        self.assertEqual(harness.snapshots, 0)
        self.assertEqual(harness.files['stopped-observed-events.jsonl'], harness.inputs[0])

    def test_replaced_foreign_gapped_and_duplicate_bindings_reject(self):
        mutations = [raw(BASE).replace(b'"scene"', b'"other"'),
                     raw(BASE + [dict(geometry(5), run_id='restored')]),
                     raw(BASE + [geometry(6)]),
                     raw(BASE + [row(5, 'human_window_binding', BINDING)])]
        for changed in mutations:
            harness = Harness([changed])
            with self.subTest(raw=changed[-100:]), self.assertRaises(ValueError):
                harness.collect()
            self.assertEqual(harness.snapshots, 0)
            self.assertEqual(harness.files['stopped-observed-events.jsonl'], changed)

    def test_foreign_scene_background_and_input_reject(self):
        mutations = [geometry(5, scene='foreign'), row(5, 'native_background', {}),
                     row(5, 'native_input', {}), row(5, 'human_callback', {}),
                     row(5, 'human_scroll_begin', {}), row(5, 'human_failure', {})]
        for changed in mutations:
            harness = Harness([raw(BASE + [changed])])
            with self.subTest(kind=changed['kind']), self.assertRaises(ValueError):
                harness.collect()
            self.assertEqual(harness.snapshots, 0)

    def test_auxiliary_match_cannot_qualify_owned_window(self):
        harness = Harness()
        harness.snapshot_row['payload']['owned_size'] = [466, 678]
        harness.snapshot_raw = raw(BASE + [geometry(5), harness.snapshot_row])
        with self.assertRaisesRegex(ValueError, 'owned window did not resize'):
            harness.collect()
        self.assertEqual(harness.snapshots, 1)
        self.assertNotIn('owned-readiness.json', harness.files)

    def test_roundoff_passes_but_size_scale_and_nonfinite_mismatches_do_not(self):
        self.assertTrue(fold.matches([951.000001, 669], 3, DISPLAY))
        self.assertTrue(fold.matches([951, 669], 3.00000001, DISPLAY))
        self.assertFalse(fold.matches([952, 669], 3, DISPLAY))
        self.assertFalse(fold.matches([951, 669], 2, DISPLAY))
        for value in (float('nan'), float('inf'), 0, True):
            with self.subTest(value=value), self.assertRaises(ValueError):
                fold.matches([value, 669], 3, DISPLAY)

    def test_changed_display_rejects_after_the_single_snapshot(self):
        for key, value in [('uniqueId','outer'), ('nativeSize',[1398,2034]),
                           ('currentOrientation','rot0'), ('pointScale',2), ('primary',True)]:
            harness = Harness(); harness.display[key] = value
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'display changed'):
                harness.collect()
            self.assertEqual((harness.snapshots,harness.displays),(1,1))

    def test_stale_snapshot_and_rewritten_post_snapshot_prefix_reject(self):
        harness = Harness(); harness.snapshot_row = BASE[2]
        with self.assertRaisesRegex(ValueError, 'snapshot preceded'):
            harness.collect()
        harness = Harness(); harness.snapshot_raw = harness.snapshot_raw.replace(b'"scene"', b'"foreign"')
        with self.assertRaisesRegex(ValueError, 'prefix replaced'):
            harness.collect()

    def test_no_retry_after_snapshot_failure_or_late_completion(self):
        harness = Harness(); harness.fail_snapshot = True
        with self.assertRaisesRegex(ValueError, 'snapshot failed'):
            harness.collect()
        self.assertEqual((harness.snapshots,harness.displays),(1,0))
        harness = Harness(); harness.late_snapshot = True
        with self.assertRaisesRegex(ValueError, 'OWNED_SNAPSHOT_DEADLINE_EXPIRED'):
            harness.collect()
        self.assertEqual((harness.snapshots,harness.displays),(1,0))

    def test_changed_process_and_consumed_readiness_reject(self):
        harness = Harness(); harness.process_changed = True
        with self.assertRaisesRegex(ValueError, 'process changed'):
            harness.collect()
        self.assertEqual(harness.snapshots,0)
        harness = Harness(); harness.collect()
        with self.assertRaisesRegex(ValueError, 'already consumed'):
            harness.gate.observe(harness.snapshot_raw)

    def test_stalled_display_shares_snapshot_budget_and_does_not_retry(self):
        harness=Harness();harness.stalled_display=True
        with self.assertRaisesRegex(ValueError,'POST_SNAPSHOT_DISPLAY_DEADLINE_EXPIRED'):
            harness.collect()
        self.assertEqual((harness.snapshots,harness.displays),(1,1))
        self.assertEqual(harness.operation_deadlines,[.25,.25])
        stop=json.loads(harness.files['readiness-stop.json'])
        self.assertEqual((stop['deadline'],stop['original_deadline']),(.25,1))
        self.assertNotIn('owned-readiness.json',harness.files)


class SavedDiagnostic(unittest.TestCase):
    def test_preserved_native_tail_demonstrates_readiness_but_cannot_repair_attempt(self):
        repo = Path(__file__).resolve().parents[3]
        owner = json.loads((repo/'DatadogRUM/MultiSceneSupport/Results/S2-swiftui-ancestry-20260930.json').read_text())
        result_path = Path(owner['result']['path'])
        self.assertEqual(hashlib.sha256(result_path.read_bytes()).hexdigest(), owner['result']['sha256'])
        result = json.loads(result_path.read_bytes())
        folder = result_path.parent
        def artifact(name):
            value = (folder/name).read_bytes()
            self.assertEqual(hashlib.sha256(value).hexdigest(), result['artifacts'][name])
            return value
        original = artifact('native-preserved/events.jsonl')
        lines = original.splitlines(keepends=True)
        rows = [json.loads(line) for line in lines]
        binding = next(r['payload'] for r in rows if r['kind']=='human_window_binding')
        display = next(d for d in json.loads(artifact('open-display-30.raw.json'))['result']['displays'] if d['active'])
        gate = fold.Readiness(prefix=b''.join(lines[:18]),before_sequence=17,
                              run=result['run_id'],binding=binding,display=display)
        self.assertIsNone(gate.observe(b''.join(lines[:46])))
        self.assertEqual(gate.observe(b''.join(lines[:47]))['sequence'],47)
        self.assertEqual(gate.observe(b''.join(lines[:50]))['sequence'],50)
        early = next(r for r in rows if r['sequence']==31)
        scene = early['payload']['topology']['scene_inventory'][0]
        owned = next(w for w in scene['windows'] if w['owned'])
        self.assertFalse(fold.matches(owned['bounds'][2:],scene['screen_scale'],display))
        self.assertEqual(result['state'],'INVALID_DIAGNOSTIC')
        self.assertEqual(result['cleanup'],'PASS')

    def test_driver_consumes_hint_then_checks_real_owner_validator_and_actual_display(self):
        import human_ancestry_native as native
        repo = Path(__file__).resolve().parents[3]
        owner = json.loads((repo/'DatadogRUM/MultiSceneSupport/Results/S2-swiftui-ancestry-20260930.json').read_text())
        root = Path(owner['root']); module, _, _ = native.context(root)
        folder = root/'native'
        lines = (folder/'native-preserved/events.jsonl').read_bytes().splitlines(keepends=True)
        rows = [json.loads(line) for line in lines]
        closed = rows[16]
        binding = next(r['payload'] for r in rows if r['kind']=='human_window_binding')
        observed = json.loads((folder/'open-display-30.raw.json').read_bytes())
        display = next(d for d in observed['result']['displays'] if d['active'])
        arguments=observed['info']['arguments']; identifier=arguments[arguments.index('--device')+1]
        for resized in (True, False):
            with self.subTest(owned_resized=resized), tempfile.TemporaryDirectory() as temporary:
                output = Path(temporary); documents=output/'documents'; documents.mkdir()
                # Deliberate offline snapshot mutation, never native evidence.
                snapshot = copy.deepcopy(closed); snapshot['sequence']=48
                if resized:
                    scene = snapshot['payload']['topology']['scene_inventory'][0]
                    scene['screen_bounds'][2:]=[951,669]
                    next(w for w in scene['windows'] if w['owned'])['bounds'][2:]=[951,669]
                hint = b''.join(lines[:47])
                (documents/'events.jsonl').write_bytes(hint)
                capture = SimpleNamespace(prefix=b''.join(lines[:18]),run=closed['run_id'],
                    binding=binding,documents=documents,live=lambda deadline:None)
                calls=[]
                def take_snapshot(name,phase,deadline):
                    calls.append(('snapshot',name,phase));capture.prefix=hint+raw([snapshot])
                    return snapshot,[]
                capture.snapshot=take_snapshot
                def actual(identifier,output,name,deadline):
                    calls.append(('actual-display',name))
                    (output/(name+'.json')).write_bytes(json.dumps(observed).encode())
                    return json.dumps(observed).encode()
                joined = SimpleNamespace(transport=SimpleNamespace(display=actual),displays=module.displays,
                                         native_ownership=module.native_ownership,oracle=module.oracle)
                if resized:
                    self.assertEqual(native.opened_snapshot(joined,capture,output,identifier,closed,display,
                        time.time()+5,2),snapshot)
                else:
                    with self.assertRaisesRegex(ValueError,'native geometry differs'):
                        native.opened_snapshot(joined,capture,output,identifier,closed,display,time.time()+5,2)
                self.assertEqual(calls,[('snapshot','opened','diagnostic.opened'),('actual-display','after-snapshot-display')])


if __name__ == '__main__':
    unittest.main()
