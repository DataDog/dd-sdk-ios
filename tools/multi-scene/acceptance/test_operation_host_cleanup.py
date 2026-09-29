"""Offline host-cleanup controls. Devices, input and process outcomes are doubles."""
import base64
import copy
from pathlib import Path
import time
import unittest
from unittest.mock import patch

import operation_cleanup as c
import operation_transport as t
import test_operation_setup as setup_fixture
import test_operation_transport as wire_fixture


class Device(setup_fixture.Device):
    def __init__(self, source, *, mode=None):
        self.__dict__ = source.__dict__.copy()
        self.mode = mode; self.groups = []; self.alive = True; self.installed = True; self.captures = 0
        self.native_raw = b'{"state":"fixture-native-result"}'
        self.terminal = dict(schemaVersion=1, scenarioID=self.identity['setupProfile']['scenario'],
                            state='PASS', matchedExpectationCount=1, issues=[])
        self.process = dict(processIdentifier=123, executable='/private/Bundle/Fixture.app/Fixture')

    def recorded(self, raw, label, *, returncode=0):
        self.sequence += 1; self.groups.append(self.sequence)
        folder = self.output / (f'{self.sequence:05d}-' + label); folder.mkdir()
        data = t.encode(raw); (folder / 'response.json').write_bytes(data)
        receipt = dict(started_at=time.time(), finished_at=time.time(), deadline=self.deadline,
            returncode=returncode, before=[], remaining=[], quiescence_error=None, response_sha256=t.sha(data))
        if self.mode == 'late': receipt['finished_at'] = self.deadline
        if self.mode == 'unreaped': receipt['remaining'] = [77]
        if self.mode == 'response-hash': receipt['response_sha256'] = 'f'*64
        (folder / 'receipt.json').write_bytes(t.encode(receipt))
        if self.mode == 'substituted-return': raw = dict(raw, olderObservation=True)
        return raw, receipt

    def envelope(self, args, value):
        return dict(info=dict(outcome='success', commandType='devicectl.'+'.'.join(args[:3]),
            arguments=['devicectl', *args[:3], '--device', self.identifier, '--timeout', '28',
                       '--json-output', '/fixture/response.json', *args[3:]]), result=value)

    def command(self, args, label, deadline, *, check=True):
        self.deadline = deadline; self.calls.append(('command', label))
        if args[:3] == ['device', 'info', 'processes']:
            rows = [copy.deepcopy(self.process)] if self.alive else []
            if self.mode == 'missing-process': rows = []
            if self.mode == 'duplicate-process': rows *= 2
            if self.mode == 'replaced-process' and label == 'cleanup-process-final': rows[0]['executable'] = '/new/Fixture.app/Fixture'
            if self.mode == 'process-remains' and not self.alive: rows = [copy.deepcopy(self.process)]
            if self.mode == 'restarted-process' and not self.alive: rows = [dict(self.process, processIdentifier=999)]
            if self.mode == 'malformed-absence' and not self.alive: rows = [{}]
            value = dict(deviceIdentifier=self.identifier, runningProcesses=rows)
        elif args[:3] == ['device', 'process', 'terminate']:
            if self.mode != 'terminate-error': self.alive = False
            value = dict(deviceIdentifier=self.identifier, process=copy.deepcopy(self.process), signal=dict(name='SIGTERM',value=15))
            if self.mode == 'wrong-terminated-pid': value['process']['processIdentifier'] = 999
        elif args[:3] == ['device', 'uninstall', 'app']:
            self.installed = self.mode in ['uninstall-error', 'app-remains']
            value = dict(deviceIdentifier=self.identifier, uninstalledApplications=[dict(bundleID='test.bundle')])
            if self.mode == 'wrong-uninstalled-bundle': value['uninstalledApplications'][0]['bundleID'] = 'other.bundle'
        elif args[:3] == ['device', 'info', 'apps']:
            value = dict(deviceIdentifier=self.identifier, matchingBundleIdentifier='test.bundle', apps=[{}] if self.installed else [])
        elif args[:3] == ['device', 'info', 'files']:
            raw = self.envelope(args, {}); raw['info']['outcome'] = 'failed'
            raw.update(errorSignature='(CoreDevice.ActionError 3)', error=dict(code=3,domain='CoreDevice.ActionError'))
            return self.recorded(raw, label, returncode=1)
        else: raise AssertionError(args)
        raw = self.envelope(args, value)
        if self.mode == 'foreign-device': raw['info']['arguments'][5] = 'foreign'
        if self.mode == 'foreign-command': raw['info']['commandType'] = 'devicectl.device.info.apps'
        if self.mode == 'wrong-arguments': raw['info']['arguments'] += ['unexpected']
        failed = (self.mode == 'terminate-error' and label == 'cleanup-terminate') or (self.mode == 'uninstall-error' and label == 'cleanup-uninstall')
        if failed: raw['info']['outcome'] = 'failed'
        return self.recorded(raw, label, returncode=1 if failed else 0)

    def push(self, bundle, source, destination, label, deadline):
        self.deadline = deadline; self.calls.append(('push', destination)); self.files[destination] = Path(source).read_bytes()
        if destination.endswith('request'):
            fingerprint = self.files[destination].decode(); request = self.files[destination+'-'+fingerprint+'.json']
            self.publish_cleanup(request, fingerprint, deadline)
        raw, _ = self.result('to', bundle, source, destination)
        return self.recorded(raw, label)

    def publish_cleanup(self, request, fingerprint, deadline):
        self.captures += 1; prefix='Documents/'+self.identity['runID']+'.operations-'
        reply = t.load(wire_fixture.reply(self.identity, request)); capture=t.load(base64.b64decode(reply['capture']))
        capture.update(before=copy.deepcopy(self.snapshot), after=copy.deepcopy(self.snapshot)); capture.pop('idleFailure')
        if self.mode == 'held-input': capture['idleFailure'] = 'input held'
        if self.mode == 'owner-replaced':
            for side in ['before','after']: capture[side]['input'][0]['rootIdentity'] = 'different-root'
        reply['capture'] = base64.b64encode(t.encode(capture)).decode(); returned=t.encode(reply)
        self.files[prefix+'response-'+fingerprint+'.json'] = returned
        context=t.load(wire_fixture.context_reply(self.identity,request,returned,deadline))
        sample=dict(sampledAt=time.time(), before=copy.deepcopy(capture['before']), after=copy.deepcopy(capture['after']), reads=[])
        if self.mode == 'context-input-change': sample['after']['input'][0]['generation'] += 1
        for name in ['sdkBefore','sdkAfter']:
            raw=t.encode(sample); context['components'][name]=base64.b64encode(raw).decode();context['componentSHA256'][name]=t.sha(raw)
        context_raw=t.encode(context); completed=wire_fixture.context_completion(self.identity,request,returned,context_raw,deadline)
        self.files[prefix+'context-'+fingerprint+'.json']=context_raw
        self.files[prefix+'context-'+fingerprint+'-result.json']=completed
        pending=(self.captures==1 and self.mode!='already-stopped') or self.mode=='never-stops'
        receipt=dict(schemaVersion=1,identity=self.identity,requestSHA256=fingerprint,replySHA256=t.sha(returned),
            captureSHA256=t.sha(base64.b64decode(reply['capture'])),contextCompletionSHA256=t.sha(completed),
            driver=dict(requested=True,stopped=not pending),
            state='NOT_STOPPED' if pending else 'STOPPED',pumpStopped=not pending,deadline=deadline,finishedAt=deadline-.1)
        if self.native_raw is not None: receipt['nativeLocalResultSHA256']=t.sha(self.native_raw)
        if self.terminal is not None: receipt['driver']['terminalBeforeStop']=copy.deepcopy(self.terminal)
        if not pending:
            status=t.encode(dict(identity=self.identity,sequence=3,state='STOPPED_FOR_CLEANUP',requestSHA256=fingerprint,
                deadline=deadline,observedAt=deadline-.2));receipt.update(pumpStopStatus=base64.b64encode(status).decode(),pumpStopStatusSHA256=t.sha(status))
        if self.mode == 'pending-wrong-request' and pending: receipt['requestSHA256']='f'*64
        if self.mode == 'pending-missing-driver' and pending: receipt['driver']=None
        if self.mode == 'pending-with-stop-status' and pending: receipt['pumpStopStatus']='fake'
        if self.mode == 'pending-extended' and pending: receipt['deadline'] += 1
        if self.mode == 'pending-terminal-foreign' and pending: receipt['driver']['terminalBeforeStop']['scenarioID']='foreign'
        if self.mode == 'changed-native-result': self.files[prefix+'native-local-result.json']=b'changed'
        elif self.native_raw is not None: self.files[prefix+'native-local-result.json']=self.native_raw
        if self.mode == 'changed-terminal': receipt['driver']['terminalBeforeStop']['state']='FAIL'
        if self.mode == 'missing-stop-proof': return
        self.files[prefix+'cleanup-'+fingerprint+'-driver.json']=t.encode(receipt)

    def pull(self,bundle,source,destination,label,deadline,*,check):
        self.deadline=deadline;self.calls.append(('pull',source));missing=source not in self.files
        if not missing: Path(destination).write_bytes(self.files[source])
        raw,_=self.result('from',bundle,source,destination,missing)
        return self.recorded(raw,label,returncode=1 if missing else 0)

    def quiescent(self,deadline):
        residue=[77] if self.mode=='host-child' else []
        value=dict(state='INVALID' if residue else 'PASS',groups=self.groups,remaining=residue,at=time.time(),deadline=deadline)
        t.save(self.output/'before-cleanup-quiescence.json',t.encode(value))


