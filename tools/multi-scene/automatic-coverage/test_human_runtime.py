"""No native execution: finite inventory and actual-query cleanup adapter controls."""
import copy
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import contextlib
import time
import unittest
from unittest.mock import patch, Mock
import human_runtime as runtime
from acceptance_common import Rejected


class RuntimeBindingControls(unittest.TestCase):
    def definition(self):return json.loads(runtime.build.OWNER.read_text())
    def test_existing_forty_cells_start_with_the_baseline_candidate_pair(self):
        rows=runtime.selected_matrix(self.definition());self.assertEqual(len(rows),40)
        self.assertEqual(rows[0],runtime.FIRST);self.assertEqual(rows[1],dict(runtime.FIRST,build='candidate-27.1'))
    def test_s2_has_twelve_cells_with_separate_rebuild_and_sdk_axes(self):
        register=runtime.shared.read(runtime.shared.REPO/'DatadogRUM/MultiSceneSupport/release-gates.json')
        rows=runtime.s2_matrix(self.definition(),register)
        self.assertEqual(len(rows),12)
        for offset in range(0,12,3):
            self.assertEqual([row['build'] for row in rows[offset:offset+3]],
                             ['baseline-26.5','baseline-27.1','candidate-27.1'])
        self.assertTrue(all(row['device']=='duo' and row['multiple_scenes'] is False for row in rows))
    def test_s2_rejects_changed_source_pair(self):
        register=runtime.shared.read(runtime.shared.REPO/'DatadogRUM/MultiSceneSupport/release-gates.json')
        next(row for row in register['releases'] if row['id']=='S2')['acceptance_contract']['source_pair']['candidate']='unreviewed'
        with self.assertRaises(Rejected):runtime.s2_matrix(self.definition(),register)
    def test_duplicate_cannot_replace_an_unrun_cell(self):
        definition=self.definition();definition['matrix']['inventory'][-1]=copy.deepcopy(definition['matrix']['inventory'][0])
        with self.assertRaises(Rejected):runtime.selected_matrix(definition)
    def test_old_sdk_manifest_expansion_rejected(self):
        definition=self.definition();definition['matrix']['inventory'][0]['multiple_scenes']=True
        with self.assertRaises(Rejected):runtime.selected_matrix(definition)
    def device_bytes(self,kind='regular',state='Booted'):
        version='27-1' if kind=='duo' else '27-0';name='iPhone-Duo' if kind=='duo' else 'iPhone-18-Pro'
        return json.dumps({'devices':{'com.apple.CoreSimulator.SimRuntime.iOS-'+version:[{'udid':'fixture','state':state,'deviceTypeIdentifier':'com.apple.CoreSimulator.SimDeviceType.'+name}]}}).encode()
    def test_actual_regular_and_duo_queries_remain_distinct(self):
        for kind in ['regular','duo']:
            with patch.object(runtime.shared,'capture',return_value=SimpleNamespace(stdout=self.device_bytes(kind))):
                self.assertEqual(runtime.device_snapshot('fixture',kind)['udid'],'fixture')
                with self.assertRaises(Rejected):runtime.device_snapshot('fixture','regular' if kind=='duo' else 'duo')
    def test_shutdown_device_is_not_implicitly_booted(self):
        with patch.object(runtime.shared,'capture',return_value=SimpleNamespace(stdout=self.device_bytes(state='Shutdown'))) as read:
            with self.assertRaises(Rejected):runtime.device_snapshot('fixture','regular')
            self.assertEqual(read.call_count,1)
    def test_cleanup_adapter_restores_original_query_after_failure(self):
        original=runtime.shared.devices
        with patch.object(runtime.transport,'cleanup_cell',side_effect=RuntimeError('offline cleanup rejection')):
            with self.assertRaises(RuntimeError):runtime.cleanup(Path('/unused'),None,None,{'bundle':'fixture'},'fixture',{},[],None,None,'INVALID',1,'regular')
        self.assertIs(runtime.shared.devices,original)


