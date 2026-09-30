"""Synthetic bootstrap/cleanup controls; no IO reaches a simulator or device."""
import base64
import copy
import json
from pathlib import Path
import plistlib
import tempfile
import time
import unittest
from unittest.mock import patch
import uuid

from acceptance_common import Rejected
import operation_transport as t
import scene_background_bootstrap as host
import scene_background_cycle as cycle
from test_focus_activation_host import Device as FocusDevice
from test_focus_activation_transport import response
from test_scene_background_cycle import native


def witness(run, phase='before'):
    value = native(phase,[]); value['runID'] = run
    return value


def one_owner(run):
    value = witness(run)['snapshot']
    for key in ['scenes','input','inventory']: value[key] = value[key][:1]
    value['continuity']['owners'] = value['continuity']['owners'][:1]
    value['connectedSceneIDs'] = [value['scenes'][0]['nativeSceneID']]
    value['scenes'][0]['activationState'] = value['inventory'][0]['activationState'] = 'foreground-active'
    value['inventory'][0]['keyWindowIdentity'] = value['scenes'][0]['windowIdentity']
    value['inventory'][0]['windows'][0]['key'] = True
    return value


class Device(FocusDevice):
    def __init__(self,root,app):
        super().__init__(root,app)
        self.identity.update(scenarioID=cycle.SCENARIO,profile=cycle.PROFILE)
        self.startup['scenarioID'] = cycle.SCENARIO
        self.channel = self.prefix+'.background-channel/'
        self.files[self.prefix+'.startup-freshness.json'] = t.encode(self.startup)
        self.files[self.channel+'challenge.json'] = t.encode(self.identity)
        self.stop_snapshot = one_owner(self.identity['runID'])
        self.after_command = None

    def push(self,bundle,source,destination,label,deadline):
        self.calls.append(('push',destination)); raw = Path(source).read_bytes(); self.files[destination] = raw
        if destination.endswith('.request'):
            sent = self.files[self.channel+raw.decode()+'.json']; operation = t.load(sent)['operation']
            value = copy.deepcopy(self.stop_snapshot if operation == 'stop' else one_owner(self.identity['runID']))
            if operation == 'stop':
                if self.mode == 'held-input': value['input'][0]['touches'] = 1
                if self.mode in ['changed-A-observer','changed-B-observer']:
                    index = 0 if self.mode.startswith('changed-A') else 1
                    value['input'][index]['observerIdentity'] = 'replacement'
                if self.mode == 'changed-B-generation':
                    for key in ['scenes','input']: value[key][1]['generation'] += 1
                    value['continuity']['owners'][1]['generation'] += 1
            returned = response(sent,value)
            if operation == 'stop' and self.mode == 'never-stopped': returned['driver']['stopped'] = False
            self.files[self.channel+raw.decode()+'.reply.json'] = t.encode(returned)
        args = ['device','copy','to','--domain-type','appDataContainer','--domain-identifier',bundle,
                '--source',str(source),'--destination',destination]
        return self.returned(args,label,{},deadline)

    def command(self,args,label,deadline,*,check=True):
        result,receipt = super().command(args,label,deadline,check=check)
        if self.mode == 'restarted-PID' and label == 'cleanup-process-absence':
            result['result']['runningProcesses'] = [dict(self.process,processIdentifier=124)]
            raw = t.encode(result); folder = self.output/f'{self.sequence:05d}-{label}'
            (folder/'response.json').write_bytes(raw); receipt['response_sha256'] = t.sha(raw)
            (folder/'receipt.json').write_bytes(t.encode(receipt))
        if self.after_command is not None: self.after_command(label)
        return result,receipt


