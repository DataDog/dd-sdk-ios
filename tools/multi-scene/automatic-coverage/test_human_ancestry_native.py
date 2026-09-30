"""Request and owner discriminators for the one automatic ancestry diagnostic."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from unittest.mock import Mock

import human_ancestry_native as native
from test_tool_worker_service import Fixture


def synthetic_plan(f):
    """An admission fixture with no product, native process or actual tool contract."""
    w=native.worker_service; folder=f.requests.parent
    w.save(f.root/'request.json',dict(operation='action',binding=f.binding,issued_at=10))
    w.save(f.root/'response.json',dict(kind='AUTOMATIC_PREFIX_NO_CALL',input_calls=0,
        request=w.reference(f.root/'request.json'),binding=f.binding,owner=f.binding['owner'],published_at=71))
    w.save(f.root/'assessment.json',dict(state='STOPPED_BEFORE_INPUT_ASSESSED',timings=dict(
        capture=dict(issued_to_claim_seconds=18,native_call_seconds=8,return_to_publication_seconds=6))))
    ledger=w.budget_ledger({k:w.reference(f.root/(k+'.json')) for k in ('assessment','request','response')},
        passive_snapshot=30,settle=2)
    w.save(f.root/'budget.json',ledger); f.budgets=ledger['budgets']
    w.save(f.root/'definition.json',dict(synthetic=True))
    plan=dict(kind='ONE_AUTOMATIC_PREFIX_ANCESTRY_QUALIFICATION',worker=f.binding['owner'],
        device=dict(udid=f.binding['device'],runtime='synthetic',state='Booted',deviceTypeIdentifier='test'),
        product=dict(bundle=f.binding['bundle'],path='synthetic-no-product',product=dict(executable='test')),
        run_id=f.binding['run_id'],budgets=f.budgets,budget_ledger=w.reference(f.root/'budget.json'),
        worker_service=str(f.folder),worker_sources=f.sources,pump_source=w.reference(f.pump_source),
        helpers={k:v for k,v in f.sources.items() if k!=str(f.pump_source)},
        driver=native.evidence.reference(native.__file__),definition=w.reference(f.root/'definition.json'))
    w.save(f.root/'build.json',dict(synthetic=True)); plan['build']=w.reference(f.root/'build.json')
    w.save(f.root/'prefix.json',dict(kind=plan['kind'],budget_ledger=plan['budget_ledger'],
        budgets_seconds=plan['budgets'],worker=plan['worker'],pump_source=plan['pump_source']))
    plan['prefix_definition']=w.reference(f.root/'prefix.json')
    w.save(folder/'plan.json',plan); f.binding=native.worker_binding(folder,plan)
    w.save(folder/'review.json',dict(state='PASS',reviewer='/root/c06_runtime_plan',
        plan_sha256=w.reference(folder/'plan.json')['sha256'],synthetic=True))
    return plan


class WorkerAdmission(unittest.TestCase):
    def test_runner_publication_mutation_stops_before_display_session_and_install(self):
        for changed in ('admission','consumption','plan','review','ledger','observed-source','pump-source','helper-closure'):
            with self.subTest(changed=changed):
                f=Fixture(self,plan_factory=synthetic_plan,external_service=True); f.answer()
                shared=SimpleNamespace(apps=Mock(return_value={}),
                    capture=Mock(return_value=SimpleNamespace(returncode=1)),command=Mock())
                module=SimpleNamespace(shared=shared,transport=SimpleNamespace(display=Mock()),
                    human_release=SimpleNamespace(process_identity=native.worker_service.process_identity))
                original_save=native.worker_service.save; original_setup=native.worker_service.setup_current
                def simulated(*args): return dict(original_setup(*args),discovery_source='LIVE_TOOL_DISCOVERY')
                def save(path,value):
                    original_save(path,value)
                    if Path(path).name!='admission.json': return
                    if changed=='admission':
                        record=native.evidence.read(path); record['deadline']+=1; Path(path).write_text(json.dumps(record))
                    elif changed=='consumption':
                        target=f.folder/'consumed.json'; record=native.evidence.read(target)
                        record['execution_deadline']+=600; target.write_text(json.dumps(record))
                    elif changed in ('plan','review'):
                        target=f.requests.parent/(changed+'.json'); target.write_text('{}')
                    elif changed=='ledger': (f.root/'budget.json').write_text('{}')
                    elif changed=='observed-source': (f.root/'assessment.json').write_text('{}')
                    elif changed=='pump-source': f.pump_source.write_text('# replacement synthetic pump source\n')
                    else: dependencies.return_value={k:'0'*64 for k in f.plan['helpers']}
                with patch.object(native,'context',return_value=(module,{},{})), \
                     patch.object(native,'dependencies',return_value=f.plan['helpers']) as dependencies, \
                     patch.object(native,'product',return_value=dict(synthetic=True)), \
                     patch.object(native,'device',return_value=f.plan['device']), \
                     patch.object(native,'prefix_definition',return_value=native.evidence.read(f.root/'prefix.json')), \
                     patch.object(native.worker_service,'setup_current',side_effect=simulated), \
                     patch.object(native.worker_service,'save',side_effect=save), \
                     patch.object(native,'PreparedPrefixSession') as session:
                    with self.assertRaises(ValueError): native.run(f.root,output=f.requests.parent)
                shared.command.assert_not_called(); module.transport.display.assert_not_called(); session.assert_not_called()
                self.assertFalse((f.requests.parent/'admission.json').exists())
                self.assertTrue((f.requests.parent/'invalidated-admission.json').exists())
                rejected=native.evidence.read(f.requests.parent/'admission-rejection.json')
                self.assertEqual(rejected['service_cleanup'],'OWNED_SERVICE_STOPPED_NO_NATIVE_CLEANUP')
                self.assertEqual(rejected['installations'],0); self.assertFalse(rejected['native_cleanup'])
                with self.assertRaises(ValueError): native.worker_service.process_identity(f.service.record['pid'])

    def test_successful_simulated_admission_keeps_the_issued_clocks_and_bytes(self):
        f=Fixture(self,plan_factory=synthetic_plan); f.answer(); original=native.worker_service.setup_current
        def simulated(*args): return dict(original(*args),discovery_source='LIVE_TOOL_DISCOVERY')
        module=SimpleNamespace(human_release=SimpleNamespace(process_identity=native.worker_service.process_identity))
        with patch.object(native.worker_service,'setup_current',side_effect=simulated):
            clocks,consumption,service=native.worker_gate(f.requests.parent,f.plan)
        admission=dict(kind=f.plan['kind'],plan=native.evidence.reference(f.requests.parent/'plan.json'),
            review=native.evidence.reference(f.requests.parent/'review.json'),run_id=f.plan['run_id'],
            controller_pid=clocks['controller']['pid'],controller_identity=clocks['controller']['identity'],
            started_at=clocks['issued_at'],deadline=clocks['execution_deadline'],
            cleanup_deadline=clocks['cleanup_deadline'],worker_consumption=consumption,scenario_credit=False)
        with patch.object(native,'dependencies',return_value=f.plan['helpers']), \
             patch.object(native,'product',return_value=dict(synthetic=True)):
            native.publish_admission(f.root,f.requests.parent,module,f.plan,admission,consumption,service,{})
        self.assertEqual(native.evidence.read(f.requests.parent/'admission.json'),admission)
        self.assertEqual(native.worker_service.reference(f.requests.parent/'admission.json'),
            native.worker_service.value_reference(f.requests.parent/'admission.json',admission))

    def test_synthetic_roundtrip_cannot_admit_native_or_install(self):
        f=Fixture(self,plan_factory=synthetic_plan); f.answer()
        with self.assertRaisesRegex(ValueError,'synthetic controls'):
            native.worker_gate(f.requests.parent,f.plan)
        self.assertFalse((f.requests.parent/'admission.json').exists())
        self.assertFalse((f.folder/'consumed.json').exists())
        stopped=native.evidence.read(f.requests.parent/'worker-preflight-rejected.json')
        self.assertEqual(stopped['installations'],0); self.assertFalse(stopped['native_admitted'])

    def test_old_budget_stops_before_readiness_consumption(self):
        f=Fixture(self,plan_factory=synthetic_plan); f.answer()
        plan=dict(f.plan,budgets=dict(f.budgets,step=90))
        with self.assertRaises(ValueError): native.worker_gate(f.requests.parent,plan)
        self.assertFalse((f.folder/'consumed.json').exists())
        self.assertFalse((f.requests.parent/'admission.json').exists())

    def test_foreign_or_consumed_output_does_not_gain_admission(self):
        for consumed in (False,True):
            with self.subTest(consumed=consumed):
                f=Fixture(self,plan_factory=synthetic_plan); f.answer()
                if consumed: native.evidence.save(f.requests.parent/'admission.json',dict(original='immutable'))
                else: native.evidence.save(f.requests/'unexpected.json',dict(foreign=True))
                with self.assertRaises(ValueError): native.worker_gate(f.requests.parent,f.plan)
                self.assertFalse((f.folder/'consumed.json').exists())

    def test_simulated_live_contract_consumption_preserves_original_clocks(self):
        f=Fixture(self,plan_factory=synthetic_plan); f.answer()
        original=native.worker_service.setup_current
        def simulated(*args):
            return dict(original(*args),discovery_source='LIVE_TOOL_DISCOVERY')
        # Mocked discovery is unit preparation only; the runner is never called.
        with patch.object(native.worker_service,'setup_current',side_effect=simulated):
            receipt,ref,_=native.worker_gate(f.requests.parent,f.plan)
        self.assertEqual(receipt['execution_deadline'],receipt['issued_at']+f.budgets['native'])
        self.assertEqual(receipt['cleanup_deadline'],receipt['execution_deadline']+f.budgets['cleanup'])
        self.assertEqual(ref,native.worker_service.reference(f.folder/'consumed.json'))
        self.assertFalse((f.requests.parent/'admission.json').exists())

    def test_runner_rejects_missing_pump_before_admission_or_install(self):
        f=Fixture(self,pump=False,plan_factory=synthetic_plan)
        shared=SimpleNamespace(apps=Mock(return_value={}),capture=Mock(return_value=SimpleNamespace(returncode=1)),
                               command=Mock())
        module=SimpleNamespace(shared=shared)
        with patch.object(native,'context',return_value=(module,{},{})), \
             patch.object(native,'dependencies',return_value=f.plan['helpers']), \
             patch.object(native,'product',return_value=dict(synthetic=True)), \
             patch.object(native,'device',return_value=f.plan['device']), \
             patch.object(native,'prefix_definition',return_value=native.evidence.read(f.root/'prefix.json')):
            with self.assertRaises(ValueError): native.run(f.root,output=f.requests.parent)
        shared.command.assert_not_called()
        self.assertFalse((f.requests.parent/'admission.json').exists())

    def test_route_check_wraps_actual_exchange_and_end(self):
        folder=Path('/synthetic'); consumption=dict(path='mock',sha256='0'*64)
        session=object.__new__(native.PreparedPrefixSession)
        session.service_root=folder; session.consumption=consumption
        with patch.object(native.worker_service,'active') as active, \
             patch.object(native.prefix_session.Session,'exchange',return_value=('actual','return')) as exchange:
            self.assertEqual(session.exchange('step','capture',{},10),('actual','return'))
        self.assertEqual(active.call_count,2); exchange.assert_called_once()
        with patch.object(native.worker_service,'active',side_effect=ValueError('pump absent')), \
             patch.object(native.prefix_session.Session,'exchange') as exchange:
            with self.assertRaises(ValueError): session.exchange('step','capture',{},10)
        exchange.assert_not_called()
        with patch.object(native.worker_service,'active') as active, \
             patch.object(native.prefix_session.Session,'end') as end:
            session.end(10)
        end.assert_called_once_with(10); active.assert_called_once_with(folder,consumption)


class SnapshotJoin(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path('/Users/valentin.pertuisot/work/dd-sdk-ios-extractions/evidence/s2-swiftui-ancestry-j7r7e8fi')
        cls.module, definition, _ = native.context(cls.root)
        prior = native.build.bound(definition['source_attempt'])
        folder = Path(prior['separate_restoration']['result']['path']).parent
        cls.raw = (folder/'events.jsonl').read_bytes()
        cls.checkpoint = json.loads((folder/'checkpoint.json').read_bytes())
        cls.request = (folder/'published-request.json').read_bytes()
        cls.run_id = json.loads(cls.request)['run_id']
        cls.binding = native.validate_snapshot(cls.module,cls.raw,cls.checkpoint,cls.request,cls.run_id)[1]

    def test_saved_failure_joins_without_receiving_scenario_credit(self):
        row, binding, _ = native.validate_snapshot(self.module,self.raw,self.checkpoint,self.request,self.run_id)
        self.assertEqual(row['sequence'],186)
        self.assertEqual(binding,self.binding)
        self.assertEqual(row['payload']['topology']['accessibility'][0]['capture_error'],
                         'public accessibility view has missing owned ancestry')

    def test_replaced_request_phase_hash_and_run_reject(self):
        for key,value in [('phase','diagnostic.opened'),('run_id','foreign'),('request_id','foreign')]:
            request=json.loads(self.request);request[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):
                native.validate_snapshot(self.module,self.raw,self.checkpoint,json.dumps(request).encode(),self.run_id)

    def test_forged_checkpoint_and_missing_prefix_reject(self):
        for raw,checkpoint in [(self.raw[:-100],self.checkpoint),
                               (self.raw,dict(self.checkpoint,sha256='0'*64)),
                               (self.raw,dict(self.checkpoint,request_id='foreign'))]:
            with self.subTest(checkpoint=checkpoint),self.assertRaises(ValueError):
                native.validate_snapshot(self.module,raw,checkpoint,self.request,self.run_id)

    def test_validly_hashed_regressed_cleanup_checkpoint_rejects(self):
        native.validate_snapshot(self.module,self.raw,self.checkpoint,self.request,self.run_id,after_sequence=185)
        for previous in (186,187):
            with self.subTest(previous=previous),self.assertRaisesRegex(ValueError,'did not advance'):
                native.validate_snapshot(self.module,self.raw,self.checkpoint,self.request,self.run_id,after_sequence=previous)

    def test_rebound_owner_rejects_even_with_valid_writer_prefix(self):
        for key in ('root','window','scene'):
            binding=dict(self.binding,**{key:'foreign'})
            with self.subTest(key=key),self.assertRaises(ValueError):
                native.validate_snapshot(self.module,self.raw,self.checkpoint,self.request,self.run_id,binding)

    def test_actual_display_tolerates_roundoff_but_rejects_other_size(self):
        row,binding,_=native.validate_snapshot(self.module,self.raw,self.checkpoint,self.request,self.run_id)
        scene=row['payload']['topology']['scene_inventory'][0]
        display=dict(nativeSize=[n*scene['screen_scale'] for n in scene['screen_bounds'][2:]],
                     pointScale=scene['screen_scale'],currentOrientation='rot0')
        native.screen(self.module,row,binding,display)
        changed=copy.deepcopy(row)
        next(w for w in changed['payload']['topology']['scene_inventory'][0]['windows'] if w['owned'])['bounds'][2]+=.000001
        native.screen(self.module,changed,binding,display)
        display['nativeSize'][0]+=100
        with self.assertRaises(ValueError):native.screen(self.module,row,binding,display)

    def test_failed_snapshot_retains_actual_bytes_without_advancing_accepted_state(self):
        for prefix in (b'',b'replaced-prefix'):
            with self.subTest(prefix=prefix),tempfile.TemporaryDirectory() as temporary:
                folder=Path(temporary);documents=folder/'documents';documents.mkdir()
                raw=b'actual-invalid-stream\n';checkpoint=b'{}'
                def publish(path,request):
                    native.evidence.save(path,request)
                    (documents/'events.jsonl').write_bytes(raw)
                    (documents/('events-checkpoint-'+request['request_id']+'.json')).write_bytes(checkpoint)
                module=SimpleNamespace(shared=SimpleNamespace(save=publish),
                    human_release=SimpleNamespace(process_identity=lambda _: 'actual-process'))
                capture=native.Capture(module,folder,documents,'run',123)
                capture.prefix=prefix;capture.last_sequence=7;capture.last_row={'sequence':7}
                with patch.object(native,'validate_snapshot',side_effect=ValueError('invalid current capture')):
                    with self.assertRaises(ValueError):capture.snapshot('failed','cleanup.idle',time.time()+30)
                failure=native.evidence.read(capture.failed_snapshot['path'])
                self.assertEqual(Path(failure['events']['path']).read_bytes(),raw)
                self.assertEqual(Path(failure['checkpoint']['path']).read_bytes(),checkpoint)
                self.assertEqual(failure['prior_accepted_sequence'],7)
                self.assertFalse(failure['scenario_credit'])
                self.assertEqual(capture.last_row,{'sequence':7});self.assertEqual(capture.prefix,prefix)
                self.assertFalse((folder/'failed/joined.json').exists())


if __name__=='__main__':unittest.main()
