"""Local synthetic pump controls; these do not qualify native capture or a gate."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import urllib.request
import uuid
from types import SimpleNamespace

import tool_worker_service as worker


# A real separate process loads the component and answers via its delivery route.
# Its discovery is explicitly synthetic; the native entrypoint must reject it.
PUMP = '''import json, os, sys, time, urllib.request
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import tool_worker_service as w
folder=Path(sys.argv[2]); record=w.health(folder)
loaded=time.time(); process=dict(pid=os.getpid(),identity=w.process_identity(os.getpid()))
contract=dict(kind='TOOL_PUMP_CONTRACT',discovery_source='SYNTHETIC_CONTROL',discovered_at=loaded,
 tools={k:'Synthetic contract, no native calls' for k in ('DeviceInteractionStartSession',
 'DeviceInteractionSynthesize','DeviceInteractionEndSession')})
w.save(folder/'pump-contract.json',contract)
w.save(folder/'pump-setup.json',dict(kind='TOOL_PUMP_SETUP',service=w.reference(folder/'service.json'),
 binding=record['binding'],sources=record['sources'],pump_source=record['pump_source'],
 pump_process=process,contract=w.reference(folder/'pump-contract.json'),loaded_at=loaded,native_calls=0,pending_calls=0))
while time.time()<record['deadline']:
 with urllib.request.urlopen(record['url']+'/pending',timeout=3) as response: pending=json.load(response)
 if pending['kind']=='PROBE':
  answer=dict(kind='TOOL_PUMP_PREPARED',request=pending['request'],binding=record['binding'],
   sources=record['sources'],pump_source=record['pump_source'],pump_process=process,
   setup=w.reference(folder/'pump-setup.json'),loaded_at=loaded,native_calls=0,pending_calls=0,native_authority=False)
  request=urllib.request.Request(record['url']+'/answer',data=json.dumps(answer).encode())
  with urllib.request.urlopen(request,timeout=3) as response: json.load(response)
  break
 time.sleep(.01)
time.sleep(120)
'''


class Fixture:
    def __init__(self, case, *, service_seconds=10000, pump=True, plan_factory=None, external_service=False):
        self.temporary = tempfile.TemporaryDirectory(); case.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve(); self.folder = self.root / 'worker-service'
        self.pump_source = self.root / 'synthetic_pump.py'; self.pump_source.write_text(PUMP)
        self.sources = {str(p): worker.reference(p)['sha256'] for p in
                        (self.pump_source, Path(worker.__file__).resolve())}
        self.binding = dict(owner='/control/worker', device='synthetic-device', bundle='test.task',
            run_id=str(uuid.uuid4()), plan_sha256='1'*64, product_sha256='2'*64)
        self.requests = self.root / 'native/supported'; self.requests.mkdir(parents=True)
        self.budgets = dict(worker.budget_floors(dict(transport_seconds=31.7805211544,
            inspection_seconds=60.9894039631), steps=13, passive_snapshot=30, settle=2),
            passive_snapshot=30, settle=2)
        self.plan = plan_factory(self) if plan_factory else None
        if external_service:
            setup=dict(folder=str(self.folder),binding=self.binding,sources=self.sources,
                pump_source=worker.reference(self.pump_source),requests=str(self.requests),seconds=service_seconds)
            worker.save(self.root/'setup.json',setup)
            self.process=subprocess.Popen([sys.executable,'-B',worker.__file__,'--setup',str(self.root/'setup.json')],
                stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            def close():
                if self.process.poll() is None: self.process.terminate()
                self.process.communicate(timeout=5)
            case.addCleanup(close)
            cutoff=time.time()+5
            while not (self.folder/'service.json').exists():
                if self.process.poll() is not None: raise AssertionError(self.process.communicate()[1].decode())
                if time.time()>cutoff: raise AssertionError('local service did not start')
                time.sleep(.01)
            self.service=SimpleNamespace(record=worker.health(self.folder))
        else:
            self.service = worker.Service(self.folder, self.binding, self.sources,
                worker.reference(self.pump_source), self.requests, seconds=service_seconds)
            thread = threading.Thread(target=self.service.server.serve_forever, daemon=True); thread.start()
            def close():
                self.service.server.shutdown(); self.service.server.server_close(); thread.join(3)
            case.addCleanup(close)
        self.pump = None
        if pump:
            self.pump = subprocess.Popen([sys.executable, '-B', str(self.pump_source),
                str(Path(worker.__file__).parent), str(self.folder)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            def stop():
                if self.pump.poll() is None: self.pump.terminate()
                self.pump.communicate(timeout=5)
            case.addCleanup(stop)

    def answer(self):
        worker.probe(self.folder, self.binding)
        cutoff = time.time() + 5
        while not (self.folder / 'publication.json').exists():
            if self.pump.poll() is not None:
                raise AssertionError(self.pump.communicate()[1].decode())
            if time.time() > cutoff: raise AssertionError('synthetic pump did not answer')
            time.sleep(.01)
        worker.qualify(self.folder, self.binding, self.budgets)


class Readiness(unittest.TestCase):
    def test_pre_admission_cleanup_stops_only_owned_service_and_proves_absence(self):
        f=Fixture(self,external_service=True,pump=False)
        worker.stop_before_admission(f.folder,deadline=time.time()+10,
            expected_service=worker.reference(f.folder/'service.json'))
        stopped=worker.read(f.folder/'stop-result.json')
        self.assertEqual(stopped['state'],'OWNED_SERVICE_STOPPED')
        self.assertFalse(stopped['native_cleanup']); self.assertFalse(list(f.requests.iterdir()))
        with self.assertRaises(ValueError): worker.process_identity(stopped['pid'])

    def test_replaced_service_registration_cannot_kill_a_different_process(self):
        f=Fixture(self,external_service=True,pump=False); original=worker.reference(f.folder/'service.json')
        data=worker.read(f.folder/'service.json'); data['pid']=os.getpid()
        data['process_identity']=worker.process_identity(os.getpid()); (f.folder/'service.json').write_text(json.dumps(data))
        with patch.object(worker.os,'kill') as kill, self.assertRaisesRegex(ValueError,'bytes changed'):
            worker.stop_before_admission(f.folder,deadline=time.time()+10,expected_service=original)
        kill.assert_not_called(); self.assertIsNone(f.process.poll())

    def test_original_probe_cutoff_rejects_late_answer_and_preserves_raw_bytes(self):
        f=Fixture(self,pump=False); worker.probe(f.folder,f.binding,seconds=.01); time.sleep(.02)
        raw=json.dumps(dict(kind='TOOL_PUMP_PREPARED',binding=f.binding)).encode()
        request=urllib.request.Request(f.service.record['url']+'/answer',data=raw)
        with self.assertRaises(urllib.error.HTTPError): urllib.request.urlopen(request,timeout=3)
        self.assertEqual((f.folder/'answer.json').read_bytes(),raw)
        self.assertFalse((f.folder/'publication.json').exists())

    def test_actual_local_roundtrip_consumes_once_and_has_no_native_authority(self):
        f = Fixture(self); f.answer()
        before = time.time(); value = worker.consume(f.folder, f.binding, f.budgets)
        self.assertGreaterEqual(value['issued_at'], before)
        self.assertFalse(value['native_authority'])
        self.assertEqual(value['cleanup_deadline'] - value['execution_deadline'], f.budgets['cleanup'])
        self.assertEqual(worker.active(f.folder, worker.reference(f.folder/'consumed.json')), value)
        self.assertFalse(list(f.requests.iterdir()))
        self.assertEqual(worker.read(f.folder/'qualified.json')['gates_closed'], [])
        with self.assertRaises(FileExistsError): worker.consume(f.folder, f.binding, f.budgets)

    def test_declaration_and_actual_service_health_are_not_pump_readiness(self):
        f = Fixture(self, pump=False)
        self.assertEqual(worker.health(f.folder)['pid'], os.getpid())
        with self.assertRaises(ValueError): worker.qualify(f.folder, f.binding, f.budgets)
        worker.save(f.folder/'declaration.json', dict(state='PREPARED'))
        with self.assertRaises(ValueError): worker.consume(f.folder, f.binding, f.budgets)
        self.assertFalse((f.folder/'consumed.json').exists())

    def test_wrong_plan_owner_device_product_and_run_reject(self):
        f = Fixture(self); f.answer()
        for key in f.binding:
            changed = dict(f.binding, **{key: str(uuid.uuid4()) if key=='run_id' else 'foreign'})
            with self.subTest(key=key), self.assertRaises(ValueError):
                worker.consume(f.folder, changed, f.budgets)
        self.assertFalse((f.folder/'consumed.json').exists())

    def test_source_and_pump_process_replacement_reject(self):
        f = Fixture(self); f.answer(); f.pump.terminate(); f.pump.communicate(timeout=5)
        with self.assertRaises(ValueError): worker.consume(f.folder, f.binding, f.budgets)
        f.pump_source.write_text(PUMP + '\n# changed\n')
        with self.assertRaisesRegex(ValueError, 'source changed'): worker.health(f.folder)

    def test_setup_and_contract_byte_replacement_reject(self):
        for filename in ('pump-setup.json', 'pump-contract.json'):
            with self.subTest(filename=filename):
                f = Fixture(self); f.answer()
                path=f.folder/filename; data=worker.read(path); data['changed']=True
                path.write_text(json.dumps(data))
                with self.assertRaises(ValueError): worker.consume(f.folder, f.binding, f.budgets)

    def test_qualified_evidence_mutation_and_partial_publication_reject(self):
        for filename in ('service.json','probe.json','answer.json','publication.json','qualified.json'):
            with self.subTest(filename=filename):
                f=Fixture(self); f.answer(); path=f.folder/filename
                if filename=='qualified.json': data=worker.read(path); data['binding']['owner']='foreign'; path.write_text(json.dumps(data))
                else: path.write_text('{')
                with self.assertRaises((ValueError, KeyError)): worker.consume(f.folder,f.binding,f.budgets)
                self.assertFalse((f.folder/'consumed.json').exists())

    def test_stale_probe_and_insufficient_original_service_reserve_reject(self):
        f=Fixture(self); f.answer()
        with patch.object(worker.time,'time',return_value=worker.read(f.folder/'probe.json')['deadline']+1):
            with self.assertRaisesRegex(ValueError,'expired'): worker.consume(f.folder,f.binding,f.budgets)
        g=Fixture(self,service_seconds=180)
        worker.probe(g.folder,g.binding)
        cutoff=time.time()+5
        while not (g.folder/'publication.json').exists() and time.time()<cutoff: time.sleep(.01)
        with self.assertRaisesRegex(ValueError,'cover execution'): worker.qualify(g.folder,g.binding,g.budgets)

    def test_mutation_after_consumption_invalidates_positive_marker(self):
        f=Fixture(self); f.answer(); original=worker.save
        def save(path,value):
            original(path,value)
            if Path(path).name=='consumed.json': (f.folder/'publication.json').write_text('{}')
        with patch.object(worker,'save',side_effect=save), self.assertRaises(ValueError):
            worker.consume(f.folder,f.binding,f.budgets)
        self.assertFalse((f.folder/'consumed.json').exists())
        self.assertTrue((f.folder/'invalidated-consumed.json').exists())
        self.assertEqual(worker.read(f.folder/'consumed.json.failure.json')['state'],'INVALID')

    def test_changed_consumption_clocks_or_controller_at_publication_reject(self):
        for key in ('execution_deadline','cleanup_deadline','controller'):
            with self.subTest(key=key):
                f=Fixture(self); f.answer(); original=worker.save
                def save(path,value):
                    original(path,value)
                    if Path(path).name=='consumed.json':
                        changed=worker.read(path)
                        if key=='controller': changed[key]['identity']='replacement-controller'
                        else: changed[key]+=600
                        Path(path).write_text(json.dumps(changed))
                with patch.object(worker,'save',side_effect=save),self.assertRaisesRegex(ValueError,'issued consumption'):
                    worker.consume(f.folder,f.binding,f.budgets)
                self.assertFalse((f.folder/'consumed.json').exists())
                self.assertTrue((f.folder/'invalidated-consumed.json').exists())

    def test_rebound_consumption_reference_cannot_change_clocks_or_controller(self):
        for key in ('execution_deadline','cleanup_deadline','controller'):
            with self.subTest(key=key):
                f=Fixture(self); f.answer(); value=worker.consume(f.folder,f.binding,f.budgets)
                if key=='controller': value[key]=dict(pid=f.pump.pid,identity=worker.process_identity(f.pump.pid))
                else: value[key]+=600
                (f.folder/'consumed.json').write_text(json.dumps(value,sort_keys=True,indent=2)+'\n')
                with self.assertRaises(ValueError): worker.active(f.folder,worker.reference(f.folder/'consumed.json'))

    def test_changed_qualification_receipt_at_publication_rejects(self):
        f=Fixture(self); f.answer(); (f.folder/'qualified.json').unlink(); original=worker.save
        def save(path,value):
            original(path,value)
            if Path(path).name=='qualified.json':
                changed=worker.read(path); changed['at']+=1; Path(path).write_text(json.dumps(changed))
        with patch.object(worker,'save',side_effect=save),self.assertRaisesRegex(ValueError,'issued qualification'):
            worker.qualify(f.folder,f.binding,f.budgets)
        self.assertFalse((f.folder/'qualified.json').exists())
        self.assertTrue((f.folder/'invalidated-qualified.json').exists())

    def test_mutation_after_qualification_invalidates_positive_marker(self):
        f=Fixture(self); f.answer(); (f.folder/'qualified.json').unlink(); original=worker.save
        def save(path,value):
            original(path,value)
            if Path(path).name=='qualified.json': (f.folder/'answer.json').write_text('{}')
        with patch.object(worker,'save',side_effect=save), self.assertRaises(ValueError):
            worker.qualify(f.folder,f.binding,f.budgets)
        self.assertFalse((f.folder/'qualified.json').exists())
        self.assertTrue((f.folder/'invalidated-qualified.json').exists())

    def test_consumed_delivery_stays_available_until_end_and_completion(self):
        f=Fixture(self); f.answer(); worker.consume(f.folder,f.binding,f.budgets)
        with self.assertRaisesRegex(ValueError,'survive End'):
            worker.stop_before_admission(f.folder,deadline=time.time()+10,
                expected_service=worker.reference(f.folder/'service.json'))
        request=f.requests/'end'; request.mkdir()
        worker.save(request/'request.json',dict(binding=f.binding,operation='end'))
        with urllib.request.urlopen(f.service.record['url']+'/pending',timeout=3) as response:
            pending=json.load(response)
        self.assertEqual(pending,dict(kind='FILES',requests=[worker.reference(request/'request.json')]))
        worker.save(request/'response.json',dict(actual='simulated End return, not native evidence'))
        with urllib.request.urlopen(f.service.record['url']+'/pending',timeout=3) as response:
            self.assertEqual(json.load(response),dict(kind='FILES',requests=[]))
        with self.assertRaises(ValueError):
            worker.stop_owned(f.folder,deadline=time.time()+10,consumed=worker.reference(f.folder/'consumed.json'))

    def test_concurrent_consumption_has_exactly_one_winner(self):
        f=Fixture(self); f.answer(); results=[]
        def consume():
            try: worker.consume(f.folder,f.binding,f.budgets); results.append('PASS')
            except FileExistsError: results.append('REJECT')
        threads=[threading.Thread(target=consume) for _ in range(2)]
        for thread in threads: thread.start()
        for thread in threads: thread.join(5)
        self.assertEqual(sorted(results),['PASS','REJECT'])


class BudgetComposition(unittest.TestCase):
    def setUp(self):
        temporary=tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup); self.root=Path(temporary.name)
        request=dict(operation='action',binding=dict(owner='synthetic'),issued_at=10)
        worker.save(self.root/'request.json',request)
        worker.save(self.root/'response.json',dict(kind='AUTOMATIC_PREFIX_NO_CALL',input_calls=0,
            request=worker.reference(self.root/'request.json'),binding=request['binding'],owner='synthetic',published_at=71))
        worker.save(self.root/'assessment.json',dict(state='STOPPED_BEFORE_INPUT_ASSESSED',timings=dict(
            start=dict(ignored_startup=90),capture=dict(issued_to_claim_seconds=18,
                native_call_seconds=8,return_to_publication_seconds=6))))
        self.refs={k:worker.reference(self.root/(k+'.json')) for k in ('assessment','request','response')}
        self.ledger=worker.budget_ledger(self.refs,passive_snapshot=30,settle=2)

    def test_bound_thirteen_step_ledger_contains_every_serial_phase(self):
        self.assertEqual(worker.validate_ledger(self.ledger,self.ledger['budgets']),self.ledger)
        self.assertEqual(self.ledger['steps'],13); self.assertFalse(self.ledger['timing_acceptance'])
        self.assertEqual(self.ledger['per_step'],dict(returned_captures=2,image_inspections=2,passive_snapshots=4,settle=1))
        self.assertGreaterEqual(self.ledger['budgets']['native'],13*self.ledger['budgets']['step'])

    def test_old_90_second_step_and_each_underfunded_phase_reject(self):
        for key in ('request','step','native','cleanup'):
            budget=dict(self.ledger['budgets'],**{key:90 if key=='step' else 1})
            with self.subTest(key=key),self.assertRaises(ValueError): worker.validate_ledger(self.ledger,budget)

    def test_omitted_inspection_passive_or_bootstrap_costs_reject(self):
        for section,key in [('per_step','image_inspections'),('per_step','passive_snapshots'),
                            ('native_overhead','requests'),('cleanup_overhead','stop_restore_seconds')]:
            value=copy.deepcopy(self.ledger); del value[section][key]
            with self.subTest(key=key),self.assertRaises(ValueError): worker.validate_ledger(value,self.ledger['budgets'])

    def test_nonfinite_unbounded_or_changed_budget_sources_reject(self):
        for invalid in (float('nan'),float('inf'),True,-1,14401):
            budget=dict(self.ledger['budgets'],native=invalid)
            with self.subTest(value=invalid),self.assertRaises(ValueError): worker.validate_ledger(self.ledger,budget)
        (self.root/'request.json').write_text('{}')
        with self.assertRaises(ValueError): worker.validate_ledger(self.ledger,self.ledger['budgets'])


if __name__=='__main__': unittest.main()