class Channel:
    """Synthetic first inspection only; no visibility, native or permit claim."""
    def __init__(self,session):
        self.remote = session.remote; self.bundle = session.expected['bundle']; self.identity = session.identity
        self.index = 0; self.evidence = session.output/'synthetic-inspection'; self.evidence.mkdir()
        observed = witness(self.identity['runID'])
        raw = t.encode(dict(identity=self.identity,sequence=1,boundary=host.phases.PHASES[0],
            before=base64.b64encode(t.encode(observed)).decode(),after=base64.b64encode(t.encode(observed)).decode(),
            snapshot=dict(signals=[])))
        digest = t.sha(raw); self.latest = dict(name='capture-'+digest+'.json',sha256=digest,bytes=len(raw))
        (self.evidence/self.latest['name']).write_bytes(raw)
        self.remote.stop_snapshot = witness(self.identity['runID'],'foreground')['snapshot']

    def live(self): host.capture.read_reference(self.evidence,self.latest)


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='h10-bootstrap-synthetic-'); self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve(); self.app = self.root/'Focus.app'; self.app.mkdir()
        (self.app/'Info.plist').write_bytes(plistlib.dumps(dict(CFBundleExecutable='Focus',CFBundleIdentifier='offline.focus')))
        (self.app/'Focus').write_bytes(bytes.fromhex('cffaedfe')+b'synthetic-only')
        self.remote = Device(self.root,self.app)
        self.session = host.Session(self.remote,self.app,self.root/'host',run_id=self.remote.identity['runID'],
            process_id=123,revision='a'*40,startup_nonce=self.remote.nonce,execution_ms=self.remote.execution,
            cleanup_ms=self.remote.cleanup,device_udid='offline-udid',expected_sources=host.LOADED_SOURCES,wait=lambda:None)

    def armed(self): self.session.bootstrap(); self.session.exchange('arm')

    def release(self):
        path = self.session.request_release()
        return path,host.release.acknowledge(path,'SYNTHETIC RELEASE CONTROL; no human session')

    def removals(self):
        return [x for x in self.remote.calls if x[0] == 'command' and x[1][1] in ['process','uninstall']]

    def mutate_save(self,path,transform):
        actual = host.t.save
        def save(target,raw):
            actual(target,raw)
            if Path(target) == path: Path(target).write_bytes(transform(raw))
        return patch.object(host.t,'save',side_effect=save)

    def test_acknowledged_stopped_cleanup_preserves_full_invalid_tail_without_gate_claim(self):
        self.armed(); self.session.failed = True; self.session.retain_recorder()
        actual = self.remote.recorder+b'partial-invalid-tail'; self.remote.files[host.base.recorder.SOURCE] = actual
        self.release(); result = self.session.cleanup()
        self.assertEqual(result['state'],'TASK_APP_REMOVED')
        self.assertEqual(result['containerAbsence'],'UNVERIFIED'); self.assertFalse(result['releaseAcceptance'])
        self.assertEqual((result['scenario'],result['evidence']),('UNCHANGED','UNCHANGED'))
        self.assertEqual((self.session.output/'cleanup/final-recorder.jsonl').read_bytes(),actual)
        self.assertEqual([x[1][:3] for x in self.removals()],
                         [['device','process','terminate'],['device','uninstall','app']])
        self.assertFalse(self.remote.alive); self.assertFalse(self.remote.installed)

    def test_wrong_profile_stops_before_arm_or_native_input(self):
        for key,value in [('profile',host.control.PROFILE),('scenarioID',host.control.SCENARIO)]:
            with self.subTest(key=key),self.assertRaises(ValueError):
                host.challenge(t.encode(self.remote.identity|{key:value}),self.remote.installed_bytes,self.session.expected)
        self.remote.files[self.remote.channel+'challenge.json'] = t.encode(self.remote.identity|{'profile':host.control.PROFILE})
        with self.assertRaises(ValueError): self.session.bootstrap()
        self.assertFalse(any(call[0] == 'push' for call in self.remote.calls)); self.assertEqual(self.removals(),[])

    def test_startup_rejects_changed_nonce_scope_boundary_or_stale_storage(self):
        for key,value in [('nonce',str(uuid.uuid4())),('scenarioID',host.control.SCENARIO),('processID',True),
                          ('boundary','after-sdk'),('releaseAcceptance',True),
                          ('paths',self.remote.startup['paths']|{'Documents':'NONEMPTY'})]:
            with self.subTest(key=key),self.assertRaises(ValueError):
                host.freshness(t.encode(self.remote.startup|{key:value}),self.session.expected)

    def test_installed_code_mismatch_does_not_dispatch(self):
        value = t.load(self.remote.installed_bytes); value['binaries']['Focus'] = '0'*64
        self.remote.files[self.remote.prefix+'.installed-code.json'] = t.encode(value)
        with self.assertRaises(ValueError): self.session.bootstrap()
        self.assertFalse(any(call[0] == 'push' for call in self.remote.calls))

    def test_product_change_after_bootstrap_blocks_arm(self):
        self.session.bootstrap(); (self.app/'Focus').write_bytes(bytes.fromhex('cffaedfe')+b'changed')
        with self.assertRaises(ValueError): self.session.exchange('arm')
        self.assertFalse(any(call[0] == 'push' for call in self.remote.calls))

    def test_process_replacement_blocks_arm(self):
        self.session.bootstrap(); self.remote.mode = 'replaced-process'
        with self.assertRaises(ValueError): self.session.exchange('arm')
        self.assertFalse(any(call[0] == 'push' for call in self.remote.calls))

    def test_changed_helper_or_persisted_source_manifest_stops_before_native_effect(self):
        self.session.bootstrap(); changed = host.LOADED_SOURCES|{str(Path(host.__file__).resolve()):'0'*64}
        with patch.object(host,'sources',return_value=changed),self.assertRaises(ValueError): self.session.exchange('arm')
        self.assertFalse(any(call[0] == 'push' for call in self.remote.calls))

    def test_changed_source_manifest_blocks_arm(self):
        self.session.bootstrap(); (self.session.output/'sources.json').write_bytes(b'changed')
        with self.assertRaises(ValueError): self.session.exchange('arm')
        self.assertFalse(any(call[0] == 'push' for call in self.remote.calls))

    def test_bootstrap_artifact_changed_during_publication_invalidates_result(self):
        path = self.session.output/'bootstrap/challenge.json'
        with self.mutate_save(path,lambda raw:raw+b'\n'),self.assertRaises(ValueError): self.session.bootstrap()
        self.assertTrue((self.session.output/'bootstrap/invalidated-result.json').exists())
        self.assertFalse((self.session.output/'bootstrap/result.json').exists())

    def test_control_result_changed_during_publication_never_qualifies(self):
        self.session.bootstrap(); path = self.session.output/'arm/result.json'
        with self.mutate_save(path,lambda raw:raw+b'\n'),self.assertRaises(ValueError): self.session.exchange('arm')
        self.assertFalse((self.session.output/'arm/result.json').exists()); self.assertEqual(self.removals(),[])

    def test_actual_io_response_changed_after_arm_blocks_cleanup(self):
        self.armed(); path = next((self.session.output/'io-execution').glob('*-response.json'))
        path.write_bytes(path.read_bytes()+b'\n')
        with self.assertRaises(ValueError): self.session.request_release()
        self.assertEqual(self.removals(),[])

    def test_actual_io_receipt_changed_during_publication_stops_arm(self):
        self.session.bootstrap(); label = f'{self.remote.sequence+1:05d}-arm-process-before-receipt.json'
        path = self.session.output/'io-execution'/label
        with self.mutate_save(path,lambda raw:raw+b'\n'),self.assertRaises(ValueError): self.session.exchange('arm')
        self.assertEqual(self.removals(),[])

    def test_late_unreaped_and_substituted_actual_returns_do_not_dispatch(self):
        self.session.bootstrap()
        for mode in ['late','unreaped','substituted-return']:
            # Validate each actual returned observation independently, without reusing the consumed ARM.
            self.remote.mode = mode
            with self.subTest(mode=mode),self.assertRaises(ValueError): self.session.current_process('execution','bad-'+mode)
        self.assertFalse(any(call[0] == 'push' for call in self.remote.calls))

    def test_public_stop_requires_actual_release_before_any_command(self):
        self.armed(); count = len(self.remote.calls)
        with self.assertRaises(ValueError): self.session.exchange('stop')
        self.assertEqual(len(self.remote.calls),count); self.assertEqual(self.removals(),[])

    def test_cleanup_requires_acknowledgement_and_keeps_task_open(self):
        self.armed(); self.session.request_release(); count = len(self.remote.calls)
        with self.assertRaisesRegex(ValueError,'missing or symlinked'): self.session.cleanup()
        self.assertEqual(len(self.remote.calls),count); self.assertTrue(self.remote.alive)

    def test_release_request_is_bound_to_original_cleanup_cutoff_and_context(self):
        self.armed(); path,reply = self.release(); request = t.load(path.read_bytes())
        self.assertEqual(request['deadline'],self.remote.cleanup/1000)
        self.assertEqual(request['channel_identity_sha256'],t.sha(t.encode(self.remote.identity)))
        for key,value in [('run_id','foreign'),('request_sha256','0'*64),('at',float('inf')),
                          ('at',request['deadline']),('user_message','')]:
            (path.parent/'operator-released.json').write_bytes(t.encode(reply|{key:value}) if value != float('inf')
                else json.dumps(reply|{key:value}).encode())
            with self.subTest(key=key),self.assertRaises((ValueError,Rejected)): self.session.released()
        self.assertEqual(self.removals(),[])

    def test_release_acknowledgement_cannot_be_replaced_after_consumption(self):
        self.armed(); path,reply = self.release(); self.session.released()
        (path.parent/'operator-released.json').write_bytes(t.encode(reply|{'user_message':'another control'}))
        with self.assertRaises(ValueError): self.session.cleanup()
        self.assertEqual(self.removals(),[])

    def test_held_input_prevents_task_removal(self):
        self.armed(); self.release(); self.remote.mode = 'held-input'
        with self.assertRaises(ValueError): self.session.cleanup()
        self.assertEqual(self.removals(),[])

    def test_unstopped_native_driver_prevents_task_removal(self):
        self.armed(); self.release(); self.remote.mode = 'never-stopped'
        with self.assertRaises(ValueError): self.session.cleanup()
        self.assertEqual(self.removals(),[])

    def test_changed_original_A_observer_prevents_task_removal(self):
        self.armed(); self.release(); self.remote.mode = 'changed-A-observer'
        with self.assertRaises(ValueError): self.session.cleanup()
        self.assertEqual(self.removals(),[])

    def test_initial_two_scene_owners_are_preserved_through_cleanup(self):
        self.armed(); channel = Channel(self.session); result = self.session.remember_owners(channel)
        self.assertFalse(result['native_acceptance']); self.release()
        self.assertEqual(self.session.cleanup()['state'],'TASK_APP_REMOVED')

    def test_captured_B_observer_change_prevents_task_removal(self):
        self.armed(); self.session.remember_owners(Channel(self.session)); self.release()
        self.remote.mode = 'changed-B-observer'
        with self.assertRaises(ValueError): self.session.cleanup()
        self.assertEqual(self.removals(),[])

    def test_captured_B_generation_change_prevents_task_removal(self):
        self.armed(); self.session.remember_owners(Channel(self.session)); self.release()
        self.remote.mode = 'changed-B-generation'
        with self.assertRaises(ValueError): self.session.cleanup()
        self.assertEqual(self.removals(),[])

    def test_replaced_critical_inspection_prevents_cleanup(self):
        self.armed(); channel = Channel(self.session); self.session.remember_owners(channel)
        (channel.evidence/channel.latest['name']).write_bytes(b'changed')
        with self.assertRaises(Rejected): self.session.request_release()
        self.assertEqual(self.removals(),[])

    def replace_inspection_at_publication(self,redirect=False):
        self.armed(); channel = Channel(self.session); original = dict(channel.latest)
        directory = channel.evidence; original_raw = host.capture.read_reference(directory,original)
        replacement = t.load(original_raw); replacement['sequence'] += 1
        raw = t.encode(replacement); digest = t.sha(raw)
        reference = dict(name='capture-'+digest+'.json',sha256=digest,bytes=len(raw))
        other = self.session.output/'redirected-inspection' if redirect else directory
        if redirect: other.mkdir()
        (other/reference['name']).write_bytes(raw); actual = host.t.save
        def save(path,data):
            actual(path,data)
            if Path(path) == self.session.output/'critical-owners.json':
                channel.evidence = other; channel.latest = reference
        with patch.object(host.t,'save',side_effect=save),self.assertRaises(ValueError):
            self.session.remember_owners(channel)
        self.assertTrue(self.session.failed)
        self.assertEqual(self.session.critical['reference'],original)
        issued = t.load((self.session.output/'critical-owners.json').read_bytes())
        self.assertEqual(issued['reference'],original); self.assertEqual(issued['directory'],str(directory))
        self.assertEqual(host.capture.read_reference(directory,original),original_raw)
        self.assertTrue((self.session.output/'critical-owner-binding/failure.json').exists())
        self.assertEqual(self.removals(),[])

    def test_initial_capture_descriptor_replacement_at_publication_is_rejected(self):
        self.replace_inspection_at_publication()

    def test_initial_capture_directory_redirection_at_publication_is_rejected(self):
        self.replace_inspection_at_publication(redirect=True)

    def mutation_before_uninstall(self,relative=None,changed_helper=False):
        self.armed(); self.release(); fired = False
        changed = host.LOADED_SOURCES|{str(Path(host.__file__).resolve()):'0'*64}
        actual_sources = host.sources
        def mutate(label):
            nonlocal fired
            if label == 'cleanup-process-absence':
                fired = True
                if relative is not None:
                    path = self.session.output/relative; path.write_bytes(path.read_bytes()+b'\n')
        def sources(): return changed if fired and changed_helper else actual_sources()
        self.remote.after_command = mutate
        with patch.object(host,'sources',side_effect=sources),self.assertRaises(ValueError): self.session.cleanup()
        self.assertTrue(fired); self.assertFalse(self.remote.alive); self.assertTrue(self.remote.installed)
        self.assertEqual([x[1][:3] for x in self.removals()],[['device','process','terminate']])
        self.assertEqual((self.session.output/'cleanup/final-recorder-0000.raw').read_bytes(),self.remote.recorder)
        self.assertFalse((self.session.output/'cleanup/result.json').exists())
        self.assertTrue((self.session.output/'cleanup/failure.json').exists())

    def test_stop_mutation_after_process_absence_prevents_uninstall(self):
        self.mutation_before_uninstall('stop/reply.json')

    def test_source_manifest_mutation_after_process_absence_prevents_uninstall(self):
        self.mutation_before_uninstall('sources.json')

    def test_helper_closure_mutation_after_process_absence_prevents_uninstall(self):
        self.mutation_before_uninstall(changed_helper=True)

    def test_release_ack_mutation_after_process_absence_prevents_uninstall(self):
        self.mutation_before_uninstall('release/operator-released.json')

    def test_admission_mutation_after_process_absence_prevents_uninstall(self):
        self.mutation_before_uninstall('cleanup/teardown-admission.json')

    def test_final_recorder_mutation_after_process_absence_prevents_uninstall(self):
        self.mutation_before_uninstall('cleanup/final-recorder.jsonl')

    def test_host_quiescence_mutation_after_process_absence_prevents_uninstall(self):
        self.mutation_before_uninstall('cleanup/host-quiescence.json')

    def test_host_workers_must_be_quiescent_before_task_removal(self):
        self.armed(); self.release(); self.remote.mode = 'live-worker'
        with self.assertRaises(ValueError): self.session.cleanup()
        self.assertEqual(self.removals(),[])

    def test_truncated_full_recorder_is_preserved_and_prevents_task_removal(self):
        self.armed(); self.session.retain_recorder(); self.remote.files[host.base.recorder.SOURCE] = self.remote.recorder[:20]
        self.release()
        with self.assertRaises(ValueError): self.session.cleanup()
        self.assertEqual((self.session.output/'cleanup/final-recorder.jsonl').read_bytes(),self.remote.recorder[:20])
        self.assertEqual(self.removals(),[])

    def test_stop_replacement_at_teardown_publication_invalidates_admission(self):
        self.armed(); self.release(); actual = host.t.save
        def save(path,raw):
            actual(path,raw)
            if Path(path) == self.session.output/'cleanup/teardown-admission.json':
                target = self.session.output/'stop/reply.json'; target.write_bytes(target.read_bytes()+b'\n')
        with patch.object(host.t,'save',side_effect=save),self.assertRaises(ValueError): self.session.cleanup()
        self.assertEqual(self.removals(),[])
        self.assertFalse((self.session.output/'cleanup/teardown-admission.json').exists())
        self.assertTrue((self.session.output/'cleanup/invalidated-teardown-admission.json').exists())

    def test_cleanup_publication_mutation_never_leaves_positive_result(self):
        self.armed(); self.release(); path = self.session.output/'cleanup/result.json'
        with self.mutate_save(path,lambda raw:raw+b'\n'),self.assertRaises(ValueError): self.session.cleanup()
        self.assertFalse(path.exists()); self.assertFalse(self.remote.installed)
        self.assertTrue((path.parent/'invalidated-result.json').exists())

    def test_retained_task_app_keeps_cleanup_invalid(self):
        self.armed(); self.release(); self.remote.mode = 'app-remains'
        with self.assertRaises(ValueError): self.session.cleanup()
        self.assertFalse((self.session.output/'cleanup/result.json').exists())

    def test_restarted_task_process_prevents_uninstall_and_cleanup_pass(self):
        self.armed(); self.release(); self.remote.mode = 'restarted-PID'
        with self.assertRaises(ValueError): self.session.cleanup()
        self.assertEqual([x[1][:3] for x in self.removals()],[['device','process','terminate']])
        self.assertTrue(self.remote.installed)

    def test_h04_collection_cannot_be_used_for_h10_acceptance(self):
        self.armed(); count = len(self.remote.calls)
        with self.assertRaises(ValueError): self.session.collect()
        self.assertEqual(len(self.remote.calls),count)

    def test_arm_cleanup_and_capture_prefix_are_single_consumption(self):
        self.armed(); self.session.retain_recorder()
        with self.assertRaises(ValueError): self.session.exchange('arm')
        with self.assertRaises(ValueError): self.session.retain_recorder()
        self.release(); self.session.cleanup()
        with self.assertRaises(ValueError): self.session.cleanup()


if __name__ == '__main__': unittest.main()
