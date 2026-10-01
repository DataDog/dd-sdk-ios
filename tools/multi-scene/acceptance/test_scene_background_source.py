"""Actual-return binding and ordering controls; all tool results are synthetic."""
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch
import uuid

from acceptance_common import Rejected
import operation_transport as t
import scene_background_source as source


class SourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve(); folder = self.root/'source'; folder.mkdir()
        run = str(uuid.uuid4()); now = int(time.time()*1000)
        self.identity = dict(schemaVersion=1,runID=run,processID=123,scenarioID=source.protocol.cycle.SCENARIO,
            profile=source.protocol.cycle.PROFILE,sourceRevision='a'*40,installedCodeSHA256='b'*64,
            challengeID=str(uuid.uuid4()),executionDeadlineMilliseconds=now+600000,cleanupDeadlineMilliseconds=now+900000)
        self.binding = dict(owner='/root',device='physical-device',udid='udid',bundle='task.bundle',pid=123,
            run_id=run,plan_sha256='c'*64,product_sha256='d'*64)
        self.subject = source.Source(folder,self.binding,self.identity,request_seconds=120,expected_sources=source.LOADED_SOURCES)

    def publish(self, path, actual, *, owner='/root', late=False):
        dispatch = self.subject.dispatch(path, '/root'); started = time.time()
        observation = dict(owner=owner,tool=dispatch['tool'],arguments=dispatch['arguments'],
                           started_at=started,finished_at=dispatch['deadline']+1 if late else time.time(),actual_return=actual)
        self.subject.publish(path, observation)
        return observation

    def start(self, *, qualified=True, actual=None):
        path = self.subject.issue('start')
        actual = actual or dict(structuredContent=dict(deviceIsSimulator=False,deviceUUID='physical-device',interactionSessionKey='actual-key'))
        self.publish(path,actual)
        if qualified: self.subject.accept_start()
        return path

    def test_actual_start_bound_without_native_or_gate_claim(self):
        path = self.start(); self.assertEqual(self.subject.key,'actual-key'); self.assertTrue(self.subject.start_qualified)
        self.assertEqual(t.load((path.parent/'tool-result.json').read_bytes())['structuredContent']['interactionSessionKey'],'actual-key')

    def test_capture_requires_qualified_start_even_when_key_was_returned(self):
        self.start(qualified=False)
        with self.assertRaises((ValueError,Rejected)): self.subject.issue('capture',inspection={})
        self.assertFalse((self.subject.folder/'capture-0').exists())

    def test_foreign_device_return_retained_but_not_accepted(self):
        actual = dict(structuredContent=dict(deviceIsSimulator=False,deviceUUID='other',interactionSessionKey='key'))
        self.start(qualified=False,actual=actual)
        with self.assertRaises((ValueError,Rejected)): self.subject.accept_start()
        self.assertTrue((self.subject.folder/'start/tool-result.json').is_file())

    def test_simulator_start_rejected(self):
        self.start(qualified=False,actual=dict(structuredContent=dict(deviceIsSimulator=True,deviceUUID='physical-device',interactionSessionKey='key')))
        with self.assertRaises((ValueError,Rejected)): self.subject.accept_start()

    def test_tool_error_and_late_result_preserved(self):
        path = self.subject.issue('start'); actual = dict(isError=True,content=[dict(type='text',text='failed actual call')])
        with self.assertRaises((ValueError,Rejected)): self.publish(path,actual,late=True)
        with self.assertRaises((ValueError,Rejected)): self.subject.accept_start()
        self.assertEqual(t.load((path.parent/'tool-result.json').read_bytes()),actual)

    def test_wrong_tool_owner_cannot_qualify_the_return(self):
        path = self.subject.issue('start')
        with self.assertRaises((ValueError,Rejected)):
            self.publish(path,dict(structuredContent=dict(deviceIsSimulator=False,deviceUUID='physical-device',interactionSessionKey='key')),owner='other')
        self.assertEqual(self.subject.resolved,{})
        self.assertIsNone(self.subject.key)
        self.assertTrue((path.parent/'tool-result.json').exists())
        with self.assertRaises((ValueError,Rejected)): self.subject.accept_start()

    def test_unresolved_dispatch_and_replaced_return_cannot_issue_capture(self):
        path = self.subject.issue('start'); self.subject.dispatch(path,'/root')
        with self.assertRaises((ValueError,Rejected)): self.subject.issue('capture',inspection={})

    def test_changed_published_start_invalidates_later_requests(self):
        path = self.start(); original = (path.parent/'tool-result.json').read_bytes()
        (path.parent/'tool-result.json').write_bytes(t.encode(dict(structuredContent={'old':'replacement'})))
        with self.assertRaises((ValueError,Rejected)): self.subject.issue('capture',inspection={})
        (path.parent/'tool-result.json').write_bytes(original)
        with self.assertRaises((ValueError,Rejected)): self.subject.issue('capture',inspection={})
        self.assertTrue(self.subject.failed)
        self.finish_end()

    def finish_end(self):
        path = self.subject.issue('end'); self.publish(path,dict(structuredContent=dict(userMessage='Session stopped')))
        completion = dict(owner='/root',pending_calls=0,input_commands=0,final_response=dict(
            path=str(path.parent/'response.json'),sha256=t.sha(self.subject.responses['end'])),at=time.time())
        return self.subject.accept_end(completion)

    def test_damaged_source_evidence_does_not_block_owned_end(self):
        path,_,_,_ = self.capture_return()
        (path.parent/'returned-screenshot.png').unlink()
        with self.assertRaises((ValueError,Rejected)): self.subject.accept_capture(path,'/decoder','e'*64)
        self.assertTrue(self.subject.failed)
        self.assertEqual(self.finish_end()['state'],'SUPPORTED_SOURCE_SESSION_STOPPED')
        self.assertEqual(self.subject.accepted,[])

    def test_renamed_failed_result_does_not_block_owned_end(self):
        path = self.start()
        self.subject.save(path.parent/'result.json',t.encode({'state':'synthetic component'}))
        self.subject.fail(path.parent,ValueError('failed evidence'))
        self.assertFalse((path.parent/'result.json').exists())
        self.assertTrue((path.parent/'invalidated-result.json').exists())
        self.finish_end()

    def test_start_publication_failure_retains_only_actual_owned_cleanup_key(self):
        path = self.subject.issue('start'); dispatch = self.subject.dispatch(path,'/root')
        observation = dict(owner='/root',tool=dispatch['tool'],arguments=dispatch['arguments'],started_at=time.time(),
            finished_at=time.time(),actual_return=dict(structuredContent=dict(deviceIsSimulator=False,
                deviceUUID='physical-device',interactionSessionKey='actual-key')))
        with patch.object(source.t,'save',side_effect=OSError('disk full')):
            with self.assertRaises(OSError): self.subject.publish(path,observation)
        self.assertEqual(self.subject.key,'actual-key'); self.assertFalse(self.subject.start_qualified)
        self.assertEqual(self.subject.resolved['start'],t.encode(observation))
        with self.assertRaises((ValueError,Rejected)): self.subject.issue('capture',inspection={})
        self.assertFalse(self.finish_end()['native_acceptance'])

    def test_foreign_start_publication_failure_never_acquires_cleanup_key(self):
        path = self.subject.issue('start'); dispatch = self.subject.dispatch(path,'/root')
        observation = dict(owner='foreign',tool=dispatch['tool'],arguments=dispatch['arguments'],started_at=time.time(),
            finished_at=time.time(),actual_return=dict(structuredContent=dict(deviceIsSimulator=False,
                deviceUUID='physical-device',interactionSessionKey='actual-key')))
        with patch.object(source.t,'save',side_effect=OSError('disk full')):
            with self.assertRaises(OSError): self.subject.publish(path,observation)
        self.assertIsNone(self.subject.key); self.assertEqual(self.subject.resolved,{})
        with self.assertRaises((ValueError,Rejected)): self.subject.issue('end')

    def changed_call(self,key,value):
        path = self.subject.issue('start'); dispatch = self.subject.dispatch(path,'/root')
        original = dict(owner='/root',tool=dispatch['tool'],arguments=dispatch['arguments'],started_at=time.time(),
            finished_at=time.time(),actual_return=dict(structuredContent=dict(deviceIsSimulator=False,
                deviceUUID='physical-device',interactionSessionKey='actual-key')))
        observation = dict(original); observation[key] = value
        with self.assertRaises((ValueError,Rejected)): self.subject.publish(path,observation)
        self.assertIsNone(self.subject.key); self.assertEqual(self.subject.resolved,{})

    def test_changed_tool_never_acquires_cleanup_key(self): self.changed_call('tool','foreign-tool')

    def test_changed_arguments_never_acquires_cleanup_key(self):
        self.changed_call('arguments',dict(deviceIdentifier='foreign'))

    def test_damaged_end_response_cannot_qualify_cleanup(self):
        self.start(); path = self.subject.issue('end'); self.publish(path,dict(structuredContent=dict(userMessage='Session stopped')))
        (path.parent/'tool-result.json').write_bytes(t.encode(dict(structuredContent=dict(userMessage='Session stopped',old=True))))
        completion = dict(owner='/root',pending_calls=0,input_commands=0,final_response=dict(
            path=str(path.parent/'response.json'),sha256=t.sha(self.subject.responses['end'])),at=time.time())
        with self.assertRaises((ValueError,Rejected)): self.subject.accept_end(completion)
        self.assertFalse(self.subject.ended)

    def test_unresolved_capture_blocks_end_even_after_evidence_failure(self):
        self.start()
        with patch.object(self.subject,'inspection',return_value=(dict(descriptor=dict(token='x'),owners={}),{})):
            path = self.subject.issue('capture',inspection={})
        self.subject.dispatch(path,'/root'); self.subject.failed = True
        with self.assertRaises((ValueError,Rejected)): self.subject.issue('end')

    def test_original_cleanup_cutoff_cannot_be_extended(self):
        self.start(); self.subject.cleanup += 60
        with self.assertRaises((ValueError,Rejected)): self.subject.issue('end')

    def test_cleanup_key_cannot_be_replaced(self):
        self.start(); self.subject.key = 'foreign-key'
        with self.assertRaises((ValueError,Rejected)): self.subject.issue('end')

    def test_execution_context_restore_does_not_clear_failure(self):
        self.start(); original = self.subject.execution; self.subject.execution += 60
        with self.assertRaises((ValueError,Rejected)): self.subject.issue('capture',inspection={})
        self.subject.execution = original
        with self.assertRaises((ValueError,Rejected)): self.subject.issue('capture',inspection={})
        self.finish_end()

    def test_replaced_request_restore_cannot_enable_dispatch(self):
        path=self.subject.issue('start'); original=path.read_bytes()
        path.write_bytes(t.encode({'replaced':'request'}))
        with self.assertRaises((ValueError,Rejected)): self.subject.dispatch(path,'/root')
        path.write_bytes(original)
        with self.assertRaises((ValueError,Rejected)): self.subject.dispatch(path,'/root')
        self.assertEqual(self.subject.claims,{})

    def test_inspected_reference_restore_cannot_enable_capture_dispatch(self):
        self.start(); ref=self.root/'inspected.json'; original=b'original inspection'; ref.write_bytes(original)
        checked=dict(descriptor=dict(token='x'),owners={})
        with patch.object(self.subject,'inspection',return_value=(checked,{str(ref):t.sha(original)})):
            path=self.subject.issue('capture',inspection={})
        ref.write_bytes(b'replaced inspection')
        with self.assertRaises((ValueError,Rejected)): self.subject.dispatch(path,'/root')
        ref.write_bytes(original)
        with self.assertRaises((ValueError,Rejected)): self.subject.dispatch(path,'/root')
        self.assertNotIn('capture-0',self.subject.claims)
        self.finish_end()

    def test_end_publication_rejoins_actual_end_and_completion_at_both_boundaries(self):
        for boundary in ['worker-completed.json','result.json']:
            for name in ['request.json','dispatch.json','observation.json','tool-result.json','response.json','worker-completed.json']:
                with self.subTest(boundary=boundary,changed=name):
                    self.setUp(); self.start(); path=self.subject.issue('end')
                    self.publish(path,dict(structuredContent=dict(userMessage='Session stopped')))
                    completion=dict(owner='/root',pending_calls=0,input_commands=0,final_response=dict(
                        path=str(path.parent/'response.json'),sha256=t.sha(self.subject.responses['end'])),at=time.time())
                    original_save=source.t.save
                    def mutate(target,raw):
                        original_save(target,raw)
                        if Path(target).name == boundary:
                            changed=self.subject.folder/name if name=='worker-completed.json' else path.parent/name
                            changed.write_bytes(b'changed after terminal save')
                    with patch.object(source.t,'save',side_effect=mutate):
                        with self.assertRaises((ValueError,Rejected)): self.subject.accept_end(completion)
                    self.assertFalse(self.subject.ended)

    def test_capture_requires_previous_acceptance_and_sends_no_input_or_activation(self):
        self.start(); checked = dict(descriptor=dict(token='token-0'),owners={'owners':'source-bound'})
        with patch.object(self.subject,'inspection',return_value=(checked,{})):
            path = self.subject.issue('capture',inspection={'synthetic':'unqualified'})
        request = t.load(path.read_bytes()); self.assertEqual(request['arguments'],dict(interactSessionKey='actual-key'))
        self.subject.dispatch(path,'/root'); self.subject.publish(path,dict(owner='/root',tool=source.TOOLS['capture'],
            arguments=request['arguments'],started_at=time.time(),finished_at=time.time(),actual_return=dict(structuredContent={})))
        with self.assertRaises((ValueError,Rejected)): self.subject.issue('capture',inspection={})

    def test_persistence_failure_is_sticky_and_preserves_issued_bytes(self):
        with patch.object(source.t,'save',side_effect=OSError('disk full')):
            with self.assertRaises(OSError): self.subject.issue('start')
        self.assertTrue(self.subject.failed); self.assertIn('start',self.subject.requests)
        with self.assertRaises((ValueError,Rejected)): self.subject.issue('start')

    def capture_return(self):
        self.start()
        checked = dict(descriptor=dict(token='token-0',payloads={'scene-A':'current-A'}),owners={'owners':'bound'})
        with patch.object(self.subject,'inspection',return_value=(checked,{})):
            path = self.subject.issue('capture',inspection={'phase_replies':[]})
        hierarchy = self.root/'actual-hierarchy.txt'; hierarchy.write_text(
            'Application bundle identifier: task.bundle\nApplication UI orientation: landscapeLeft\nApplication, pid: 123,\n')
        image = self.root/'actual.png'; image.write_bytes(b'\x89PNG\r\n\x1a\nactual synthetic pixels')
        self.publish(path,dict(structuredContent=dict(applicationState='NotRun',hierarchyPath=str(hierarchy),screenshotPath=str(image))))
        return path,checked,image,hierarchy

    def test_notrun_task_capture_joins_returned_artifacts_without_inventing_running(self):
        path,checked,image,hierarchy = self.capture_return()
        with patch.object(self.subject,'inspection_for_request',return_value=(checked,{})), \
             patch.object(source.media,'decode',return_value={'synthetic':'decoder proof'}), \
             patch.object(source.media,'checked',return_value=[{'synthetic':'frame'}]), \
             patch.object(source.display,'pixels',return_value={'synthetic':'marker match'}):
            result = self.subject.accept_capture(path,'/synthetic/decoder','e'*64)
        self.assertEqual(result['application_state'],'NotRun'); self.assertFalse(result['native_acceptance'])
        self.assertEqual((path.parent/'returned-screenshot.png').read_bytes(),image.read_bytes())
        self.assertEqual(len(self.subject.accepted),1)

    def test_substituted_frozen_image_invalidates_the_capture(self):
        path,checked,image,hierarchy = self.capture_return()
        (path.parent/'returned-screenshot.png').write_bytes(b'older replacement')
        with self.assertRaises((ValueError,Rejected)): self.subject.accept_capture(path,'/decoder','e'*64)
        self.assertTrue(self.subject.failed); self.assertEqual(self.subject.accepted,[])

    def test_wrong_task_pid_in_actual_hierarchy_rejects(self):
        self.start()
        checked = dict(descriptor=dict(token='token-0'),owners={'owners':'bound'})
        with patch.object(self.subject,'inspection',return_value=(checked,{})):
            path = self.subject.issue('capture',inspection={'phase_replies':[]})
        hierarchy = self.root/'foreign.txt'; hierarchy.write_text(
            'Application bundle identifier: task.bundle\nApplication UI orientation: landscapeLeft\nApplication, pid: 124,\n')
        image = self.root/'actual.png'; image.write_bytes(b'\x89PNG\r\n\x1a\nactual')
        self.publish(path,dict(structuredContent=dict(applicationState='NotRun',hierarchyPath=str(hierarchy),screenshotPath=str(image))))
        with self.assertRaises((ValueError,Rejected)): self.subject.accept_capture(path,'/decoder','e'*64)
        self.assertEqual(self.subject.accepted,[])

    def test_decoder_failure_preserves_actual_returned_artifacts(self):
        path,checked,image,hierarchy = self.capture_return()
        with patch.object(self.subject,'inspection_for_request',return_value=(checked,{})), \
             patch.object(source.media,'decode',side_effect=ValueError('decoder failed')):
            with self.assertRaises(ValueError): self.subject.accept_capture(path,'/decoder','e'*64)
        self.assertEqual((path.parent/'returned-screenshot.png').read_bytes(),image.read_bytes())
        self.assertTrue((path.parent/'tool-result.json').exists()); self.assertEqual(self.subject.accepted,[])

    def test_foreign_publication_failure_never_writes_outside_owned_source(self):
        outside = self.root/'outside'; outside.mkdir()
        with self.assertRaises((ValueError,Rejected)): self.subject.publish(outside/'request.json',{})
        self.assertEqual(list(outside.iterdir()),[]); self.assertTrue(self.subject.failed)

    def test_end_joins_actual_final_response_and_pending_zero(self):
        self.start(); path = self.subject.issue('end'); self.publish(path,dict(structuredContent=dict(userMessage='Session stopped')))
        completion = dict(owner='/root',pending_calls=0,input_commands=0,final_response=dict(
            path=str(path.parent/'response.json'),sha256=t.sha(self.subject.responses['end'])),at=time.time())
        result = self.subject.accept_end(completion)
        self.assertEqual(result['state'],'SUPPORTED_SOURCE_SESSION_STOPPED'); self.assertFalse(result['task_cleanup_authorized'])
        self.assertEqual(result['gates_closed'],[])

    def test_end_does_not_accept_start_reference_or_pending_work(self):
        self.start(); path = self.subject.issue('end'); self.publish(path,dict(structuredContent=dict(userMessage='Session stopped')))
        completion = dict(owner='/root',pending_calls=1,input_commands=0,final_response=self.subject.start_response,at=time.time())
        with self.assertRaises((ValueError,Rejected)): self.subject.accept_end(completion)
        self.assertFalse(self.subject.ended)


if __name__ == '__main__': unittest.main()
