"""Fabricated cleanup transport controls; no device or teardown authority."""
import base64
import copy
import time
import unittest

import operation_transport as t
import test_operation_transport as fixtures


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.identity, _ = fixtures.OperationSetupTransportTests().fixture()
        self.request, self.inner = t.message(self.identity, 'cleanup')
        self.reply = fixtures.reply(self.identity, self.request)
        self.deadline = time.time() + 60
        self.context = fixtures.context_reply(self.identity, self.request, self.reply, self.deadline)
        self.completion = fixtures.context_completion(self.identity, self.request, self.reply, self.context, self.deadline)
        self.args = dict(context_raw=self.context, completion_raw=self.completion, reply_raw=self.reply,
            request_raw=self.request, input_raw=self.inner, identity=self.identity, deadline=self.deadline)
        self.status = dict(identity=self.identity, sequence=3, state='STOPPED_FOR_CLEANUP',
            requestSHA256=t.sha(self.request), deadline=self.deadline, observedAt=self.deadline-.2)
        self.receipt = dict(schemaVersion=1, identity=self.identity, requestSHA256=t.sha(self.request),
            replySHA256=t.sha(self.reply), captureSHA256=t.sha(base64.b64decode(t.load(self.reply)['capture'])),
            contextCompletionSHA256=t.sha(self.completion), driver=dict(requested=True, stopped=True),
            state='STOPPED', pumpStopped=True, deadline=self.deadline, finishedAt=self.deadline-.1)
        self.put_status(self.receipt, self.status)

    @staticmethod
    def put_status(receipt, status):
        raw = t.encode(status)
        receipt.update(pumpStopStatus=base64.b64encode(raw).decode(), pumpStopStatusSHA256=t.sha(raw))

    def test_actual_byte_join_still_leaves_release_idle_and_teardown_pending(self):
        raw = t.encode(self.receipt); result = t.cleanup_response(raw, **self.args)
        self.assertEqual(result['receiptSHA256'], t.sha(raw)); self.assertFalse(result['teardownAuthorized'])
        for field in ['release', 'idle', 'processAbsence']: self.assertEqual(result[field], 'PENDING')

    def test_absent_pending_running_and_incomplete_receipts_reject(self):
        for field, value in [('state','NOT_STOPPED'), ('pumpStopped',False), ('driver',None),
                ('driver',dict(requested=True,stopped=False)), ('driver',dict(requested=False,stopped=True))]:
            changed = copy.deepcopy(self.receipt); changed[field] = value
            with self.subTest(field=field,value=value), self.assertRaises(ValueError):
                t.cleanup_response(t.encode(changed), **self.args)
        for field in self.receipt:
            changed=copy.deepcopy(self.receipt); del changed[field]
            with self.subTest(missing=field), self.assertRaises(ValueError): t.cleanup_response(t.encode(changed),**self.args)

    def test_wrong_request_reply_capture_completion_or_identity_rejects(self):
        for field in ['requestSHA256','replySHA256','captureSHA256','contextCompletionSHA256','identity']:
            changed=copy.deepcopy(self.receipt)
            if field=='identity': changed[field]['processID'] += 1
            else: changed[field]='f'*64
            with self.subTest(field=field), self.assertRaises(ValueError): t.cleanup_response(t.encode(changed),**self.args)

    def test_native_result_reference_preserves_exact_original_bytes(self):
        raw=b'{"state":"LOCAL_OWNERS_VERIFIED"}'
        self.receipt['nativeLocalResultSHA256']=t.sha(raw)
        t.cleanup_response(t.encode(self.receipt),native_local_raw=raw,**self.args)
        for observed in [None,b'changed']:
            with self.subTest(observed=observed), self.assertRaises(ValueError):
                t.cleanup_response(t.encode(self.receipt),native_local_raw=observed,**self.args)
        del self.receipt['nativeLocalResultSHA256']
        with self.assertRaises(ValueError): t.cleanup_response(t.encode(self.receipt),native_local_raw=raw,**self.args)

    def test_foreign_terminal_before_stop_rejects_without_reinterpreting_its_state(self):
        terminal=dict(schemaVersion=1,scenarioID=self.identity['setupProfile']['scenario'],state='FAIL',matchedExpectationCount=0,issues=[])
        self.receipt['driver']['terminalBeforeStop']=terminal
        result=t.cleanup_response(t.encode(self.receipt),**self.args)
        self.assertEqual(result['receipt']['driver']['terminalBeforeStop'],terminal)
        terminal['scenarioID']='foreign'
        with self.assertRaises(ValueError): t.cleanup_response(t.encode(self.receipt),**self.args)

    def test_deadline_extension_late_and_reordered_stop_reject(self):
        for field,value in [('deadline',self.deadline+1),('finishedAt',self.deadline),('finishedAt',self.deadline-1),
                            ('finishedAt',True),('pumpStopped',1),('schemaVersion',True)]:
            changed=copy.deepcopy(self.receipt);changed[field]=value
            with self.subTest(field=field,value=value), self.assertRaises(ValueError): t.cleanup_response(t.encode(changed),**self.args)

    def test_pump_status_identity_sequence_state_and_byte_substitution_reject(self):
        for field,value in [('state','CONTEXT_PUBLISHED'),('sequence',2),('requestSHA256','f'*64),
                            ('observedAt',self.deadline),('deadline',self.deadline+1)]:
            status=copy.deepcopy(self.status);status[field]=value
            changed=copy.deepcopy(self.receipt);self.put_status(changed,status)
            with self.subTest(field=field), self.assertRaises(ValueError): t.cleanup_response(t.encode(changed),**self.args)
        self.receipt['pumpStopStatusSHA256']='f'*64
        with self.assertRaises(ValueError): t.cleanup_response(t.encode(self.receipt),**self.args)

    def test_setup_request_cannot_substitute_for_cleanup(self):
        request,inner=t.message(self.identity,'setup');reply=fixtures.reply(self.identity,request)
        context=fixtures.context_reply(self.identity,request,reply,self.deadline)
        completion=fixtures.context_completion(self.identity,request,reply,context,self.deadline)
        with self.assertRaises(ValueError):
            t.cleanup_response(t.encode(self.receipt),context_raw=context,completion_raw=completion,
                reply_raw=reply,request_raw=request,input_raw=inner,identity=self.identity,deadline=self.deadline)


if __name__ == '__main__': unittest.main()
