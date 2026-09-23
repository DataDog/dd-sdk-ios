"""Controls for bounded collection; SDK expectations remain in rum_suite.py."""
import copy
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import rum_suite_execution as suite


class CollectionTests(unittest.TestCase):
    def test_empty_reaped_group_needs_one_actual_inventory(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);workers=[];deadline=time.time()+5
            suite.command([sys.executable,'-c','print("complete")'],root,'attempt',deadline=deadline,
                          cleanup_limit=deadline+30,workers=workers)
            receipt=suite.shared.read(root/'attempt-receipt.json')
            self.assertEqual(receipt['returncode'],0);self.assertIsNone(receipt['cleanup_failure'])
            self.assertEqual(receipt['quiescence']['inventories'],1)
            self.assertEqual(receipt['quiescence']['remaining'],[])
            self.assertEqual(workers[0]['quiescence'],receipt['quiescence'])
            self.assertTrue((root/'attempt-quiescence/inventory-1.stdout').read_text().strip())

    def test_timeout_reaps_child_and_preserves_original_deadline(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);deadline=time.time()+.05
            with self.assertRaises(subprocess.TimeoutExpired):
                suite.command([sys.executable,'-c','import time;time.sleep(20)'],root,'attempt',
                              deadline=deadline,cleanup_limit=deadline+30)
            receipt=suite.shared.read(root/'attempt-receipt.json')
            self.assertIn('TimeoutExpired',receipt['failure']);self.assertEqual(receipt['deadline'],deadline)
            self.assertEqual(receipt['cleanup_deadline'],deadline+30)
            self.assertEqual(receipt['quiescence']['state'],'PASS')

    def test_nonzero_exit_is_not_repaired_by_successful_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);deadline=time.time()+5
            with self.assertRaises(ValueError):
                suite.command([sys.executable,'-c','raise SystemExit(3)'],root,'attempt',
                              deadline=deadline,cleanup_limit=deadline+30)
            receipt=suite.shared.read(root/'attempt-receipt.json')
            self.assertEqual(receipt['returncode'],3);self.assertIsNotNone(receipt['failure'])
            self.assertEqual(receipt['quiescence']['state'],'PASS')

    def test_inventory_timeout_keeps_actual_partial_bytes_and_budget(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            failure=subprocess.TimeoutExpired(['ps'],15,output=b'7 7\n',stderr=b'partial')
            with patch.object(suite.subprocess,'run',side_effect=failure) as reader,patch.object(suite.time,'time',return_value=100):
                with self.assertRaises(subprocess.TimeoutExpired):suite.inventory(7,root,1,140)
            self.assertEqual(reader.call_args.kwargs['timeout'],15)
            self.assertEqual((root/'inventory-1.stdout').read_bytes(),b'7 7\n')
            receipt=suite.shared.read(root/'inventory-1.json')
            self.assertEqual(receipt['deadline'],140);self.assertIn('TimeoutExpired',receipt['failure'])

    def test_late_inventory_is_invalid_even_when_empty_owned_group(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);response=subprocess.CompletedProcess(['ps'],0,'1 1\n','')
            with patch.object(suite.subprocess,'run',return_value=response),patch.object(suite.time,'time',side_effect=[100,102,102]):
                with self.assertRaisesRegex(ValueError,'late'):suite.inventory(7,root,1,101)
            receipt=suite.shared.read(root/'inventory-1.json')
            self.assertEqual(receipt['returncode'],0);self.assertIsNotNone(receipt['failure'])
            self.assertEqual((root/'inventory-1.stdout').read_text(),'1 1\n')

    def test_invalid_inventory_never_signals_a_group(self):
        for output in ['', '7 7 extra\n', '7 -7\n', '7 7\n7 8\n', 'garbage\n']:
            with self.subTest(output=output),tempfile.TemporaryDirectory() as tmp:
                response=subprocess.CompletedProcess(['ps'],0,output,'')
                with patch.object(suite.subprocess,'run',return_value=response),patch.object(suite.os,'killpg') as kill:
                    with self.assertRaises(ValueError):suite.quiesce(987654,Path(tmp)/'q',time.time()+30)
                kill.assert_not_called()

    def test_system_zero_group_is_not_a_malformed_owned_process(self):
        with tempfile.TemporaryDirectory() as tmp:
            response=subprocess.CompletedProcess(['ps'],0,'0 0\n1 0\n7 7\n8 9\n','')
            with patch.object(suite.subprocess,'run',return_value=response):
                self.assertEqual(suite.inventory(7,Path(tmp),1,time.time()+30),[7])

    def test_current_and_unscoped_groups_are_refused(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(suite.os,'killpg') as kill:
            for group in [0,1,os.getpgrp()]:
                with self.subTest(group=group),self.assertRaises(ValueError):
                    suite.quiesce(group,Path(tmp)/str(group),time.time()+30)
            kill.assert_not_called()

    def test_remaining_descendant_uses_only_its_owned_group(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(suite,'inventory',side_effect=[[987655],[]]) as reader,patch.object(suite.os,'killpg') as kill:
                result=suite.quiesce(987654,Path(tmp)/'q',time.time()+30)
            kill.assert_called_once_with(987654,signal.SIGTERM)
            self.assertEqual(result['state'],'PASS');self.assertEqual(reader.call_count,2)

    def test_failed_command_inventory_requires_separate_restoration(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);workers=[];deadline=time.time()+5
            with patch.object(suite,'quiesce',side_effect=ValueError('reader failed')):
                with self.assertRaisesRegex(ValueError,'reader failed'):
                    suite.command([sys.executable,'-c','pass'],root,'attempt',deadline=deadline,
                                  cleanup_limit=deadline+30,workers=workers)
            before=(root/'attempt-receipt.json').read_bytes()
            receipt=json.loads(before);self.assertEqual(receipt['returncode'],0)
            self.assertIsNotNone(receipt['cleanup_failure']);self.assertNotIn('quiescence',workers[0])
            with patch.object(suite,'quiesce',return_value={'state':'INVALID','remaining':[7]}):
                with self.assertRaisesRegex(ValueError,'defer simulator teardown'):
                    suite.ensure_quiescent(workers,root,deadline+30)
            self.assertEqual((root/'attempt-receipt.json').read_bytes(),before)

    def test_later_restoration_does_not_rewrite_failed_command(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);old={'failure':'original timeout'};suite.shared.save(root/'attempt-receipt.json',old)
            with patch.object(suite,'quiesce',return_value={'state':'PASS','remaining':[]}) as clean:
                suite.ensure_quiescent([{'name':'attempt','pid':987654}],root,123)
            clean.assert_called_once_with(987654,root/'attempt-restoration-quiescence',123)
            self.assertEqual(suite.shared.read(root/'attempt-receipt.json'),old)

    def test_command_output_collision_does_not_start_native_process(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'attempt.log').write_text('preserve')
            with patch.object(suite.subprocess,'Popen') as launch:
                with self.assertRaises(FileExistsError):
                    suite.command(['unused'],root,'attempt',deadline=time.time()+5,cleanup_limit=time.time()+35)
            launch.assert_not_called();self.assertEqual((root/'attempt.log').read_text(),'preserve')

    def test_expired_command_does_not_start_native_process(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(suite.subprocess,'Popen') as launch:
            with self.assertRaises(ValueError):
                suite.command(['unused'],Path(tmp),'attempt',deadline=time.time()-1,cleanup_limit=time.time()+5)
            launch.assert_not_called()


class AdmissionTests(unittest.TestCase):
    def test_result_extraction_is_read_only_and_requires_timely_native_quiescence(self):
        for corruption in [None,'nonzero','cleanup','no-proof','late','terminated','not-started','missing','foreign','stale']:
            with self.subTest(corruption=corruption),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);deadline=time.time()+30
                receipt=dict(returncode=0,cleanup_failure=None,quiescence=dict(state='PASS'),finished_at=time.time())
                if corruption=='nonzero':receipt['returncode']=65
                elif corruption=='cleanup':receipt['cleanup_failure']='timeout'
                elif corruption=='no-proof':receipt['quiescence']=None
                elif corruption=='late':receipt['finished_at']=deadline
                elif corruption=='terminated':receipt['returncode']=-15
                elif corruption=='not-started':receipt['returncode']=None
                suite.shared.save(root/'execute-receipt.json',receipt)
                admission=dict(at=time.time(),deadline=deadline,result_bundle=str(root/'result.xcresult'))
                if corruption=='foreign':admission['result_bundle']='foreign'
                if corruption=='stale':admission['at']=deadline
                suite.shared.save(root/'execution-admission.json',admission)
                if corruption!='missing':(root/'result.xcresult').mkdir()
                with patch.object(suite,'command') as call:
                    if corruption in [None,'nonzero']:
                        suite.collect_results(root,deadline,call)
                        self.assertEqual(call.call_count,2)
                        for invocation in call.call_args_list:
                            self.assertEqual(invocation.args[0][:4],['xcrun','xcresulttool','get','test-results'])
                            self.assertEqual(invocation.args[2],deadline)
                    else:
                        with self.assertRaises(ValueError):suite.collect_results(root,deadline,call)
                        call.assert_not_called()

    def test_enumeration_reuse_needs_exact_runtime_and_timely_complete_receipt(self):
        case='DatadogRUMTests/Fixture/testCase()';expected={'deviceId':'selected'}
        base={
            'runtime-27.0/enumerate-receipt.json':dict(returncode=0,failure=None,finished_at=99,deadline=100,pid=7),
            'runtime-27.0/environment.json':dict(expected_result_device=expected),
            'later-quiescence.json':dict(state='PASS',remaining=[],groups=[7]),
            'runtime-27.0/enumeration.json':dict(errors=[],values=[dict(enabledTests=[dict(identifier=case)])]),
            'runtime-27.0/summary.json':dict(overall='INVALID')}
        for corruption in [None,'late','nonzero','failure','runtime','group','remaining','quiescence']:
            with self.subTest(corruption=corruption),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);(root/'runtime-27.0').mkdir();values=copy.deepcopy(base)
                receipt=values['runtime-27.0/enumerate-receipt.json'];later=values['later-quiescence.json']
                if corruption=='late':receipt['finished_at']=100
                elif corruption=='nonzero':receipt['returncode']=1
                elif corruption=='failure':receipt['failure']='exception'
                elif corruption=='runtime':values['runtime-27.0/environment.json']['expected_result_device']={}
                elif corruption=='group':later['groups']=[8]
                elif corruption=='remaining':later['remaining']=[7]
                elif corruption=='quiescence':later['state']='INVALID'
                for name,value in values.items():suite.shared.save(root/name,value)
                before=(root/'runtime-27.0/summary.json').read_bytes()
                if corruption is None:self.assertEqual(suite.enumeration_reuse(root,expected),[case])
                else:
                    with self.assertRaises(ValueError):suite.enumeration_reuse(root,expected)
                self.assertEqual((root/'runtime-27.0/summary.json').read_bytes(),before)

    def test_runtime_is_single_use_and_needs_full_original_stage_reservation(self):
        for corruption in ['consumed','expired','short-reservation','prior-failed']:
            with self.subTest(corruption=corruption),tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);suite.shared.save(root/'plan.json',{});suite.shared.save(root/'review.json',{})
                deadline=time.time()+ (2000 if corruption=='consumed' else -1 if corruption=='expired' else 100)
                suite.shared.save(root/'stage.json',dict(deadline=deadline,plan_sha256=suite.shared.sha(root/'plan.json'),
                                                        review_sha256=suite.shared.sha(root/'review.json')))
                if corruption=='consumed':(root/'runtime-27.0').mkdir()
                if corruption=='prior-failed':
                    (root/'runtime-27.0').mkdir();suite.shared.save(root/'runtime-27.0/summary.json',dict(overall='INVALID'))
                definition=dict(build_root='unused',environments=[dict(runtime='27.0')],budgets_seconds=dict(runtime_reservation=1590))
                with patch.object(suite,'reviewed',return_value=(definition,{})),patch.object(suite,'command') as native:
                    with self.assertRaises(ValueError):suite.run(root,'17.5' if corruption=='prior-failed' else '27.0')
                native.assert_not_called()


if __name__=='__main__':unittest.main()
