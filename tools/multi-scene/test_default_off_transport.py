"""Composed dispatch, interruption, sticky completion and publication controls."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import default_off_transport as transport
import default_off_native as native


class OffCompositionControls(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name).resolve()
    def command(self):
        return [sys.executable,'-c',"from pathlib import Path;Path("+repr(str(self.root/'dispatched'))+").write_text('effect')"]
    def run_process(self,name,release=None):
        now=time.time();return transport.process(self.root,self.root,dict(os.environ),self.command(),name,now+2,now+5,release=release)
    def test_optimized_parent_and_unconditionally_gated_child_cannot_dispatch(self):
        env=dict(os.environ,PYTHONPATH=str(Path(transport.__file__).parent));env.pop('PYTHONOPTIMIZE',None)
        for option in ['-O','-OO']:
            code='import default_off_transport;'+self.command()[-1]
            result=subprocess.run([sys.executable,option,'-c',code],env=env,capture_output=True,timeout=5)
            self.assertNotEqual(result.returncode,0);self.assertFalse((self.root/'dispatched').exists())
            result=subprocess.run([sys.executable,option,'-c',transport.GATED,json.dumps(self.command())],env=env,input=b'',capture_output=True,timeout=5)
            self.assertEqual(result.returncode,78);self.assertFalse((self.root/'dispatched').exists())
    def test_external_build_override_and_wrong_device_cannot_dispatch(self):
        for key,value in [('XCODE_XCCONFIG_FILE','/private/unread-config'),('PYTHONOPTIMIZE','1')]:
            with self.assertRaises(RuntimeError):transport.process(self.root,self.root,dict(os.environ,**{key:value}),self.command(),key,time.time()+2,time.time()+5)
        declared=dict(udid='device',name='iPhone',runtime='iOS27')
        original=dict(udid='device',name='iPhone',runtime='iOS27',isAvailable=True)
        for k,v in [('runtime','iOS17'),('name','other'),('isAvailable',False)]:
            bad=dict(original,**{k:v})
            with self.assertRaises(RuntimeError):transport.device_identity(bad,declared)
        self.assertFalse((self.root/'dispatched').exists());self.assertEqual(list(self.root.iterdir()),[])
    def test_registration_failure_reaps_native_and_export_children_before_dispatch(self):
        publish=transport.publish
        def fail_start(path,value,join=lambda:None):
            if str(path).endswith('-start.json'):raise OSError('registration failure')
            return publish(path,value,join)
        for name in ['native-qualification','actual-summary']:
            with patch.object(transport,'publish',side_effect=fail_start):r=self.run_process(name)
            result=native.load(r[2]);self.assertEqual(result['exception_type'],'OSError');self.assertTrue(r[4]);self.assertFalse((self.root/'dispatched').exists())
    def test_group_discovery_failure_is_still_owned_and_reaped(self):
        with patch.object(transport.os,'getpgid',side_effect=OSError('discovery failure')):r=self.run_process('discovery')
        self.assertEqual(native.load(r[2])['exception_type'],'OSError');self.assertTrue(r[4]);self.assertFalse((self.root/'dispatched').exists())
    def test_base_exception_at_release_reaps_native_and_export_children(self):
        def interrupt(*args):raise KeyboardInterrupt('interrupted release')
        for name in ['native-qualification','actual-summary']:
            r=self.run_process(name,interrupt);self.assertEqual(native.load(r[2])['exception_type'],'KeyboardInterrupt');self.assertTrue(r[4]);self.assertFalse((self.root/'dispatched').exists())
    def test_interruption_during_wait_is_bounded_and_reaps_the_child(self):
        wait=subprocess.Popen.wait
        def interrupt(child,*args,**kwargs):
            if child.stdin is not None and child.stdin.closed:raise SystemExit('interrupted wait')
            return wait(child,*args,**kwargs)
        with patch.object(transport.subprocess.Popen,'wait',interrupt):r=self.run_process('wait-interrupt')
        self.assertEqual(native.load(r[2])['exception_type'],'SystemExit');self.assertTrue(r[4])
    def test_supported_signal_handler_enters_owned_cleanup(self):
        previous=transport.install_termination_handlers()
        try:
            handler=__import__('signal').getsignal(__import__('signal').SIGTERM)
            r=self.run_process('signal-release',lambda *args:handler(__import__('signal').SIGTERM,None))
            self.assertEqual(native.load(r[2])['exception_type'],'KeyboardInterrupt');self.assertTrue(r[4]);self.assertFalse((self.root/'dispatched').exists())
        finally:
            for signal,handler in previous.items():__import__('signal').signal(signal,handler)
    def test_late_input_replacement_withdraws_canonical_positive(self):
        p=self.root/'qualification.json';source=self.root/'input';source.write_text('before');count=0
        def join():
            nonlocal count;count+=1
            if count==2:source.write_text('after')
            if source.read_text()!='before':raise ValueError('input replaced')
        with self.assertRaises(ValueError):transport.publish(p,dict(state='PASS'),join)
        self.assertFalse(p.exists());self.assertEqual(len(list(self.root.glob('qualification.json.withdrawn-*'))),1)
    def test_fsync_readback_and_interruption_withdraw_publication(self):
        for kind in ['fsync','readback','interrupt']:
            p=self.root/(kind+'.json');counter=0
            def join():
                nonlocal counter;counter+=1
                if kind=='interrupt' and counter==2:raise KeyboardInterrupt('late interruption')
            if kind=='fsync':
                with patch.object(transport.os,'fsync',side_effect=OSError('fsync failure')):
                    with self.assertRaises(OSError):transport.publish(p,dict(state='PASS'),join)
            elif kind=='readback':
                original=Path.read_bytes
                def read(path):
                    if path==p:raise OSError('readback failure')
                    return original(path)
                with patch.object(Path,'read_bytes',read):
                    with self.assertRaises(OSError):transport.publish(p,dict(state='PASS'),join)
            else:
                with self.assertRaises(KeyboardInterrupt):transport.publish(p,dict(state='PASS'),join)
            self.assertFalse(p.exists());self.assertEqual(len(list(self.root.glob(kind+'.json.withdrawn-*'))),1)
    def test_interruption_in_stdin_close_does_not_abandon_cleanup(self):
        child=subprocess.Popen([sys.executable,'-c','import sys;sys.stdin.buffer.read()'],stdin=subprocess.PIPE,start_new_session=True)
        original=child.stdin
        class InterruptedClose:
            closed=False
            def close(self):raise KeyboardInterrupt('close interrupted')
        child.stdin=InterruptedClose()
        try:
            observed=transport.cleanup_group(child,child.pid,time.time()+5)
            self.assertTrue(observed['owned_group_absent']);self.assertIn('KeyboardInterrupt',observed['signal_errors'])
        finally:
            original.close()
            if child.poll() is None:os.killpg(child.pid,__import__('signal').SIGKILL)
            child.wait(timeout=5)
    def test_cleanup_interruption_escalates_term_resistant_group_and_descendant(self):
        ready=self.root/'descendant-ready'
        code="import os,signal,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);pid=os.fork();"+"from pathlib import Path;Path("+repr(str(ready))+").write_text(str(os.getpid()));time.sleep(20)"
        child=subprocess.Popen([sys.executable,'-c',code],start_new_session=True)
        cutoff=time.time()+8
        while not ready.exists() and time.time()<cutoff:time.sleep(.01)
        self.assertTrue(ready.exists())
        original_sleep=time.sleep;interruptions=[]
        def interrupt_once(seconds):
            if not interruptions:
                interruptions.append(True);raise SystemExit('cleanup sleep interrupted')
            original_sleep(seconds)
        try:
            with patch.object(transport.time,'sleep',side_effect=interrupt_once):observed=transport.cleanup_group(child,child.pid,cutoff)
            self.assertTrue(observed['owned_group_absent'],observed);self.assertIn('SystemExit',observed['signal_errors'])
            self.assertEqual(child.returncode,-__import__('signal').SIGKILL)
        finally:
            try:os.killpg(child.pid,__import__('signal').SIGKILL)
            except ProcessLookupError:pass
            child.wait(timeout=5)
    def test_first_supported_signal_during_cleanup_is_preserved_and_drained(self):
        previous=transport.install_termination_handlers();original_sleep=time.sleep;sent=[]
        child=subprocess.Popen([sys.executable,'-c','import signal,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);time.sleep(20)'],start_new_session=True)
        original_sleep(.1)
        def signal_once(seconds):
            if not sent:
                sent.append(True);__import__('signal').getsignal(__import__('signal').SIGTERM)(__import__('signal').SIGTERM,None)
            original_sleep(seconds)
        try:
            with patch.object(transport.time,'sleep',side_effect=signal_once):observed=transport.cleanup_group(child,child.pid,time.time()+6)
            self.assertTrue(observed['owned_group_absent'],observed);self.assertEqual(observed['interruption_type'],'KeyboardInterrupt')
        finally:
            for sig,handler in previous.items():__import__('signal').signal(sig,handler)
            try:os.killpg(child.pid,__import__('signal').SIGKILL)
            except ProcessLookupError:pass
            child.wait(timeout=5)
    def successful_stopped_packet(self):
        root=self.root
        def save(name,value):return native.write(root/name,value)
        controller=root/'controller.py';controller.write_text('# constructed control only\n')
        d=dict(consumer_bindings={},controller=native.ref(controller),command=['constructed-command'],device=dict(udid='device'),operational_window_cutoff=1000)
        definition=save('definition.json',d);review=save('review.json',dict(verdict='PASS_COMPONENT_QUALIFICATION_PROPOSAL_ONLY',reviewer='/root/rum_runtime_reviewer',definitions=[definition],controllers=[native.ref(controller)]))
        stdout=root/'native-qualification.stdout';stderr=root/'native-qualification.stderr';stdout.write_text('');stderr.write_text('')
        a=dict(controller_pid=7,controller_pgid=7,definition=definition,review=review,controller=native.ref(controller),command=d['command'],started_at=1,deadline=661,cleanup_deadline=841,original_device=dict(udid='device',state='Shutdown'))
        ad=save('admission.json',a);start=save('native-qualification-start.json',dict(controller_pid=7,pid=8,pgid=8,command=d['command'],deadline=661,cleanup_cutoff=841))
        out=save('native-qualification-outcome.json',dict(start=start,returncode=0,timed_out=False,exception_type=None,owned_group_absent=True,completed_at=5,stdout=native.ref(stdout),stderr=native.ref(stderr)))
        cleanup=save('cleanup.json',dict(admission=ad,process_outcome=out,child=start,state='PASS_COMPONENT_LANE_RESTORATION_ONLY',original_state_restored=True,selected_device_state='Shutdown',completed_at=6))
        issued=dict(state='COMPONENT_TESTS_RETURNED_REQUIRES_RECONCILIATION',controller_pid=7,definition=definition,review=review,controller=native.ref(controller),admission=ad,child=start,outcome=out,cleanup=cleanup)
        save('completion.json',dict(state='CONTROLLER_RETURNED_AFTER_OWNER_PUBLICATION',definition=definition,review=review,controller=native.ref(controller),admission=ad,child=start,outcome=out,cleanup=cleanup,issued_owner=issued,completed_at=7))
        self.assertEqual(native.authority(root)[1]['returncode'],0)
        save('controller-stop.json',dict(state='STOPPED_PUBLICATION_FAILURE'))
        return d
    def test_successful_command_and_cleanup_cannot_hide_controller_stop(self):
        self.successful_stopped_packet()
        with patch.object(transport,'process') as dispatch:
            with self.assertRaises(ValueError):native.collect(self.root)
            dispatch.assert_not_called()
        with self.assertRaises(ValueError):native.authority(self.root)
    def test_simultaneous_saved_faults_are_aggregated_and_failed_cases_retained(self):
        d=self.successful_stopped_packet();d['cwd']=str(self.root);d['compiler_sdk']='sdk';d['source_freeze']={};d['source_verifier']={};d['saved_helper']={}
        expected=self.root/'expected.json';expected.write_text(json.dumps({t:[] for t in native.TARGETS}));d['expected_source_lists']=native.ref(expected);d['other_sources']=native.ref(expected)
        (self.root/'definition.json').write_text(json.dumps(d))
        (self.root/'actual-tests.stdout').write_text(json.dumps(dict(testNodes=[dict(nodeType='Test Case',nodeIdentifier='kept-failed-test',result='Failed')])))
        (self.root/'actual-summary.stdout').write_text(json.dumps(dict(result='Failed')))
        helper_path=Path('/Users/valentin.pertuisot/work/dd-sdk-ios-extractions/evidence/rum-continue-20261003-fp13e2hd/input-off-qualification-mechanism-cycle1/reconcile.py')
        h={'__name__':'saved_control_helper'};exec(compile(helper_path.read_bytes(),str(helper_path),'exec'),h)
        with patch.object(native,'helper',return_value=h):report=native.grade(self.root)
        phases={x['phase'] for x in report['issues']};self.assertEqual(report['state'],'INCOMPLETE')
        for prefix in ['authority','compiler:','products:','native-result-members','export:']:self.assertTrue(any(p.startswith(prefix) for p in phases),prefix)
        self.assertEqual(report['native_case_observations'][0]['result'],'Failed')

if __name__=='__main__':unittest.main()
