"""Run the real intake and barriers against an explicit in-process device double."""
import copy
from contextlib import nullcontext
import json
from pathlib import Path
import shutil
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest
import urllib.request
from unittest.mock import patch

import run as runner
import same_key_contract as contract
import same_key_setup as setup
import same_key_human as preparation
from test_same_key import fixtures, native


class Runner(unittest.TestCase):
    def exercise(self, *, human, background_peer=False, cleanup_failure=False,late_checkpoint=False):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); product=root/'simulator'; product.mkdir()
            app=root/'built.app';app.mkdir()
            (product/'product.json').write_text(json.dumps(dict(path=str(app),product={'fixed':True})))
            location=root/'installed.app';container=root/'data';documents=container/'Documents'
            plan=dict(source='source',protected={},multiple_scenes=True)
            installed=False; stopped=threading.Event(); errors=[]; work=[]; commands=[]; client=None
            real_time=time.time;clock_offset=[0]
            def command(argv, **kwargs):
                nonlocal installed,client
                commands.append(list(argv))
                stdout=b'';stderr=b'';code=0
                if argv[:3]==['xcrun','simctl','list']:
                    stdout=json.dumps({'devices':{'com.apple.CoreSimulator.SimRuntime.iOS-27-0':[dict(udid='device',state='Booted')]}}).encode()
                elif argv[:3]==['xcrun','simctl','get_app_container']:
                    if not installed:code=1;stderr=b'No such file'
                    else:stdout=str(location if argv[-1]=='app' else container).encode()
                elif argv[:3]==['xcrun','simctl','install']:
                    installed=True;location.mkdir();documents.mkdir(parents=True)
                elif argv[:3]==['xcrun','simctl','launch']:
                    run_id=argv[argv.index('--run-id')+1];endpoint=argv[argv.index('--endpoint')+1].rsplit('/',1)[0]
                    def actual(index):
                        n=native(index);n.update(run_id=run_id,at=time.time(),uptime=time.monotonic())
                        n['topology'][1]['activities'][0]['run_id']=run_id
                        n['setup_admission']={}
                        return n
                    def request(path,value):
                        body=value if isinstance(value,bytes) else json.dumps(value).encode()
                        with urllib.request.urlopen(urllib.request.Request(endpoint+path,data=body),timeout=5) as response:
                            raw=response.read();return json.loads(raw) if raw else None
                    def app_loop():
                        try:
                            admitted=None;complete=False;ready_sent=False;idle_sent=False
                            while not stopped.is_set():
                                folders=list((root/'cells').glob('*'))
                                if not folders:time.sleep(.01);continue
                                folder=folders[0];barrier=folder/'human-setup'
                                for phase in ['setup','cleanup']:
                                    path=barrier/('operator-'+phase)/'request.json'
                                    if path.exists() and not path.with_name('operator-released.json').exists():
                                        setup.physical_release.acknowledge(path,'Released; ready in offline fixture')
                                captured=documents/'setup-request.json'
                                if human and captured.exists() and not ready_sent:
                                    req=setup.read(captured);n=actual(0);n.update(phase='setup-ready',nonce=req['nonce'],request_sha256=setup.sha(captured.read_bytes()),
                                        input=[dict(scene='scene-'+o,window='window-'+o,controller='root-'+o,touches=0,transitioning=False,resizing=False) for o in ['A','B']])
                                    if background_peer:n['topology'][0]['state']=2
                                    setup.publish(documents/'setup-ready.json',n);ready_sent=True
                                if human and (documents/'setup-start.json').exists():
                                    start=setup.read(documents/'setup-start.json');admitted={k:start[k] for k in ['ready_sha256','nonce']}
                                if (admitted is not None or not human) and not complete:
                                    _,_,samples=fixtures();checkpoints=[];prefix=0
                                    for i,sample in enumerate(samples):
                                        n=actual(i);n['setup_admission']=admitted or {}
                                        events=sample['events']
                                        if events[prefix:]:request('/rum',b'\n'.join(json.dumps(e).encode() for e in events[prefix:]))
                                        prefix=len(events)
                                        if late_checkpoint and i==0:
                                            clock_offset[0]=301
                                            try:request('/checkpoint',n)
                                            except urllib.error.HTTPError as error:
                                                try:
                                                    if error.code!=409:raise
                                                finally:error.close()
                                            else:raise AssertionError('late checkpoint accepted')
                                            setup.publish(documents/'result.json',dict(phase='failed'));complete=True;break
                                        ack=request('/checkpoint',n);checkpoints.append(ack);work.append(n['phase'])
                                    final=actual(3);final.update(phase='complete',acknowledgments=checkpoints,setup_admission=admitted or {})
                                    if not late_checkpoint:setup.publish(documents/'result.json',final)
                                    complete=True
                                cleanup=documents/'cleanup-request.json'
                                if cleanup.exists() and not idle_sent:
                                    req=setup.read(cleanup);n=actual(3 if complete else 0)
                                    n.update(phase='cleanup-idle',nonce=req['nonce'],request_sha256=setup.sha(cleanup.read_bytes()),setup_admission=admitted or {},
                                        input=[dict(scene='scene-'+o,window='window-'+o,controller='root-'+o,touches=0,transitioning=False,resizing=False) for o in ['A','B']])
                                    setup.publish(documents/'cleanup-idle.json',n);idle_sent=True
                                time.sleep(.01)
                        except Exception as error:
                            errors.append(repr(error))
                            if not (documents/'result.json').exists():setup.publish(documents/'result.json',dict(phase='failed'))
                    client=threading.Thread(target=app_loop,daemon=True);client.start()
                    stdout=(runner.build.BUNDLE+': 42\n').encode()
                elif argv[:3]==['xcrun','simctl','terminate']:
                    stopped.set();client.join(timeout=5)
                elif argv[:3]==['xcrun','simctl','uninstall']:
                    installed=False;shutil.rmtree(location);shutil.rmtree(container)
                elif argv[0]=='ps':pass
                else:raise AssertionError('Unexpected command; no real native call permitted: '+repr(argv))
                return SimpleNamespace(stdout=stdout,stderr=stderr,returncode=code)
            with patch.object(preparation,'verify',return_value={}),patch.object(runner.build,'verify',return_value=plan),patch.object(runner.build,'protected',return_value={}),\
                 patch.object(runner.shared,'product',return_value={'fixed':True}),patch.object(runner.shared,'capture',side_effect=command),\
                 patch.object(time,'time',side_effect=lambda:real_time()+clock_offset[0]),\
                 patch('builtins.print'),\
                 (patch.object(setup.Barrier,'cleanup',side_effect=ValueError('forced fence failure')) if cleanup_failure else nullcontext()):
                try:passed=runner.run(root,'device','27.0','swift',qualification=contract,human_setup=human)
                finally:
                    stopped.set()
                    if client:client.join(timeout=5)
            self.assertEqual(errors,[])
            self.assertFalse(client.is_alive())
            folder=root/'cells/27.0-swift';summary=setup.read(folder/'summary.json')
            if cleanup_failure:
                self.assertTrue(installed)
                self.assertTrue(location.exists() and container.exists())
                self.assertFalse(passed)
                self.assertEqual(summary['cleanup'],'FAILED')
                self.assertEqual(summary['overall'],'INVALID')
                self.assertEqual(work,[] if background_peer else contract.PHASES)
                forbidden={'terminate','uninstall','shutdown'}
                self.assertFalse([argv for argv in commands if argv[:2]==['xcrun','simctl'] and argv[2] in forbidden])
                return
            self.assertFalse(installed)
            self.assertEqual(summary['cleanup'],'PASS')
            if late_checkpoint:
                self.assertFalse(passed);self.assertEqual(work,[])
                self.assertTrue((folder/'checkpoint-0.bin').exists())
                self.assertFalse((folder/'checkpoint-0.json').exists())
                self.assertEqual(summary['execution_deadline']-summary['execution_started_at'],300)
            elif background_peer:
                self.assertFalse(passed);self.assertEqual(work,[])
                self.assertIsNone(summary['execution_deadline'])
                self.assertFalse((folder/'human-setup/api-admission.json').exists())
            else:
                self.assertTrue(passed,summary)
                self.assertEqual(work,contract.PHASES)
                self.assertEqual(summary['overall'],'PASS')
                if human:
                    admission=setup.read(folder/'human-setup/api-admission.json')
                    self.assertEqual(summary['execution_deadline'],admission['execution_deadline'])
                    self.assertEqual(summary['execution_deadline']-summary['execution_started_at'],300)
                else:self.assertFalse((folder/'human-setup').exists())

    def test_complete_human_barrier_intake_and_cleanup(self):self.exercise(human=True)
    def test_background_peer_stops_before_api_and_still_cleans(self):self.exercise(human=True,background_peer=True)
    def test_default_automatic_runner_has_no_human_barrier(self):self.exercise(human=False)
    def test_failed_cleanup_after_complete_api_preserves_app(self):self.exercise(human=True,cleanup_failure=True)
    def test_failed_cleanup_after_setup_rejection_preserves_app(self):self.exercise(human=True,background_peer=True,cleanup_failure=True)
    def test_late_checkpoint_preserves_raw_rejects_evidence_and_still_requires_safe_cleanup(self):self.exercise(human=True,late_checkpoint=True)


if __name__=='__main__':unittest.main()