class S2PreparationControls(unittest.TestCase):
    LEGACY_RULE=b"        limit=100_000_000 if cost['operation']=='snapshot' else 2_000_000\n        require(type(cost.get('duration_ns')) is int and 0<=cost['duration_ns']<=limit,'observer exceeded main-thread budget')"
    def frozen_oracle(self,source):
        path=source/'runtime/helpers'/runtime.human_sessions.CONTRACT;path.parent.mkdir(parents=True)
        path.write_bytes(b'def observe(cost):\n    if cost:\n'+self.LEGACY_RULE+b'\n        require(cost["owner"]=="original", "foreign owner")\n')
        return path
    def test_timing_migration_retains_every_other_original_oracle_byte(self):
        with tempfile.TemporaryDirectory() as temp:
            source=Path(temp);path=self.frozen_oracle(source);original=path.read_bytes()
            base={'helpers':{runtime.human_sessions.CONTRACT:runtime.shared.sha(path)}}
            raw,measurement=runtime.s2_oracle(source,base)
            self.assertEqual(measurement['policy'],'diagnostic-observer-timing-v1')
            self.assertEqual(raw,original.replace(self.LEGACY_RULE,
                b"        require(type(cost.get('duration_ns')) is int and cost['duration_ns']>=0,'invalid observer duration')"))
            self.assertEqual(path.read_bytes(),original)
            path.write_bytes(original+b'# unexpected change')
            with self.assertRaises(Rejected):runtime.s2_oracle(source,base)
            path.write_bytes(original.replace(b'2_000_000',b'3_000_000'))
            base['helpers'][runtime.human_sessions.CONTRACT]=runtime.shared.sha(path)
            with self.assertRaises(Rejected):runtime.s2_oracle(source,base)
    def test_build_reuse_exception_is_only_for_the_noncompiled_backend_decoder(self):
        with tempfile.TemporaryDirectory() as temp:
            repo=Path(temp);decoder=repo/runtime.human_sessions.BACKEND_DECODER
            decoder.parent.mkdir(parents=True);decoder.write_text('original decoder')
            builder=repo/'builder.py';builder.write_text('original builder')
            expected={str(p.relative_to(repo)):runtime.shared.sha(p) for p in [decoder,builder]}
            stub=SimpleNamespace(require=runtime.require,shared=SimpleNamespace(REPO=repo,sha=runtime.shared.sha))
            decoder.write_text('reviewed runtime decoder')
            with self.assertRaises(Rejected):runtime.human_sessions.verify_build_helpers(expected,stub)
            runtime.human_sessions.verify_build_helpers(expected,stub,allow_backend_decoder_update=True)
            builder.write_text('changed builder')
            with self.assertRaises(Rejected):runtime.human_sessions.verify_build_helpers(expected,stub,allow_backend_decoder_update=True)
    def test_explicit_preparation_selects_only_twelve_cells_and_rejects_expansion(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)/'new';source=Path(temp)/'original';(source/'runtime').mkdir(parents=True)
            runtime.shared.save(source/'runtime/runtime-plan.json',{'original':'immutable'})
            contract='tools/multi-scene/automatic-coverage/human_contract.py'
            frozen=self.frozen_oracle(source);original=frozen.read_bytes()
            decoder=runtime.human_sessions.BACKEND_DECODER
            matrix=runtime.selected_matrix(json.loads(runtime.build.OWNER.read_text()))
            products={r['build']+'-'+r['framework']+('-multi' if r['multiple_scenes'] else '-single'):{'identity':runtime.cell_key(r)} for r in matrix}
            base={'helpers':{contract:runtime.shared.sha(frozen),decoder:'original decoder'},'contract':{'fixed':'original'},
                  'build_plan_sha256':'original-build','build_receipts':{'original':'hash'},'products':products}
            refresh=Path(temp)/'refresh';refresh.mkdir();runtime.shared.save(refresh/'refresh-plan.json',{'immutable':'passive observer refresh'})
            with patch.object(runtime.human_sessions,'original',return_value=base), \
                 patch.object(runtime.human_fixture_refresh,'products',return_value=products), \
                 patch.object(runtime,'helper_members',return_value={contract:'later-live-contract',decoder:runtime.shared.sha(runtime.shared.REPO/decoder)}), \
                 patch.object(runtime.human_sessions,'activate_contract_file') as activate:
                runtime.prepare_s2(SimpleNamespace(root=root,original=source,refresh_builds=refresh))
                plan=runtime.verify(root)
                self.assertEqual(plan['kind'],runtime.S2_KIND);self.assertEqual(len(plan['matrix']),12)
                self.assertEqual(len(plan['products']),6);self.assertFalse(plan['native_admitted'])
                self.assertEqual(plan['measurement']['policy'],'diagnostic-observer-timing-v1')
                self.assertEqual(activate.call_args.args[:2],(root.resolve()/'runtime/helpers'/contract,plan['helpers'][contract]))
                self.assertEqual(frozen.read_bytes(),original)
                for key in ['measurement','build_helper_reuse']:
                    changed=copy.deepcopy(plan);changed[key]={'unreviewed':'policy'}
                    runtime.shared.save(root/'runtime/runtime-plan.json',changed)
                    with self.subTest(key=key),self.assertRaises(Rejected):runtime.verify(root)
                runtime.shared.save(root/'runtime/runtime-plan.json',plan)
                selected=root/'runtime/helpers'/contract;saved=selected.read_bytes();selected.write_bytes(saved+b'# change')
                with self.assertRaises(Rejected):runtime.verify(root)
                selected.write_bytes(saved)
                plan['matrix'].append(dict(plan['matrix'][0],multiple_scenes=True))
                runtime.shared.save(root/'runtime/runtime-plan.json',plan)
                with self.assertRaises(Rejected):runtime.verify(root)
            self.assertEqual(runtime.shared.read(source/'runtime/runtime-plan.json'),{'original':'immutable'})


