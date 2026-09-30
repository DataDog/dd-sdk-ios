"""Request and owner discriminators for the one automatic ancestry diagnostic."""
import copy
import hashlib
import json
from pathlib import Path
import unittest

import human_ancestry_native as native


class SnapshotJoin(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path('/Users/valentin.pertuisot/work/dd-sdk-ios-extractions/evidence/s2-swiftui-ancestry-j7r7e8fi')
        cls.module, definition, _ = native.context(cls.root)
        prior = native.build.bound(definition['source_attempt'])
        folder = Path(prior['separate_restoration']['result']['path']).parent
        cls.raw = (folder/'events.jsonl').read_bytes()
        cls.checkpoint = json.loads((folder/'checkpoint.json').read_bytes())
        cls.request = (folder/'published-request.json').read_bytes()
        cls.run_id = json.loads(cls.request)['run_id']
        cls.binding = native.validate_snapshot(cls.module,cls.raw,cls.checkpoint,cls.request,cls.run_id)[1]

    def test_saved_failure_joins_without_receiving_scenario_credit(self):
        row, binding, _ = native.validate_snapshot(self.module,self.raw,self.checkpoint,self.request,self.run_id)
        self.assertEqual(row['sequence'],186)
        self.assertEqual(binding,self.binding)
        self.assertEqual(row['payload']['topology']['accessibility'][0]['capture_error'],
                         'public accessibility view has missing owned ancestry')

    def test_replaced_request_phase_hash_and_run_reject(self):
        for key,value in [('phase','diagnostic.opened'),('run_id','foreign'),('request_id','foreign')]:
            request=json.loads(self.request);request[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):
                native.validate_snapshot(self.module,self.raw,self.checkpoint,json.dumps(request).encode(),self.run_id)

    def test_forged_checkpoint_and_missing_prefix_reject(self):
        for raw,checkpoint in [(self.raw[:-100],self.checkpoint),
                               (self.raw,dict(self.checkpoint,sha256='0'*64)),
                               (self.raw,dict(self.checkpoint,request_id='foreign'))]:
            with self.subTest(checkpoint=checkpoint),self.assertRaises(ValueError):
                native.validate_snapshot(self.module,raw,checkpoint,self.request,self.run_id)

    def test_validly_hashed_regressed_cleanup_checkpoint_rejects(self):
        native.validate_snapshot(self.module,self.raw,self.checkpoint,self.request,self.run_id,after_sequence=185)
        for previous in (186,187):
            with self.subTest(previous=previous),self.assertRaisesRegex(ValueError,'did not advance'):
                native.validate_snapshot(self.module,self.raw,self.checkpoint,self.request,self.run_id,after_sequence=previous)

    def test_rebound_owner_rejects_even_with_valid_writer_prefix(self):
        for key in ('root','window','scene'):
            binding=dict(self.binding,**{key:'foreign'})
            with self.subTest(key=key),self.assertRaises(ValueError):
                native.validate_snapshot(self.module,self.raw,self.checkpoint,self.request,self.run_id,binding)

    def test_actual_display_tolerates_roundoff_but_rejects_other_size(self):
        row,binding,_=native.validate_snapshot(self.module,self.raw,self.checkpoint,self.request,self.run_id)
        scene=row['payload']['topology']['scene_inventory'][0]
        display=dict(nativeSize=[n*scene['screen_scale'] for n in scene['screen_bounds'][2:]],
                     pointScale=scene['screen_scale'],currentOrientation='rot0')
        native.screen(self.module,row,binding,display)
        changed=copy.deepcopy(row)
        next(w for w in changed['payload']['topology']['scene_inventory'][0]['windows'] if w['owned'])['bounds'][2]+=.000001
        native.screen(self.module,changed,binding,display)
        display['nativeSize'][0]+=100
        with self.assertRaises(ValueError):native.screen(self.module,row,binding,display)


if __name__=='__main__':unittest.main()