class CleanupHostTests(unittest.TestCase):
    def fixture(self, mode=None, *, absent=False):
        host=setup_fixture.HostSetupTests();host.setUp();self.addCleanup(host.doCleanups);host.collect()
        remote=Device(host.remote,mode=mode);host.setup.remote=remote;host.channel.remote=remote
        if absent: remote.native_raw=None;remote.terminal=None
        cleanup=c.Cleanup(host.setup,original_native_raw=remote.native_raw,original_terminal=remote.terminal,
            wait=lambda:None if mode!='missing-stop-proof' else (_ for _ in ()).throw(ValueError('bounded fixture wait')))
        request=t.load(cleanup.request_raw)
        ack=t.encode(dict(kind='OPERATOR_RELEASED',request_id=request['request_id'],run_id=request['run_id'],
            request_sha256=t.sha(cleanup.request_raw),at=time.time(),user_message='Released'))
        return cleanup,remote,ack

    def no_mutations(self,remote):
        self.assertFalse(any(x[0]=='command' and x[1] in ['cleanup-terminate','cleanup-uninstall'] for x in remote.calls))

    def test_pending_then_stopped_preserves_results_and_removes_only_task(self):
        cleanup,remote,ack=self.fixture();ready=cleanup._collect(ack)
        self.assertEqual(remote.captures,2);self.assertEqual(ready['state'],'CLEANUP_READY');self.no_mutations(remote)
        original=(cleanup.folder/'original-native-result.json').read_bytes()
        result=cleanup._remove();self.assertEqual(result['state'],'TASK_APP_REMOVED')
        self.assertEqual(result['containerAbsence'],'UNVERIFIED');self.assertFalse(result['releaseAcceptance'])
        self.assertEqual((cleanup.folder/'original-native-result.json').read_bytes(),original)
        self.assertEqual(result['scenario'],result['evidence']);self.assertEqual(result['scenario'],'UNCHANGED')
        self.assertTrue((cleanup.folder/'teardown-admission.json').is_file())

    def test_explicit_absence_of_both_prior_results_is_preserved(self):
        cleanup,remote,ack=self.fixture(absent=True)
        result=cleanup.run(ack)
        self.assertEqual(result['state'],'TASK_APP_REMOVED')
        definition=t.load((cleanup.folder/'definition.json').read_bytes())
        for key in ['originalNativeResult','originalTerminal']:self.assertEqual(definition[key],dict(present=False,sha256=None))

    def test_late_or_missing_native_result_and_terminal_reject_before_removal(self):
        for which in ['native','terminal']:
            for absent in [True,False]:
                with self.subTest(which=which,expected_absent=absent):
                    cleanup,remote,ack=self.fixture(absent=absent)
                    if which=='native':remote.native_raw=b'{"state":"late"}' if absent else None
                    else:remote.terminal=dict(schemaVersion=1,scenarioID=remote.identity['setupProfile']['scenario'],state='PASS',matchedExpectationCount=1,issues=[]) if absent else None
                    with self.assertRaises(ValueError):cleanup.run(ack)
                    self.no_mutations(remote)

    def test_public_run_keeps_idle_capture_and_removal_in_one_call(self):
        cleanup,remote,ack=self.fixture('already-stopped')
        result=cleanup.run(ack)
        self.assertEqual(result['state'],'TASK_APP_REMOVED');self.assertEqual(remote.captures,1)
        with self.assertRaises(ValueError):cleanup.run(ack)

    def test_changed_capture_or_release_bytes_cannot_authorize_removal(self):
        for relative in ['release-ack.json','channel/0002-cleanup/capture.json']:
            with self.subTest(path=relative):
                cleanup,remote,ack=self.fixture();cleanup._collect(ack)
                (cleanup.folder/relative).write_bytes(b'{}')
                with self.assertRaises(ValueError):cleanup._remove()
                self.no_mutations(remote)

    def test_setup_release_cannot_substitute_for_new_cleanup_release(self):
        cleanup,remote,_=self.fixture()
        with self.assertRaises(Exception): cleanup._collect((cleanup.host.folder/'release-ack.json').read_bytes())
        self.no_mutations(remote);self.assertEqual(remote.captures,0)

    def test_wrong_stale_empty_and_foreign_release_reject_before_capture(self):
        for field,value in [('run_id','other'),('request_sha256','f'*64),('at',0),('user_message','')]:
            with self.subTest(field=field):
                cleanup,remote,raw=self.fixture();ack=t.load(raw);ack[field]=value
                with self.assertRaises(Exception): cleanup._collect(t.encode(ack))
                self.no_mutations(remote);self.assertEqual(remote.captures,0)

    def test_pending_receipt_never_becomes_teardown_authority(self):
        for mode in ['never-stops','pending-wrong-request','pending-missing-driver','pending-with-stop-status','pending-extended','pending-terminal-foreign']:
            with self.subTest(mode=mode):
                cleanup,remote,ack=self.fixture(mode)
                with self.assertRaises(Exception): cleanup._collect(ack)
                with self.assertRaises(ValueError): cleanup._remove()
                self.no_mutations(remote);self.assertLessEqual(remote.captures,2)

    def test_missing_stop_proof_cannot_turn_elapsed_wait_into_success(self):
        cleanup,remote,ack=self.fixture('missing-stop-proof')
        with self.assertRaises(ValueError): cleanup._collect(ack)
        self.no_mutations(remote);self.assertFalse((cleanup.folder/'ready.json').exists())

    def test_held_replaced_or_changed_input_blocks_cleanup(self):
        for mode in ['held-input','owner-replaced','context-input-change']:
            with self.subTest(mode=mode):
                cleanup,remote,ack=self.fixture(mode)
                with self.assertRaises(ValueError): cleanup._collect(ack)
                self.no_mutations(remote)

    def test_completed_native_result_and_prior_terminal_cannot_change(self):
        for mode in ['changed-native-result','changed-terminal']:
            with self.subTest(mode=mode):
                cleanup,remote,ack=self.fixture(mode)
                with self.assertRaises(ValueError): cleanup._collect(ack)
                self.no_mutations(remote)

    def test_missing_or_duplicate_process_stops_before_capture(self):
        for mode in ['missing-process','duplicate-process']:
            with self.subTest(mode=mode):
                cleanup,remote,ack=self.fixture(mode)
                with self.assertRaises(ValueError): cleanup._collect(ack)
                self.no_mutations(remote);self.assertEqual(remote.captures,0)

    def test_substituted_late_foreign_or_unreaped_observations_reject(self):
        for mode in ['late','unreaped','response-hash','substituted-return','foreign-device','foreign-command','wrong-arguments']:
            with self.subTest(mode=mode):
                cleanup,remote,ack=self.fixture(mode)
                with self.assertRaises(ValueError): cleanup._collect(ack)
                self.no_mutations(remote)

    def test_replaced_pid_or_live_host_child_blocks_termination(self):
        for mode in ['replaced-process','host-child']:
            with self.subTest(mode=mode):
                cleanup,remote,ack=self.fixture(mode);cleanup._collect(ack)
                with self.assertRaises(ValueError): cleanup._remove()
                self.no_mutations(remote)

    def test_termination_failure_or_remaining_process_prevents_uninstall(self):
        for mode in ['terminate-error','wrong-terminated-pid','process-remains','restarted-process','malformed-absence']:
            with self.subTest(mode=mode):
                cleanup,remote,ack=self.fixture(mode);cleanup._collect(ack)
                with self.assertRaises(ValueError): cleanup._remove()
                self.assertNotIn(('command','cleanup-uninstall'),remote.calls)
                self.assertTrue((cleanup.folder/'removal-failure.json').is_file())

    def test_uninstall_failure_wrong_bundle_or_remaining_app_stays_partial(self):
        for mode in ['uninstall-error','wrong-uninstalled-bundle','app-remains']:
            with self.subTest(mode=mode):
                cleanup,remote,ack=self.fixture(mode);cleanup._collect(ack)
                with self.assertRaises(ValueError): cleanup._remove()
                self.assertFalse((cleanup.folder/'result.json').exists())
                self.assertTrue((cleanup.folder/'removal-failure.json').is_file())

    def test_reentry_cannot_repeat_release_or_removal(self):
        cleanup,remote,ack=self.fixture();cleanup._collect(ack);cleanup._remove();before=len(remote.calls)
        with self.assertRaises(ValueError): cleanup._collect(ack)
        with self.assertRaises(ValueError): cleanup._remove()
        self.assertEqual(len(remote.calls),before)

    def test_changed_ready_receipt_cannot_authorize_removal(self):
        cleanup,remote,ack=self.fixture();cleanup._collect(ack);(cleanup.folder/'ready.json').write_bytes(b'{}')
        with self.assertRaises(ValueError): cleanup._remove()
        self.no_mutations(remote)

    def test_original_deadline_cannot_be_extended_or_expired(self):
        for mode in ['extended','expired']:
            with self.subTest(mode=mode):
                cleanup,remote,ack=self.fixture()
                if mode=='extended': cleanup.host.channel.deadline+=1
                with patch.object(c.time,'time',return_value=cleanup.deadline+1 if mode=='expired' else time.time()):
                    with self.assertRaises(ValueError): cleanup._collect(ack)
                self.no_mutations(remote)


if __name__ == '__main__': unittest.main()
