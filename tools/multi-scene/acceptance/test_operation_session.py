"""Coordinator fault injection. Component doubles grant no native or gate credit."""
from pathlib import Path
import tempfile
import time
import types
import unittest
from unittest.mock import patch

import operation_session as s
import operation_transport as t


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name).resolve();self.calls=[];self.fail_at=None;self.stop_fails=False
        raw=types.SimpleNamespace(identifier='device',output=self.root/'io',sequence=0,groups=[])
        self.remote=s.media.ExecutionDevice(raw,execution_until=time.time()+300,deadline=time.time()+900)
        out=self.root/'cell';out.mkdir(); host_folder=out/'host-setup';host_folder.mkdir()
        self.channel=types.SimpleNamespace(remote=self.remote,deadline=self.remote.deadline,output=out,
            bundle='task.bundle',identity={'runID':'test-run','setupProfile':{'scenario':'test-scenario'}})
        self.host=types.SimpleNamespace(channel=self.channel,remote=self.remote,folder=host_folder,
            identity=self.channel.identity,collect=self.collect,publish=lambda:self.call('publish'),used=False)
        self.operator=types.SimpleNamespace(channel=self.channel,present=self.present,
            acknowledgement=lambda:(self.call('ack') or b'actual-page-ack'))
        self.movie=types.SimpleNamespace(remote=self.remote,process=None,reaped=False,start=self.start,
            finish=self.finish,running=lambda:self.call('recording-live'),quiescent=True,
            checkpoint=lambda:self.call('recorder-checkpoint'),collect=self.collect_movie,restore=self.restore_movie)
        self.capture=types.SimpleNamespace(host=self.host,movie=self.movie,nonce='nonce',source_sha256='a'*64,
            binary_sha256='b'*64,start_raw=b'start',bindings={'A':b'owner'},start_image={},
            start_barrier=lambda:self.call('start-barrier'),review_start=lambda *_:None,
            live=lambda:None,poll=self.poll,pull=lambda name:(self.call('seal') or b'seal'),
            screenshot=lambda phase:(self.call('image-'+phase) or {}),decode=lambda *_:(self.call('decode-movie') or {}))
        self.patches=[]
        def patched(target,**kw):
            item=patch(target,**kw);item.start();self.addCleanup(item.stop)
        patched('operation_session.operator_health',side_effect=lambda *a:(self.call('page') or {'pid':12}))
        patched('operation_session.display.DisplayProofBridge',side_effect=self.bridge)
        patched('operation_session.completion.Completion',side_effect=lambda *a,**kw:(self.call('completion-init') or self.host))
        patched('operation_session.recorder_contract.Recorder',side_effect=lambda *_:types.SimpleNamespace(collect=lambda:self.call('collect-local')))
        patched('operation_session.display_join',side_effect=lambda *_:(self.call('join-display') or {'state':'DISPLAY_NATIVE_JOINED'}))
        patched('operation_session.cleanup_expectations',side_effect=lambda *_:(self.call('expectations') or (b'native-original',{'state':'PASS'})))
        patched('operation_session.cleanup.Cleanup',side_effect=self.cleaner)
        patched('operation_session.backend.Backend',side_effect=self.backend)
        self.session=s.Session(self.host,self.operator,self.capture,backend_deadline=self.remote.deadline,
            maximum_attempts=2,poll_seconds=1,wait=lambda:None)

    def call(self,name):
        self.calls.append(name)
        if self.fail_at==name:raise ValueError('injected '+name)

    def collect(self,ack,review):
        self.assertEqual(ack,b'actual-page-ack')
        (self.host.folder/'process-before-response.json').write_bytes(b'original-observed-process')
        self.call('collect-host')

    def present(self,path):self.call('prompt-cleanup' if 'host-cleanup' in str(path) else 'prompt-setup')

    def start(self):
        self.movie.process=object();self.movie.quiescent=False;self.call('start-movie')

    def finish(self,*,accept):
        self.call('finish-movie' if accept else 'abort-movie')
        if self.stop_fails:raise ValueError('child still running')
        self.movie.reaped=True;self.movie.quiescent=True
        return self.root/'movie.mp4'

    def collect_movie(self,capture):
        return capture.decode(self.finish(accept=True),'MOVIE','MOVIE')

    def restore_movie(self):
        self.call('restore-movie')
        if not self.movie.quiescent:self.finish(accept=False)

    def poll(self,name):self.call('poll-'+name);return name.encode()

    def bridge(self,*args,**kwargs):
        self.call('bridge-init')
        return types.SimpleNamespace(start=lambda *a:self.call('proof-start'),run=lambda *a:self.call('proof-run'),
            final=lambda *a:self.call('proof-final'))

    def cleaner(self,host,**kw):
        self.assertEqual(kw['original_native_raw'],b'native-original')
        self.assertEqual(kw['original_terminal'],{'state':'PASS'})
        self.call('cleanup-init')
        return types.SimpleNamespace(folder=self.channel.output/'host-cleanup',
            run=lambda ack:(self.call('cleanup-remove') or {'state':'TASK_APP_REMOVED'}))

    def backend(self,*args,**kwargs):
        self.assertEqual(kwargs['deadline'],self.session.backend_deadline)
        self.call('backend-init')
        return types.SimpleNamespace(collect=lambda:(self.call('backend-collect') or {'state':'BACKEND_OWNERSHIP_JOINED'}))

    def run_session(self):
        result=self.session.run()
        self.assertFalse(result['releaseAcceptance']);self.assertEqual(result['gatesClosed'],[])
        self.assertFalse(result['sdkRegression']);return result

    def test_complete_order_has_one_completion_and_cleanup_before_backend(self):
        result=self.run_session();self.assertEqual(result['state'],'EVIDENCE_COMPLETE')
        phases=['start-barrier','prompt-setup','start-movie','collect-host','proof-start','poll-display-RUN.json',
            'image-RUN','proof-run','recorder-checkpoint','publish','poll-display-FINAL.json','seal','image-FINAL','finish-movie',
            'decode-movie','proof-final','completion-init','collect-local','join-display','prompt-cleanup',
            'cleanup-remove','backend-collect']
        offsets=[self.calls.index(p) for p in phases];self.assertEqual(offsets,sorted(offsets))
        self.assertEqual(self.calls.count('collect-local'),1)
        self.assertTrue(self.remote.cleanup_started)
        with self.assertRaises(ValueError):self.session.run()

    def test_start_barrier_failure_has_no_capture_or_teardown(self):
        self.fail_at='start-barrier';result=self.run_session()
        self.assertEqual(result['verdicts']['cleanup'],'BLOCKED')
        for step in ['prompt-setup','start-movie','collect-host','cleanup-remove','backend-init']:self.assertNotIn(step,self.calls)

    def test_failed_release_leaves_app_untouched(self):
        self.fail_at='ack';result=self.run_session()
        self.assertEqual(result['state'],'INVALID');self.assertNotIn('start-movie',self.calls)
        self.assertNotIn('cleanup-init',self.calls)

    def test_capture_failure_aborts_recorder_and_uses_separate_release_cleanup(self):
        self.fail_at='collect-host';result=self.run_session()
        self.assertLess(self.calls.index('abort-movie'),self.calls.index('prompt-cleanup'))
        self.assertIn('cleanup-remove',self.calls);self.assertNotIn('backend-init',self.calls)
        self.assertEqual(result['verdicts']['scenario'],'INVALID');self.assertEqual(result['verdicts']['cleanup'],'PASS')

    def test_run_publication_failure_never_enters_operations_collection(self):
        self.fail_at='proof-run';result=self.run_session()
        self.assertNotIn('publish',self.calls);self.assertNotIn('collect-local',self.calls)
        self.assertEqual(result['verdicts']['cleanup'],'PASS')

    def test_final_capture_failure_still_reaps_and_does_not_publish_final(self):
        self.fail_at='image-FINAL';result=self.run_session()
        self.assertIn('abort-movie',self.calls);self.assertNotIn('proof-final',self.calls)
        self.assertEqual(result['verdicts']['scenario'],'INVALID')

    def test_final_decode_failure_cannot_start_local_collection(self):
        self.fail_at='decode-movie';result=self.run_session()
        self.assertNotIn('collect-local',self.calls);self.assertEqual(result['verdicts']['cleanup'],'PASS')

    def test_unreaped_movie_blocks_all_teardown(self):
        self.fail_at='image-FINAL';self.stop_fails=True;result=self.run_session()
        self.assertEqual(result['verdicts']['cleanup'],'BLOCKED');self.assertNotIn('cleanup-init',self.calls)

    def test_changed_native_consumer_keeps_capture_invalid(self):
        self.fail_at='join-display';result=self.run_session()
        self.assertEqual(result['verdicts']['scenario'],'INVALID');self.assertNotIn('backend-init',self.calls)
        self.assertEqual(result['verdicts']['cleanup'],'PASS')

    def test_failed_cleanup_cannot_be_rescued_by_complete_backend(self):
        self.fail_at='cleanup-remove';result=self.run_session()
        self.assertEqual(result['state'],'INVALID');self.assertEqual(result['verdicts']['cleanup'],'BLOCKED')
        self.assertEqual(result['verdicts']['backend'],'PASS');self.assertEqual(result['verdicts']['scenario'],'PASS')

    def test_failed_backend_preserves_successful_capture_and_cleanup(self):
        self.fail_at='backend-collect';result=self.run_session()
        self.assertEqual(result['state'],'INVALID')
        self.assertEqual(result['verdicts'],dict(scenario='PASS',display='PASS',backend='INVALID',cleanup='PASS',recorder_restoration='PASS'))

    def test_foreign_components_reject_before_session_publication(self):
        self.capture.host=object()
        with self.assertRaisesRegex(ValueError,'original channel'):
            s.Session(self.host,self.operator,self.capture,backend_deadline=self.remote.deadline,maximum_attempts=1,poll_seconds=1)

    def test_mutated_definition_cannot_trigger_input_or_work(self):
        (self.session.folder/'definition.json').write_bytes(b'{}');result=self.run_session()
        self.assertNotIn('prompt-setup',self.calls);self.assertEqual(result['state'],'INVALID')

    def test_operator_replacement_blocks_cleanup_even_with_saved_scenario(self):
        original=s.operator_health
        def changed(op,folder):
            result=original(op,folder)
            if folder.name=='page-cleanup':result={'pid':99}
            return result
        with patch.object(s,'operator_health',side_effect=changed):result=self.run_session()
        self.assertNotIn('cleanup-remove',self.calls);self.assertEqual(result['verdicts']['cleanup'],'BLOCKED')
        self.assertEqual(result['verdicts']['scenario'],'PASS')

    def test_failed_recorder_checkpoint_never_dispatches_operations(self):
        self.fail_at='recorder-checkpoint';result=self.run_session()
        self.assertNotIn('publish',self.calls);self.assertEqual(result['verdicts']['scenario'],'INVALID')
        self.assertEqual(result['verdicts']['cleanup'],'PASS')

    def test_restoration_failure_blocks_teardown_and_keeps_other_verdicts(self):
        self.fail_at='restore-movie';result=self.run_session()
        self.assertNotIn('cleanup-remove',self.calls)
        self.assertEqual(result['verdicts']['recorder_restoration'],'BLOCKED')
        self.assertFalse(self.remote.cleanup_started)
        self.assertEqual(result['verdicts']['cleanup'],'BLOCKED')
        self.assertEqual(result['verdicts']['scenario'],'PASS');self.assertEqual(result['state'],'INVALID')

if __name__=='__main__':unittest.main()
