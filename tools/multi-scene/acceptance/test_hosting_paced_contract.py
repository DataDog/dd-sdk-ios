import copy
import importlib.util
from pathlib import Path
import unittest
import uuid
from acceptance_common import Rejected
import hosting_paced_contract as c
from test_hosting_contract import fixture as original_fixture


def fixture():
    document=original_fixture();document['identity'].update(arm='B',mode='manual')
    launch=next(r for r in document['records'] if r['kind']=='launch');launch.update(mode='manual',automatic_swiftui=False)
    rows=[]
    for row in document['records']:
        if row['kind']=='transition-start':
            phase=row['phase'];index=c.PHASES.index(phase);request=str(uuid.uuid4());controller=['root','detail','root','modal'][index]
            names=['root']+(['detail'] if index>=1 else [])+(['modal'] if index>=3 else [])
            attachments={name:{'controller':name,'loaded':True,'window':'window' if name==controller else None} for name in names}
            rows.append({'kind':'human-ready','phase':phase,'request_id':request,'control':'hosting.'+phase,
                         'controller':controller,'window':'window','attachments':attachments})
            rows.append({'kind':'human-input','phase':phase,'request_id':request,'controller':controller,'window':'window'})
        rows.append(row)
    for index,row in enumerate(rows,1):
        row.update(sequence=index,monotonic_ns=index*1000,wall_ms=index)
        if row['kind']=='human-ready':row.update(issued_ns=index*1000-1,deadline_ns=index*1000+180_000_000_000-1)
        if row['kind']=='human-input':row['consumed_ns']=index*1000
    document.update(records=rows,durable_sequence=len(rows));return document


class PacedControls(unittest.TestCase):
    def setUp(self):self.doc=fixture()
    def row(self,kind,phase):return next(r for r in self.doc['records'] if r['kind']==kind and r.get('phase')==phase)
    def rejected(self):
        with self.assertRaises(Rejected):c.local(self.doc,self.doc['identity'])
    def test_valid_retains_existing_strict_oracle(self):
        result=c.local(self.doc,self.doc['identity']);self.assertEqual(result['human_input']['attachment_observations'],4)
    def test_other_arms_not_readmitted(self):self.doc['identity']['arm']='A';self.rejected()
    def test_missing_original_lifecycle_still_rejected(self):
        next(r for r in self.doc['records'] if r['kind']=='swiftui-disappear')['kind']='missing';self.rejected()
    def test_missing_or_foreign_attachment_rejected(self):
        for mutation in ['missing','foreign']:
            self.doc=fixture();attachments=self.row('human-ready','pop')['attachments']
            if mutation=='missing':attachments.pop('root')
            else:attachments['root']['controller']='foreign'
            with self.subTest(mutation=mutation):self.rejected()
    def test_offscreen_attachment_observed_without_requiring_nil(self):
        self.row('human-ready','pop')['attachments']['root']['window']='window';c.local(self.doc,self.doc['identity'])
    def test_current_controller_cannot_be_detached(self):self.row('human-ready','pop')['attachments']['detail']['window']=None;self.rejected()
    def test_expired_request_rejected(self):self.row('human-input','pop')['consumed_ns']=self.row('human-ready','pop')['deadline_ns'];self.rejected()
    def test_reused_readiness_rejected(self):self.row('human-input','pop')['request_id']=self.row('human-ready','push')['request_id'];self.rejected()
    def test_wrong_window_rejected(self):self.row('human-input','pop')['window']='foreign';self.rejected()
    def test_input_after_transition_rejected(self):self.row('human-input','pop')['sequence']=self.row('transition-start','pop')['sequence']+1;self.rejected()
    def test_deadline_extension_rejected(self):self.row('human-ready','pop')['deadline_ns']+=1;self.rejected()


class GeneratorControls(unittest.TestCase):
    def setUp(self):
        root=Path(__file__).resolve().parents[1]/'hosted-swiftui';spec=importlib.util.spec_from_file_location('paced_variant',root/'paced_variant.py')
        self.module=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.module);self.source=(root/'App.swift').read_bytes()
    def test_preserves_tracking_calls_and_original_source(self):
        rendered=self.module.render(self.source,self.module.BASE_SHA256)
        for call in ['.trackRUMView(', 'RUMMonitor.shared()', 'RUM.enable(', 'DefaultSwiftUIRUMViewsPredicate()']:
            self.assertEqual(rendered.decode().count(call),self.source.decode().count(call))
        self.assertEqual(rendered.count(b'try await humanStep('),4)
    def test_changed_source_rejected(self):
        with self.assertRaises(Rejected):self.module.render(self.source+b'\n',self.module.BASE_SHA256)
    def test_changed_anchor_rejected_even_with_new_hash(self):
        import hashlib
        changed=self.source.replace(b'phase = "push"',b'phase = "unqualified"')
        with self.assertRaises(Rejected):self.module.render(changed,hashlib.sha256(changed).hexdigest())

if __name__=='__main__':unittest.main()