class AdmissionControls(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        self.runtime=self.root/'runtime';self.runtime.mkdir();(self.runtime/'cells').mkdir()
        runtime.shared.save(self.runtime/'runtime-plan.json',{'fixed':'plan'})
        for name in ['operator','preflight']:runtime.shared.save(self.root/(name+'.json'),{'fixed':name})
        self.stage={'state':'ADMITTED','stage_id':'one','runtime_plan_sha256':runtime.shared.sha(self.runtime/'runtime-plan.json'),
            'review_sha256':'review','issued_at':90,'execution_deadline':500,'cleanup_deadline':800}
        for name in ['operator','preflight']:
            self.stage[name+'_path']=str(self.root/(name+'.json'));self.stage[name+'_sha256']=runtime.shared.sha(self.root/(name+'.json'))
        self.plan={'matrix':[runtime.FIRST,dict(runtime.FIRST,build='candidate-27.1')],
                   'contract':{'regular_cell_seconds':1800,'duo_cell_seconds':3600,'human_step_seconds':180,'cleanup_seconds':300}}
        self.save()
    def save(self):runtime.shared.save(self.runtime/'native-admission.json',self.stage)
    def admit(self,key=None,native=500,cleanup=800):
        with patch.object(runtime.time,'time',return_value=100):
            return runtime.admit_cell(self.root,key or runtime.cell_key(runtime.FIRST),self.plan,'review',native,cleanup)
    def test_parent_and_stage_limits_clamp_every_cell(self):
        result=self.admit(native=400,cleanup=650);self.assertEqual(result[-2:],(400,650))
    def test_expired_or_foreign_stage_does_not_reopen(self):
        self.stage['execution_deadline']=99;self.save()
        with self.assertRaises(Rejected):self.admit()
    def test_candidate_cannot_skip_qualification_baseline(self):
        with self.assertRaises(Rejected):self.admit(runtime.cell_key(self.plan['matrix'][1]))
    def test_changed_operator_receipt_does_not_admit_native(self):
        runtime.shared.save(self.root/'operator.json',{'fixed':'different'})
        with self.assertRaises(Rejected):self.admit()
    def test_insufficient_native_or_cleanup_reserve_rejected(self):
        with self.assertRaises(Rejected):self.admit(native=110)
        with self.assertRaises(Rejected):self.admit(native=400,cleanup=350)


class PreviousEvidenceControls(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        (self.root/'cells').mkdir();self.matrix=runtime.selected_matrix(json.loads(runtime.build.OWNER.read_text()))
        self.plan={'matrix':self.matrix};self.stage={'stage_id':'current','runtime_plan_sha256':'p','cleanup_deadline':200}
    def completed(self,index=0):
        selected=self.matrix[index];folder=self.root/'cells'/runtime.cell_key(selected);folder.mkdir()
        local={'views':[],'initial_views':[],'view_count':0,'coverage':[],'missing_action_phases':[],
               **{k:[] for k in ['duplicate_action_ids','unknown_action_owners','unassigned_actions','errors']}}
        runtime.shared.save(folder/'local-result.json',local)
        row={'state':'PASS','scenario':'PASS','evidence':'PASS','cleanup':'PASS','stage_id':'current','runtime_plan_sha256':'p',
            'identity':{'cell':selected,'source':runtime.shared.ARMS['A' if selected['build'].startswith('baseline-') else 'B']},'started_at':100,'finished_at':110,'cleanup_deadline':120,
            'artifacts':{'local-result.json':runtime.shared.sha(folder/'local-result.json')}}
        receipt=self.root/(folder.name+'-driver.supervisor.json')
        runtime.shared.save(receipt,{'state':'PASS','remaining':[],'finished_at':110})
        row['supervisor']={'path':str(receipt),'sha256':runtime.shared.sha(receipt)}
        runtime.shared.save(folder/'summary.json',row);return folder,row
    def test_restored_summary_rejected_even_with_pass_label(self):
        folder,row=self.completed();row['stage_id']='old';runtime.shared.save(folder/'summary.json',row)
        with self.assertRaises(Rejected):runtime.prior_cells(self.root,self.plan,self.stage)
    def test_changed_mapper_inventory_invalidates_prior_acceptance(self):
        folder,_=self.completed();(folder/'local-result.json').write_text('{}')
        with self.assertRaises(Rejected):runtime.prior_cells(self.root,self.plan,self.stage)
    def test_cleanup_invalid_cannot_be_hidden_by_overall_pass(self):
        folder,row=self.completed();row['cleanup']='INVALID';runtime.shared.save(folder/'summary.json',row)
        with self.assertRaises(Rejected):runtime.prior_cells(self.root,self.plan,self.stage)
    def test_unfinished_directory_and_out_of_order_receipt_are_not_retries(self):
        folder,row=self.completed(1)
        with self.assertRaises(Rejected):runtime.prior_cells(self.root,self.plan,self.stage)
        (folder/'summary.json').unlink()
        with self.assertRaises(FileNotFoundError):runtime.prior_cells(self.root,self.plan,self.stage)
    def test_incomplete_matrix_never_claims_complete_or_closes_gates(self):
        self.completed();result=runtime.compare_matrix(self.root,self.plan,self.stage)
        self.assertEqual(result['state'],'PARTIAL_LOCAL_COMPARISON');self.assertEqual(result['qualified_cells'],1)
        self.assertEqual(result['gates_closed'],[])
    def test_all_finite_pairs_are_compared_without_crossing_manifest_boundaries(self):
        for index in range(40):self.completed(index)
        result=runtime.compare_matrix(self.root,self.plan,self.stage)
        self.assertEqual(result['state'],'COMPLETE_LOCAL_COMPARISON');self.assertEqual(len(result['comparisons']),120)
        self.assertTrue(all(row['status']=='UNCHANGED_LIMITATION' for row in result['comparisons'] if row['family']=='views'))
    def test_same_counts_with_different_occurrence_owners_require_classification(self):
        self.completed();folder,row=self.completed(1)
        local=runtime.shared.read(folder/'local-result.json');local['coverage']=[{'phase':'initial.root.tap','actions':[{'type':'tap','name':'Tap','owner_index':2,'owner_name':'Foreign'}]}]
        runtime.shared.save(folder/'local-result.json',local);row['artifacts']['local-result.json']=runtime.shared.sha(folder/'local-result.json');runtime.shared.save(folder/'summary.json',row)
        result=runtime.compare_matrix(self.root,self.plan,self.stage)
        self.assertEqual(result['state'],'REVIEW_REQUIRED');self.assertEqual(result['source_differences'],1)


class FinalVerdictControls(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        self.out=self.root/'cells'/'cell';self.out.mkdir(parents=True)
        runtime.shared.save(self.out/'cell-result.json',{'state':'PASS','scenario':'PASS','evidence':'PASS','cleanup':'PASS','cleanup_deadline':200})
        runtime.shared.save(self.root/'cell-driver.supervisor.json',{'state':'PASS','remaining':[],'before':[]})
    def final(self,**kwargs):
        with patch.object(runtime.time,'time',return_value=100):return runtime.final_cell(self.root,'cell',**kwargs)
    def test_capture_failure_keeps_independent_successful_cleanup(self):
        result=self.final(supervisor_error='publication failed')
        self.assertEqual(result['state'],'INVALID');self.assertEqual(result['cleanup'],'PASS')
    def test_late_worker_absence_keeps_original_cleanup_invalid(self):
        runtime.shared.save(self.root/'cell-driver.supervisor.json',{'state':'INVALID','remaining':[],'before':[]})
        self.assertEqual(self.final()['cleanup'],'INVALID')
    def test_descendant_reaped_after_teardown_does_not_retroactively_qualify_cleanup(self):
        runtime.shared.save(self.root/'cell-driver.supervisor.json',{'state':'PASS','remaining':[],'before':[1234]})
        self.assertEqual(self.final()['cleanup'],'INVALID')


class FailedInputRunner(unittest.TestCase):
    def exercise(self,released):
        with tempfile.TemporaryDirectory() as temp,contextlib.ExitStack() as stack:
            root=Path(temp);(root/'runtime/cells').mkdir(parents=True);installed=root/'app';installed.mkdir();documents=root/'data/Documents';documents.mkdir(parents=True)
            selected=runtime.FIRST;key=runtime.cell_key(selected);now=time.time()
            stage=dict(runtime_plan_sha256='plan',stage_id='stage',devices={'regular':{'udid':'device'}})
            product=dict(path=str(installed),bundle='task.app',product={'executable':'Fixture'})
            plan=dict(products={'baseline-27.1-UIKit-single':product},contract={'cleanup_seconds':600})
            runtime.shared.save(root/'build-plan.json',{'arms':{'baseline-27.1':{'revision':runtime.shared.ARMS['A']}}})
            stack.enter_context(patch.object(runtime,'reviewed',return_value=(plan,'review')))
            stack.enter_context(patch.object(runtime,'admit_cell',return_value=(selected,stage,now,now+600,now+1200)))
            stack.enter_context(patch.object(runtime,'device_snapshot',return_value={'udid':'device'}))
            stack.enter_context(patch.object(runtime.shared,'apps',return_value={}))
            stack.enter_context(patch.object(runtime.transport,'display',return_value=b'actual display'))
            stack.enter_context(patch.object(runtime.shared,'product',return_value=product['product']))
            stack.enter_context(patch.object(runtime.shared,'process',return_value=str(installed/'Fixture')))
            responses=[SimpleNamespace(returncode=1),SimpleNamespace(stdout=str(installed).encode()),SimpleNamespace(stdout=str(documents.parent).encode())]
            stack.enter_context(patch.object(runtime.shared,'capture',side_effect=responses))
            def command(argv,out,label,**kwargs):
                if label=='launch':(out/'launch.log').write_text('task.app: 42\n')
            stack.enter_context(patch.object(runtime.shared,'command',side_effect=command))
            collector=Mock();collector.prompt_issued=True;collector.perform.side_effect=ValueError('native effect never completed')
            stack.enter_context(patch.object(runtime.capture,'Collector',return_value=collector))
            stack.enter_context(patch.object(runtime.journey,'steps',return_value=[dict(kind='tap',phase='one')]))
            stack.enter_context(patch.object(runtime.human_processes,'quiesce',return_value={'state':'PASS','remaining':[]}))
            order=[]
            def guard(*args):
                order.append('release-and-native-idle')
                if not released:raise ValueError('release unconfirmed; preserve app')
            stack.enter_context(patch.object(runtime.capture.human_release,'guard',side_effect=guard))
            cleanup=stack.enter_context(patch.object(runtime,'cleanup',side_effect=lambda *args:order.append('teardown') or []))
            stack.enter_context(patch('builtins.print'))
            self.assertEqual(runtime.execute_cell(SimpleNamespace(root=root,key=key,execution_deadline=now+600,cleanup_deadline=now+1200)),1)
            result=runtime.shared.read(root/'runtime/cells'/key/'cell-result.json')
            self.assertEqual(result['scenario'],'UNQUALIFIED');self.assertEqual(result['state'],'INVALID')
            if released:self.assertEqual(order,['release-and-native-idle','teardown']);self.assertEqual(result['cleanup'],'PASS')
            else:cleanup.assert_not_called();self.assertEqual(result['cleanup'],'INVALID')
    def test_unconfirmed_human_input_preserves_app_through_actual_cell_finally(self):self.exercise(False)
    def test_confirmed_native_idle_allows_cleanup_without_repairing_scenario(self):self.exercise(True)


if __name__=='__main__':unittest.main()
