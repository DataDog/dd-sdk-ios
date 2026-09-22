import hashlib
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
