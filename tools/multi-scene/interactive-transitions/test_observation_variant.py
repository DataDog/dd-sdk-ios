import hashlib
import json
from pathlib import Path
import unittest
import observation_variant as v

BASE=Path(__file__).resolve().parents[1]/'automatic-coverage'

class CopiedObservation(unittest.TestCase):
    def test_only_generated_observer_gets_transition_snapshot(self):
        path=BASE/'HumanObservation.swift';original=path.read_bytes()
        result=v.human(original,hashlib.sha256(original).hexdigest()).decode()
        self.assertIn('prepare(requestID: requestID, phase: phase)',result)
        self.assertIn('"transition": TransitionObservation.shared.snapshot()',result)
        self.assertEqual(path.read_bytes(),original)
    def test_cached_metadata_keeps_every_live_topology_read(self):
        raw=(BASE/'HumanObservation.swift').read_bytes()
        actual=v.human(raw,hashlib.sha256(raw).hexdigest()).decode()
        def topology(text):return text[text.index('    func topology('):text.index('    func scrollSnapshot(')]
        original=topology(raw.decode());modified=topology(actual)
        pairs=[('self.bundlePath(for: type(of: $0))','Bundle(for: type(of: $0)).bundleURL.path'),
               ('self.bundlePath(for: type(of: window))','Bundle(for: type(of: window)).bundleURL.path')]
        for name in ['UIWindow','UINavigationController','UISplitViewController','UIHostingController<EmptyView>','UIViewController']:
            pairs.append(('bundlePath(for: '+name+'.self)','Bundle(for: '+name+'.self).bundleURL.path'))
        for before,after in pairs:modified=modified.replace(before,after)
        self.assertEqual(modified,original)
        self.assertIn('ObjectIdentifier(objectType)',actual)
        self.assertIn('if bundlePaths.count < 128',actual)
        self.assertEqual((BASE/'HumanObservation.swift').read_bytes(),raw)
    def test_unrecognized_metadata_lookup_cannot_be_silently_omitted(self):
        raw=(BASE/'HumanObservation.swift').read_bytes().replace(b'Bundle(for: UIWindow.self)',b'Bundle(for: NewWindow.self)')
        with self.assertRaises(ValueError):v.human(raw,hashlib.sha256(raw).hexdigest())
    def test_callback_cost_is_retained_as_diagnostic(self):
        import human_contract
        rows=[dict(sequence=1,run_id='run',kind='launch',payload={}),
              dict(sequence=2,run_id='run',kind='human_callback',payload=dict(request_id='request')),
              dict(sequence=3,run_id='run',kind='human_observer_cost',payload=dict(
                  event_sequence=2,operation='callback',request_id='request',duration_ns=2686500))]
        raw=b''.join((json.dumps(row)+'\n').encode() for row in rows)
        self.assertEqual(human_contract.rows(raw,'run'),rows)
    def test_wrong_frozen_source_rejected(self):
        for function,path in [(v.human,BASE/'HumanObservation.swift'),(v.observation,BASE/'Fixture/Observation.swift')]:
            with self.assertRaises(ValueError):function(path.read_bytes(),'wrong')
    def test_mapper_boundary_uses_the_writer_lock(self):
        path=BASE/'Fixture/Observation.swift';original=path.read_bytes()
        result=v.observation(original,hashlib.sha256(original).hexdigest()).decode()
        critical=result[result.index('func append('):result.index('func checkpoint(')]
        self.assertLess(critical.index('lock.lock()'),critical.index('latestViews[id] ='))
        self.assertLess(critical.index('payload["mapper_views"]'),critical.index('let row:'))
        self.assertNotIn('customEndpoint',result)
        self.assertIn('Settings.tracking == "automatic"',result)
        self.assertIn('close(reason: "background")',result)
        self.assertEqual(path.read_bytes(),original)

if __name__=='__main__':unittest.main()
