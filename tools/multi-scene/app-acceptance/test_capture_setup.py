import copy
import json
from pathlib import Path
import tempfile
import unittest

from capture_contract import encoder_setup, setup_specimens, prefix
from test_capture_contract import IDENTITY, payload, encode


def receipt():
    return dict(schema_version=1, policy='concrete-event-encoding-v1', identity=IDENTITY, pid=12,
                success=True, started_ns=1, finished_ns=51,
                families=[dict(family=k, specimen_sha256=v, encoded_bytes=100, duration_ns=10)
                          for k,v in setup_specimens().items()])


class EncoderSetupTests(unittest.TestCase):
    def test_complete_concrete_family_setup_precedes_configured_observation(self):
        rows,_=payload()
        row=rows[0];row.update(request_id=None,phase=None)
        self.assertEqual(encoder_setup(json.dumps(receipt()),IDENTITY,12,row)['success'],True)
        with self.assertRaises(ValueError):encoder_setup(json.dumps(receipt()),IDENTITY,12,dict(row,capture_started_ns=50))
        with self.assertRaises(ValueError):encoder_setup(json.dumps(receipt()),IDENTITY,12,dict(row,request_id=IDENTITY['nonce']))

    def test_failed_foreign_and_partial_setup_never_qualify(self):
        cases=[]
        for key,value in [('success',False),('success',1),('schema_version',True),('policy','old'),('identity',{}),
                          ('pid',99),('pid',True),('started_ns',True),('finished_ns',2),('families',[])]:
            r=receipt();r[key]=value;cases.append(r)
        for key,value in [('specimen_sha256','0'*64),('family','error'),('duration_ns',True),('duration_ns',0),('encoded_bytes',0)]:
            r=receipt();r['families'][1][key]=value;cases.append(r)
        r=receipt();r['families'].reverse();cases.append(r)
        r=receipt();r['families'].pop(1);cases.append(r)
        r=receipt();del r['identity'];cases.append(r)
        for r in cases:
            with self.subTest(r=r),self.assertRaises(ValueError):encoder_setup(json.dumps(r),IDENTITY,12)

    def test_specimen_hash_binds_exact_frozen_source_bytes(self):
        source=Path(__file__).with_name('ReleaseValidationCapture.swift').read_text()
        with tempfile.TemporaryDirectory() as name:
            path=Path(name)/'capture.swift'
            path.write_text(source.replace('"action": #"','"unknown": #"',1))
            with self.assertRaises(ValueError):setup_specimens(path)
            path.write_text(source.replace('validation-recorder-setup','changed-recorder-setup',1))
            self.assertNotEqual(setup_specimens(path),setup_specimens())

    def test_first_real_event_keeps_original_cost_caps_in_every_phase(self):
        encoder_setup(json.dumps(receipt()),IDENTITY,12)
        for family in ['action','view','resource','error','long_task']:
            for phase in [None,'process-session-binding-0','first-human-action']:
                rows,_=payload([('mapper',dict(family=family,accepted=True,event_json=json.dumps(dict(type=family))))])
                for row in rows:row['phase']=phase
                rows[-1]['fields']['duration_ns']=10_000_000
                prefix(*encode(rows),IDENTITY)
                rows[-1]['fields']['duration_ns']+=1
                with self.subTest(family=family,phase=phase),self.assertRaisesRegex(ValueError,'frozen limit'):
                    prefix(*encode(rows),IDENTITY)
        for kind,limit,fields in [('predicate_result',2_000_000,{}),('browser_message',10_000_000,
                                  dict(event_json='{"source":"browser"}',scope='raw_browser_source_payload')),
                                 ('snapshot',100_000_000,{})]:
            rows,_=payload([(kind,fields)]);rows[-1]['fields']['duration_ns']=limit+1
            with self.assertRaisesRegex(ValueError,'frozen limit'):prefix(*encode(rows),IDENTITY)

    def test_initial_binding_stops_before_snapshot_if_setup_failed(self):
        from types import SimpleNamespace
        from unittest.mock import Mock, patch
        import journey_workflow
        for bad in [dict(receipt(),success=False),dict(receipt(),pid=99)]:
            with tempfile.TemporaryDirectory() as name:
                root=Path(name);documents=root/'documents';documents.mkdir();out=root/'out';out.mkdir()
                (documents/'encoder-setup.json').write_text(json.dumps(bad))
                driver=SimpleNamespace(deadline=99999999999,out=out,collector=SimpleNamespace(directory=documents,identity=IDENTITY,snapshot=Mock()),expected={'pid':12},live=Mock())
                with self.assertRaises(ValueError):journey_workflow.initial_session(driver,{},set())
                driver.collector.snapshot.assert_not_called()
                self.assertEqual(json.loads((out/'encoder-setup.json').read_text()),bad)

    def test_setup_publication_cannot_bypass_the_writer_checkpoint(self):
        from types import SimpleNamespace
        import threading
        import time
        from capture_io import Collector, atomic, encoded
        import journey_workflow
        for publication_delay in [0, .03]:
            with tempfile.TemporaryDirectory() as name:
                root=Path(name);documents=root/'documents';documents.mkdir();output=root/'output';output.mkdir();captured=root/'capture';captured.mkdir()
                end=time.time()+.12
                collector=Collector(documents,captured,IDENTITY,12,lambda:True,deadline=end,snapshot_seconds=.1)
                collector.directory.mkdir()
                def publish():atomic(collector.directory/'encoder-setup.json',encoded(receipt()))
                worker=threading.Timer(publication_delay,publish);worker.start()
                def live(deadline):
                    if time.time()>=deadline:raise ValueError('deadline expired')
                driver=SimpleNamespace(deadline=end,out=output,collector=collector,expected={'pid':12},live=live)
                try:
                    with self.assertRaisesRegex(ValueError,'deadline'):journey_workflow.initial_session(driver,{},set())
                finally:worker.join()
                self.assertTrue((output/'encoder-setup.json').is_file())
                self.assertFalse((collector.directory/'events.jsonl').exists())
                self.assertFalse(any(p.name=='session-binding.json' for p in captured.rglob('*')))

    def test_old_or_asymmetric_capture_products_stop_during_preparation(self):
        import journey_workflow
        from acceptance_common import Rejected
        source=Path(__file__).with_name('ReleaseValidationCapture.swift')
        relative='Targets/Platform/DatadogObservability/ReleaseValidationCapture.swift'
        for mode in ['smoke','journeys']:
            with tempfile.TemporaryDirectory() as name:
                root=Path(name);arms={}
                for arm in ['baseline','candidate']:
                    app=root/arm;path=app/relative;path.parent.mkdir(parents=True);path.write_bytes(source.read_bytes())
                    arms[arm]={'app':str(app)}
                prep=dict(arms=arms,overlay_sha256={relative:journey_workflow.builds.sha(source)})
                (root/'preparation.json').write_text(json.dumps(prep));definition=dict(mode=mode,source_manifest={})
                journey_workflow.source_manifest(root,definition)
                (root/'candidate'/relative).write_text('old recorder')
                with self.assertRaises(Rejected):journey_workflow.source_manifest(root,definition)
                (root/'candidate'/relative).write_bytes(source.read_bytes());prep['overlay_sha256'][relative]='0'*64
                (root/'preparation.json').write_text(json.dumps(prep))
                with self.assertRaises(Rejected):journey_workflow.source_manifest(root,definition)

    def test_setup_does_not_allow_missing_cost_or_synthetic_event_family(self):
        encoder_setup(json.dumps(receipt()),IDENTITY,12)
        rows,_=payload([('encoder_setup',{})])
        with self.assertRaises(ValueError):prefix(*encode(rows),IDENTITY)
        rows,_=payload([('mapper',dict(family='action',accepted=True,event_json='{"type":"action"}'))])
        with self.assertRaises(ValueError):prefix(*encode(rows[:-1]),IDENTITY)


if __name__=='__main__':unittest.main()
