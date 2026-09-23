"""Negative controls for the bounded legacy iOS 17.5 continuation."""
import copy
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

import legacy17 as subject
import test_legacy_compatibility as samples


def cases():
    result=[]
    for arm in subject.legacy.ARMS:
        for mode in subject.legacy.MODES:
            data=samples.lifecycle(mode.endswith('manual')) if mode.startswith('lifecycle-') else samples.navigation()
            data.update(mode=mode,os='17.5',run_id=arm+'/'+mode)
            result.append(dict(arm=arm,mode=mode,os='17.5',run_id=data['run_id'],status='PASS',scenario='PASS',evidence='PASS',
                               installed_identity=True,clean_install=True,cleanup={'status':'PASS'},
                               signature=subject.legacy.check_result(data,data['run_id'],mode,'17.5')))
    return result


class LegacyContinuationTests(unittest.TestCase):
    def runner(self,root):
        runner=object.__new__(subject.Runner);runner.root=Path(root);runner.deadline=time.time()+20
        runner.definition={'runtime':{'developer':'/unused'},'budgets_seconds':{'native_per_cell':120,'cleanup_per_cell':60,'final_cleanup':120}}
        runner.summary={'commands':[],'cases':[],'stage_deadline':time.time()+100,'builds':{},'devices':{'17.5':{'udid':'device'}}}
        runner.cleanup_phase=False
        return runner

    def test_final_state_checks_both_initial_boot_states(self):
        for state in ['Shutdown','Booted']:
            initial={'17.5':dict(udid='selected',state=state)}
            subject.restored_states(initial,{'devices':{'runtime':[dict(udid='selected',state=state)]}})
            for rows in [[],[dict(udid='selected',state='Booted' if state=='Shutdown' else 'Shutdown')]]:
                with self.subTest(state=state,rows=rows),self.assertRaises(ValueError):
                    subject.restored_states(initial,{'devices':{'runtime':rows}})

    def test_complete_eight_cell_matrix(self):
        self.assertEqual(subject.matrix(cases()),'PASS')

    def test_missing_duplicate_cell_and_run_are_rejected(self):
        for mutation in ['missing','duplicate','run']:
            value=cases()
            if mutation=='missing':value.pop()
            elif mutation=='duplicate':value[-1]=copy.deepcopy(value[0])
            else:value[-1]['run_id']=value[0]['run_id']
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):subject.matrix(value)

    def test_runtime_identity_and_independent_verdicts_are_required(self):
        for key,value in [('os','27.0'),('installed_identity',False),('clean_install',False),('scenario','FAIL'),('evidence','INVALID'),('cleanup',{'status':'INVALID'})]:
            rows=cases();rows[0][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):subject.matrix(rows)

    def test_equal_counts_do_not_hide_changed_owner(self):
        value=cases();value[0]['signature']['owners'][0]['occurrence']=9
        with self.assertRaisesRegex(ValueError,'difference'):subject.matrix(value)

    def test_native_process_identity_rejects_relaunch_and_restored_id(self):
        subject.native_identity({'pid':9,'run_id':'run'},9,'run')
        for value in [{'pid':10,'run_id':'run'},{'pid':9,'run_id':'restored'},{'pid':'9','run_id':'run'},{'pid':True,'run_id':'run'},{'run_id':'run'}]:
            with self.subTest(value=value),self.assertRaises(ValueError):subject.native_identity(value,9,'run')

    def test_fixture_pid_is_published_at_every_boundary(self):
        original=(subject.baseline.HERE/'Fixture/App.swift').read_text()
        navigation=subject.legacy.compatibility_source(original)
        lifecycle=subject.legacy.observed_lifecycle_source(navigation)
        for text,count in [(navigation,1),(lifecycle,3)]:
            bound=subject.fixture_identity(text)
            self.assertEqual(bound.count('"pid": ProcessInfo.processInfo.processIdentifier'),count)
            with self.assertRaises(ValueError):subject.fixture_identity(bound)
        with self.assertRaises(ValueError):subject.fixture_identity('no anchors')

    def test_cleanup_has_its_own_budget_after_expired_work(self):
        with tempfile.TemporaryDirectory() as root:
            runner=self.runner(root);runner.summary['stage_deadline']=time.time()-1
            with self.assertRaises(ValueError):runner.phase('native_per_cell')
            value=runner.phase('cleanup_per_cell',cleanup=True)
            self.assertGreater(value['deadline'],time.time())
            self.assertEqual(value['deadline']-value['started_at'],60)

    def test_expired_command_never_starts(self):
        with tempfile.TemporaryDirectory() as root:
            runner=self.runner(root);runner.deadline=time.time()-1
            with patch.object(subject.subprocess,'Popen') as launch,self.assertRaises(ValueError):runner.command('late',['ignored'])
            launch.assert_not_called()

    def test_fresh_publication_is_retained_before_identity_rejection(self):
        with tempfile.TemporaryDirectory() as root:
            runner=self.runner(root);runner.summary['cases']=[dict(pid=9,run_id='fresh',artifact_root=root)]
            path=Path(root)/'result.json';raw=b'{"run_id":"restored","pid":9}'
            path.write_bytes(raw)
            with self.assertRaises(ValueError):runner.wait_json(path,0)
            self.assertEqual([p.read_bytes() for p in Path(root).glob('raw-result-*.json')],[raw])

    def test_stale_file_timestamp_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            runner=self.runner(root);runner.summary['cases']=[dict(pid=9,run_id='fresh',artifact_root=root)]
            path=Path(root)/'ready.json';path.write_text('{"pid":9,"run_id":"fresh"}')
            with self.assertRaisesRegex(ValueError,'timestamp'):runner.wait_json(path,time.time_ns()+1_000_000_000)

    def test_late_publication_cannot_rescue_expired_cell(self):
        with tempfile.TemporaryDirectory() as root:
            runner=self.runner(root);runner.summary['cases']=[dict(pid=9,run_id='fresh',artifact_root=root)];runner.deadline=time.time()-1
            path=Path(root)/'result.json';path.write_text('{"pid":9,"run_id":"fresh"}')
            with self.assertRaises(TimeoutError):runner.wait_json(path,0)

    def test_boundary_identity_checked_before_native_command(self):
        for name,receipt in [('background','accepted-readiness.json'),('foreground','accepted-background.json')]:
            with self.subTest(name=name),tempfile.TemporaryDirectory() as root:
                runner=self.runner(root);runner.summary['cases']=[dict(pid=9,run_id='fresh',artifact_root=root)]
                (Path(root)/receipt).write_text('{"pid":10,"run_id":"fresh"}')
                with patch.object(subject.subprocess,'Popen') as launch,self.assertRaises(ValueError):runner.command(name,['ignored'])
                launch.assert_not_called()

    def test_published_result_is_rechecked_from_frozen_bytes(self):
        with tempfile.TemporaryDirectory() as root:
            runner=self.runner(root);data=samples.navigation();data.update(os='17.5',pid=9)
            path=Path(root)/'result.json';path.write_text(json.dumps(data))
            case=dict(pid=9,run_id='fresh',mode='automatic',os='17.5',result=dict(path=str(path),sha256=subject.shared.sha(path)),
                      signature=subject.legacy.check_result(data,'fresh','automatic','17.5'))
            runner.summary['cases']=[case];runner.verify_evidence()
            data['events'][1]['owner']='foreign';path.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError,'changed'):runner.verify_evidence()

    def test_installed_product_mismatch_prevents_launch_and_still_cleans(self):
        with tempfile.TemporaryDirectory() as root:
            runner=self.runner(root);calls=[]
            runner.summary['builds']['baseline/Navigation']=dict(bundle='task.bundle',app='built',sha256='frozen',full_product={'files':{}})
            def command(name,args,**kwargs):
                calls.append(name)
                return (1,'') if name=='prior-data' else (0,root)
            runner.command=command;runner.verify_inputs=lambda:None;runner.verify_products=lambda:None;runner.boot=lambda version:None
            runner.cleanup=lambda device,bundle:dict(status='PASS',only_bundle=bundle)
            with patch.object(subject.shared,'product',return_value={'files':{'foreign':'changed'}}),self.assertRaisesRegex(ValueError,'case did not pass'):
                runner.run_case('baseline','17.5','automatic')
            self.assertNotIn('launch',calls)
            self.assertEqual(runner.summary['cases'][0]['cleanup']['only_bundle'],'task.bundle')
            self.assertEqual(runner.summary['cases'][0]['status'],'INVALID')


if __name__=='__main__':unittest.main()
