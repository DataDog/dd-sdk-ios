"""Host subprocess and fabricated CoreDevice controls. No native acceptance."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import types
import unittest
import uuid
from unittest.mock import patch

import operation_media as m
import operation_transport as t

POPEN = subprocess.Popen
CHILD = """
import json,signal,sys,time
from pathlib import Path
folder=Path(sys.argv[1]); args=json.loads(sys.argv[2]); mode=sys.argv[3]
def finish(*_):
    if mode=='ignore': return
    value={'info':{'commandType':'devicectl.device.capture.screen-record','outcome':'success','arguments':['devicectl']+args}}
    if mode=='foreign': value['info']['arguments'][4]='foreign-device'
    (folder/'response.json').write_text(json.dumps(value))
    (folder/'screen.mp4').write_bytes(b'host lifetime fixture only')
    sys.exit(0)
signal.signal(signal.SIGINT,finish)
(folder/'child-ready').write_text('ready')
if mode=='early': sys.exit(0)
while True: time.sleep(.02)
"""


class MediaTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name).resolve()
        self.calls=[]
        self.raw=types.SimpleNamespace(identifier='physical-device',output=self.root/'device',sequence=0,groups=[])
        self.raw.command=lambda *a,**kw:self.calls.append((a,kw))
        self.raw.pull=lambda *a,**kw:self.calls.append((a,kw))
        self.raw.push=lambda *a,**kw:self.calls.append((a,kw))
        self.raw.quiescent=lambda *a:self.calls.append(a)
        self.now=time.time(); self.remote=m.ExecutionDevice(self.raw,execution_until=self.now+30,deadline=self.now+60)
        self.mode='ok'; self.movie=None
        self.script=self.root/'child.py';self.script.write_text(CHILD)
        self.addCleanup(self.stop_child)

    def stop_child(self):
        if self.movie and self.movie.process and self.movie.process.poll() is None:
            os.killpg(self.movie.process.pid,9);self.movie.process.wait(timeout=2)
        if self.movie and self.movie.watchdog:self.movie.watchdog.cancel()

    def movie_start(self):
        self.movie=m.Movie(self.remote,self.root/'movie',record_until=time.time()+4,
            stop_until=time.time()+7,environment=os.environ)
        def child(argv,**kwargs):
            self.assertEqual(argv[:5],['xcrun','devicectl','device','capture','screen-record'])
            self.assertTrue(kwargs['start_new_session'])
            return POPEN([sys.executable,str(self.script),str(self.movie.folder),json.dumps(self.movie.args),self.mode],**kwargs)
        with patch.object(m.subprocess,'Popen',side_effect=child):self.movie.start()
        end=time.time()+2
        while not (self.movie.folder/'child-ready').exists() and time.time()<end:time.sleep(.01)
        self.assertTrue((self.movie.folder/'child-ready').exists())
        return self.movie

    def test_execution_device_caps_io_and_reserves_original_cleanup_cutoff(self):
        self.remote.command(['device','info','details'],'a',self.remote.deadline)
        self.assertEqual(self.calls[-1][0][-1],self.remote.execution_until)
        self.remote.begin_cleanup()
        self.remote.command(['device','info','details'],'b',self.remote.deadline)
        self.assertEqual(self.calls[-1][0][-1],self.remote.deadline)
        with self.assertRaises(ValueError):self.remote.begin_cleanup()

    def test_changed_device_or_deadline_never_reaches_native_io(self):
        for change in ['device','deadline']:
            with self.subTest(change=change):
                if change=='device':self.raw.identifier='foreign'
                else:self.remote.deadline+=1
                with self.assertRaises(ValueError):self.remote.command([], 'x', self.now+60)
        self.assertEqual(self.calls,[])

    def test_expired_execution_does_not_extend_to_cleanup_without_transition(self):
        with patch.object(m.time,'time',return_value=self.remote.execution_until):
            with self.assertRaises(ValueError):self.remote.command([], 'x', self.remote.deadline)
            self.remote.begin_cleanup();self.remote.command([], 'cleanup', self.remote.deadline)
        self.assertEqual(len(self.calls),1)

    def test_owned_recorder_sigint_finalizes_and_reaps_with_actual_response(self):
        movie=self.movie_start(); path=movie.finish(accept=True)
        self.assertEqual(path.read_bytes(),b'host lifetime fixture only')
        result=t.load((movie.folder/'process-finished.json').read_bytes())
        self.assertTrue(result['reaped']);self.assertFalse(result['captureAccepted'])
        self.assertEqual(result['remaining'],[]);self.assertEqual(result['signals'],['SIGINT'])
        self.assertIn(movie.process.pid,self.remote.groups)
        with self.assertRaises(ValueError):movie.finish(accept=True)
        with self.assertRaises(ValueError):movie.start()

    def test_abort_reaps_without_publishing_accepted_media(self):
        movie=self.movie_start();movie.finish(accept=False)
        self.assertTrue(movie.reaped);self.assertFalse((movie.folder/'result.json').exists())

    def test_foreign_returned_command_is_retained_and_reaped_before_rejection(self):
        self.mode='foreign';movie=self.movie_start()
        with self.assertRaisesRegex(ValueError,'command differs'):movie.finish(accept=True)
        self.assertTrue(movie.reaped);self.assertTrue(movie.response.is_file())
        self.assertFalse((movie.folder/'result.json').exists())

    def test_early_exit_cannot_substitute_for_final_capture(self):
        self.mode='early';movie=self.movie_start();movie.process.wait(timeout=2)
        with self.assertRaises(ValueError):movie.running()
        with self.assertRaisesRegex(ValueError,'before FINAL'):movie.finish(accept=True)
        self.assertTrue(movie.reaped)

    def test_ignored_interrupt_is_forced_reaped_and_not_accepted(self):
        self.mode='ignore';movie=self.movie_start()
        with self.assertRaisesRegex(ValueError,'recording failed'):movie.finish(accept=True)
        result=t.load((movie.folder/'process-finished.json').read_bytes())
        self.assertTrue(result['forced']);self.assertTrue(result['reaped'])
        self.assertEqual(result['signals'],['SIGINT','SIGKILL'])

    def test_definition_mutation_or_cleanup_prevents_capture_checks(self):
        movie=self.movie_start();(movie.folder/'definition.json').write_bytes(b'{}')
        with self.assertRaises(ValueError):movie.running()
        movie.finish(accept=False)

    def test_recording_cutoff_is_never_renewed(self):
        movie=self.movie_start()
        with patch.object(m.time,'time',return_value=movie.record_until):
            with self.assertRaises(ValueError):movie.running()
        movie.finish(accept=False)

    def test_watchdog_stops_only_owned_child_and_prevents_acceptance(self):
        movie=self.movie_start();movie.expire();movie.process.wait(timeout=2)
        with self.assertRaises(ValueError):movie.finish(accept=True)
        self.assertTrue(movie.expired);self.assertTrue(movie.reaped)

    def test_actual_command_identity_rejects_changed_duplicate_and_missing_arguments(self):
        args=['device','capture','screen-record','--device','physical-device','--destination','/a.mp4']
        value=dict(info=dict(commandType='devicectl.device.capture.screen-record',outcome='success',arguments=['devicectl',*args]))
        m.command_identity(value,args)
        for actual in [args[:-1],args+['--device','other'],['different',*args],args[:-1]+['/old.mp4']]:
            value['info']['arguments']=actual
            with self.assertRaises(ValueError):m.command_identity(value,args)

class ObservationTests(unittest.TestCase):
    def setUp(self):
        import test_operation_setup as host_tests
        import test_operation_host_cleanup as cleanup_tests
        self.host_control=host_tests.HostSetupTests('runTest')
        original=host_tests.transport_controls.OperationSetupTransportTests.fixture
        def fixture(test):
            identity,args=original(test);identity['runID']=str(uuid.uuid4());args['run_id']=identity['runID'];return identity,args
        with patch.object(host_tests.transport_controls.OperationSetupTransportTests,'fixture',fixture):self.host_control.setUp()
        self.addCleanup(self.host_control.doCleanups)
        h=self.host_control;self.raw=cleanup_tests.Device(h.remote)
        remote=m.ExecutionDevice(self.raw,execution_until=time.time()+300,deadline=h.channel.deadline)
        h.setup.remote=h.channel.remote=remote
        self.movie=types.SimpleNamespace(running=lambda:None)
        self.media=m.Media(h.setup,h.root/'media',binary=h.root/'codec',source_sha256='a'*64,
            binary_sha256='b'*64,nonce=str(uuid.uuid4()),movie=self.movie,wait=lambda:None)
        self.bindings={row['logicalSceneID']:t.encode(row) for row in self.raw.snapshot['input']}
        self.start=dict(identity=h.identity,phase='START',nonce=self.media.nonce,
            bindingSHA256={key:t.sha(raw) for key,raw in self.bindings.items()},
            bindings={key:t.load(raw) for key,raw in self.bindings.items()},surfaces={'fraction':.10000000000001})
        self.populate()

    def populate(self):
        self.raw.files[self.media.prefix+'display-START.json']=t.encode(self.start)
        for scene,raw in self.bindings.items():self.raw.files[self.media.prefix+'display-binding-'+scene+'.json']=raw

    def test_start_barrier_preserves_raw_bytes_and_actual_transfer_responses(self):
        original=self.raw.files[self.media.prefix+'display-START.json']
        self.media.start_barrier()
        self.assertEqual(self.media.start_raw,original)
        self.assertTrue(any(p.name.endswith('-response.json') for p in self.media.folder.iterdir()))
        with self.assertRaises(ValueError):self.media.start_barrier()

    def test_substituted_return_rejects_despite_matching_saved_file(self):
        self.raw.mode='substituted-return'
        with self.assertRaisesRegex(ValueError,'substituted'):self.media.start_barrier()
        self.assertTrue(any(p.name.endswith('-response.json') for p in self.media.folder.iterdir()))

    def test_native_failure_precedes_present_start_success(self):
        self.raw.files[self.media.prefix+'native-admission-failure.json']=b'{"state":"INVALID"}'
        with self.assertRaisesRegex(ValueError,'native admission failed'):self.media.start_barrier()
        self.assertFalse(any(source.endswith('display-START.json') for method,source in self.raw.calls if method=='pull'))

    def test_foreign_nonce_or_owner_cannot_supply_start_barrier(self):
        self.start['nonce']=str(uuid.uuid4());self.populate()
        with self.assertRaisesRegex(ValueError,'different native owners'):self.media.start_barrier()

    def test_only_missing_file_response_is_pending(self):
        self.assertIsNone(self.media.pull('missing.json',required=False))
        with self.assertRaisesRegex(ValueError,'required native artifact'):self.media.pull('missing.json')

    def review_fixture(self):
        self.media.start_barrier();h=self.host_control
        image=h.setup.folder/'screen.png';image.write_bytes(b'exact screenshot fixture')
        owners={scene:{k:v for k,v in t.load(raw).items() if k!='logicalSceneID'} for scene,raw in self.bindings.items()}
        request=dict(screenshot=str(image),screenshotSHA256=m.setup.file_sha(image),owners=owners)
        observations=[]
        for index,scene in enumerate(m.pixels.SCENES):
            for phase in [None,'START']:
                observations.append(dict(payload=m.pixels.marker(self.media.binding,scene,phase),
                    enclosingPixels=[index*100.0,0.0,40.0,40.0]))
        return request,dict(geometryValid=True,observations=observations)

    def test_start_owner_mapping_uses_enclosing_pixels_with_fractional_encoding(self):
        request,frame=self.review_fixture()
        with patch.object(self.media,'decode',return_value={}),patch.object(m.pixels,'checked',return_value=[frame]):
            reply=t.load(self.media.review_start(request,self.host_control.channel.deadline))
        self.assertEqual(reply['visibleOwners']['scene-B']['visibleRegion'],[100,0,40,40])
        self.assertEqual(reply['requestSHA256'],t.sha(t.encode(request)))

    def test_missing_start_pixels_prevent_host_proof(self):
        request,frame=self.review_fixture();frame['observations'].pop(0)
        with patch.object(self.media,'decode',return_value={}),patch.object(m.pixels,'checked',return_value=[frame]):
            with self.assertRaises(ValueError):self.media.review_start(request,self.host_control.channel.deadline)

    def test_wrong_screenshot_cannot_replace_collected_start(self):
        request,_=self.review_fixture();request['screenshotSHA256']='0'*64
        with self.assertRaisesRegex(ValueError,'collected screenshot'):
            self.media.review_start(request,self.host_control.channel.deadline)

if __name__=='__main__':unittest.main()
