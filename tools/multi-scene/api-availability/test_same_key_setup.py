"""Exercise actual request publication and native evidence rejection without a device."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import same_key_setup as s
from acceptance_common import Rejected
from test_same_key import native


class Setup(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name); self.documents = self.root/'Documents'; self.documents.mkdir()
        self.clock = patch.object(s.time, 'time', return_value=100).start()
        patch('builtins.print').start()
        self.addCleanup(patch.stopall)
        self.identity = dict(run_id='run', source='source', pid=42)
        self.barrier = s.Barrier(self.root, self.documents, self.identity, 1900)
        self.admissions = []

    def release(self, request=None):
        path = request or self.barrier.operator_request
        s.physical_release.acknowledge(path, 'Released; ready')

    def ready(self, **changes):
        value = native(0)
        request = s.read(self.documents/'setup-request.json')
        value.update(phase='setup-ready', nonce=request['nonce'], request_sha256=s.sha((self.documents/'setup-request.json').read_bytes()),
                     setup_admission={}, input=[dict(scene='scene-'+o, window='window-'+o, controller='root-'+o,
                         touches=0, transitioning=False, resizing=False) for o in ['A','B']])
        value.update(changes)
        s.publish(self.documents/'setup-ready.json', value)
        return value

    def arm(self):
        self.release(); self.barrier.poll(self.admissions.append); value = self.ready()
        self.barrier.poll(self.admissions.append)
        return value

    def test_no_native_request_before_operator_release(self):
        self.barrier.poll(self.admissions.append)
        self.assertEqual(list(self.documents.iterdir()), [])
        self.assertEqual(self.admissions, [])

    def test_native_capture_precedes_one_shot_start_and_fixed_api_clock(self):
        self.release(); self.barrier.poll(self.admissions.append)
        self.assertFalse((self.documents/'setup-start.json').exists())
        self.ready()
        def admit(record):
            self.assertFalse((self.documents/'setup-start.json').exists())
            self.admissions.append(record)
        self.clock.return_value = 200
        self.barrier.poll(admit)
        self.assertEqual(self.admissions[0]['execution_deadline'], 500)
        raw = (self.documents/'setup-start.json').read_bytes()
        self.clock.return_value = 250
        self.barrier.poll(admit)
        self.assertEqual(len(self.admissions), 1)
        self.assertEqual((self.documents/'setup-start.json').read_bytes(), raw)
        self.assertEqual(self.barrier.setup_deadline, 1900)

    def test_foreign_operator_reply_rejected(self):
        self.release(); path = self.barrier.operator_request.with_name('operator-released.json')
        v=s.read(path);v['run_id']='restored';path.write_text(json.dumps(v))
        with self.assertRaises(Rejected):self.barrier.poll(self.admissions.append)
        self.assertFalse((self.documents/'setup-request.json').exists())

    def test_expired_setup_never_starts_api_clock(self):
        self.clock.return_value=1900
        with self.assertRaises(ValueError):self.barrier.poll(self.admissions.append)
        self.assertEqual(self.admissions, [])

    def test_native_foreign_run_source_pid_nonce_and_hash_rejected(self):
        self.release(); self.barrier.poll(self.admissions.append); good=self.ready()
        request=(self.documents/'setup-request.json').read_bytes()
        for key in ['run_id','source','pid','nonce','request_sha256']:
            with self.subTest(key=key),self.assertRaises(ValueError):
                s.capture(s.encoded(dict(good,**{key:'foreign'})), request,self.identity,phase='setup-ready')

    def test_batched_or_prestarted_api_work_rejected(self):
        self.release(); self.barrier.poll(self.admissions.append)
        self.ready(operations=['start-A'])
        with self.assertRaises(ValueError):self.barrier.poll(self.admissions.append)
        self.assertFalse((self.documents/'setup-start.json').exists())

    def test_failed_readiness_bytes_are_preserved(self):
        self.release();self.barrier.poll(self.admissions.append);value=self.ready()
        value['topology'][0]['state']=2
        path=self.documents/'setup-ready.json';path.write_bytes(s.encoded(value));raw=path.read_bytes()
        with self.assertRaises(ValueError):self.barrier.poll(self.admissions.append)
        self.assertEqual((self.barrier.folder/'setup-ready.json').read_bytes(),raw)
        self.assertEqual(self.admissions,[])

    def test_real_input_resizing_and_foreign_window_rejected(self):
        self.release();self.barrier.poll(self.admissions.append);good=self.ready()
        raw=(self.documents/'setup-request.json').read_bytes()
        for field,value in [('touches',1),('touches',False),('transitioning',True),('resizing',True),('window','foreign')]:
            bad=copy.deepcopy(good);bad['input'][0][field]=value
            with self.subTest(field=field,value=value),self.assertRaises(ValueError):
                s.capture(s.encoded(bad),raw,self.identity,phase='setup-ready')

    def test_callback_cannot_precede_or_change_admission(self):
        value=native(0);value['setup_admission']={}
        with self.assertRaises(ValueError):self.barrier.validate(value)
        self.arm()
        value['setup_admission']={k:self.barrier.start[k] for k in ['ready_sha256','nonce']}
        self.barrier.validate(value)
        for field in ['ready_sha256','nonce']:
            bad=copy.deepcopy(value);bad['setup_admission'][field]='restored'
            with self.assertRaises(ValueError):self.barrier.validate(bad)
        value['topology'][0]['windows'][0]['controller']='new'
        with self.assertRaises(ValueError):self.barrier.validate(value)

    def test_changed_peer_after_native_readiness_rejected(self):
        self.arm();value=native(0);value['setup_admission']={k:self.barrier.start[k] for k in ['ready_sha256','nonce']}
        value['topology'][1]['state']=2
        with self.assertRaises(ValueError):self.barrier.validate(value)

    def test_cleanup_requires_new_operator_release(self):
        self.arm()
        with patch.object(s.time,'sleep',side_effect=lambda _:setattr(self.clock,'return_value',281)):
            with self.assertRaises(ValueError):self.barrier.cleanup(400)
        self.assertFalse((self.documents/'cleanup-request.json').exists())

    def test_cleanup_requires_fresh_idle_capture_and_preserves_admission(self):
        self.arm();done=False
        def respond(_):
            nonlocal done
            path=self.barrier.folder/'operator-cleanup/request.json'
            if not path.with_name('operator-released.json').exists():self.release(path)
            request_path=self.documents/'cleanup-request.json'
            if request_path.exists() and not done:
                req=s.read(request_path);value=native(3)
                value.update(phase='cleanup-idle',nonce=req['nonce'],request_sha256=s.sha(request_path.read_bytes()),
                    setup_admission={k:self.barrier.start[k] for k in ['ready_sha256','nonce']},
                    input=[dict(scene='scene-'+o,window='window-'+o,controller='root-'+o,touches=0,
                                transitioning=False,resizing=False) for o in ['A','B']])
                s.publish(self.documents/'cleanup-idle.json',value);done=True
        with patch.object(s.time,'sleep',side_effect=respond):self.barrier.cleanup(400)
        self.assertEqual(s.read(self.barrier.folder/'cleanup-qualified.json')['state'],'PASS')


if __name__=='__main__':unittest.main()
