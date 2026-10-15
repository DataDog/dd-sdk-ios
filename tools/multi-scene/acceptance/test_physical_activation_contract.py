"""Regression discriminators; synthetic success is never physical evidence."""
import copy
import json
from pathlib import Path
import unittest
from acceptance_common import Rejected
import physical_activation_contract as p

RUN='exp196-unit-activation'

def fixture():
    return json.loads(Path(__file__).with_name('physical-activation-unit-fixture.json').read_text())['records']

class PhysicalActivationTests(unittest.TestCase):
    def test_complete_contract(self):
        local=p.validate_local(fixture(),RUN)
        self.assertEqual([len(v) for v in local['home_occurrences'].values()],[3,2])
        self.assertEqual(len(local['marker_owners']),5)

    def test_activation_and_teardown_discriminators(self):
        for case in ['old-contract','old-run','missing-terminal','failed-terminal','missing-ack','stale-activation',
                     'peer-active','late-background','native-alias','wrong-native-marker','wrong-owner','wrong-resource',
                     'old-occurrence','no-disconnect','wrong-destroy-target','late-destroy','no-destroy','extra-phase','native-error']:
            with self.subTest(case=case):
                rows=fixture();ss=[x['signal'] for x in rows if x['type']=='signal']
                act=next(s for s in ss if s.get('kind')=='rum-action' and s.get('name')==p.PHASES[1])
                start=next(s for s in ss if s.get('kind')=='step-started' and s.get('stepIndex')==7)
                bg=[s for s in ss if s.get('kind')=='scene-lifecycle' and s.get('activationState')=='background'
                    and s.get('semanticContext',{}).get('logicalSceneID')=='scene-B' and s['sequence']<start['sequence']][-1]
                destroy=next(s for s in ss if s.get('name')=='physical-scene-destruction-requested')
                if case=='old-contract': rows[0]['manifest']['scenario']['steps'].pop()
                elif case=='old-run': act['runID']='old'
                elif case=='missing-terminal': rows.pop()
                elif case=='failed-terminal': rows[-1]['result']['state']='FAIL'
                elif case=='missing-ack': next(s for s in ss if s.get('kind')=='step-acknowledged')['kind']='assertion'
                elif case=='stale-activation': next(s for s in ss if s.get('stepIndex')==5 and s.get('kind')=='step-acknowledged')['acknowledgedSignalSequence']=22
                elif case=='peer-active': bg['activationState']='foreground-active'
                elif case=='late-background': bg['sequence']=start['sequence']+1
                elif case=='native-alias': bg['semanticContext']['nativeSceneID']='foreign'
                elif case=='wrong-native-marker': act['sourceContext']['nativeSceneID']='foreign'
                elif case=='wrong-owner': act['rumContext']['viewID']=next(s['rumContext']['viewID'] for s in ss if s.get('kind')=='rum-action' and s.get('name')==p.PHASES[0])
                elif case=='wrong-resource': next(s for s in ss if s.get('kind')=='rum-resource' and s.get('name')==p.PHASES[1])['rumContext']['viewID']='foreign'
                elif case=='old-occurrence':
                    initial=next(s['rumContext']['viewID'] for s in ss if s.get('kind')=='rum-view-snapshot' and s.get('semanticContext',{}).get('logicalSceneID')=='scene-A')
                    act['rumContext']['viewID']=initial
                elif case=='no-disconnect': next(s for s in ss if s.get('scenePhase')=='disconnected')['scenePhase']='ready'
                elif case=='wrong-destroy-target':destroy['semanticContext']['logicalSceneID']='scene-A'
                elif case=='late-destroy':destroy['sequence']=ss[-1]['sequence']
                elif case=='no-destroy':destroy['name']='unqualified'
                elif case=='extra-phase': next(s for s in ss if s.get('kind')=='rum-action' and s.get('name')==p.PHASES[0])['name']=p.PHASES[1]
                elif case=='native-error':destroy['kind']='rum-error'
                with self.assertRaises(Rejected):p.validate_local(rows,RUN)

    def test_complete_backend_discriminators(self):
        local=p.validate_local(fixture(),RUN);rows=[]
        for v in local['views']:
            rows.append(dict(id=str(len(rows)),attributes=dict(custom=dict(type='view',session=dict(id=local['session_id']),view=dict(id=v['view_id'],name=v['name']),context=dict(probe=dict(run_id=RUN))))))
        for w in local['work']:
            c=dict(type=w['kind'],session=dict(id=local['session_id']),view=dict(id=w['view_id']),context=dict(probe=dict(run_id=RUN,phase=w['phase'],source_scene=w['source_scene'])))
            c[w['kind']]=dict(id=w['event_id']);rows.append(dict(id=str(len(rows)),attributes=dict(custom=c)))
        self.assertEqual(p.validate_backend(local,RUN,rows,len(rows))['marker_pairs'],5)
        for case in ['truncated','extra','owner','run','session','error','id']:
            bad=copy.deepcopy(rows)
            if case=='truncated':bad.pop()
            elif case=='extra':bad.append(copy.deepcopy(rows[-1]));bad[-1]['id']='extra'
            elif case=='owner':bad[-1]['attributes']['custom']['view']['id']='foreign'
            elif case=='run':bad[-1]['attributes']['custom']['context']['probe']['run_id']='old'
            elif case=='session':bad[-1]['attributes']['custom']['session']['id']='foreign'
            elif case=='error':bad[-1]['attributes']['custom']['type']='error'
            elif case=='id':bad[-1]['id']=bad[0]['id']
            with self.subTest(case=case),self.assertRaises(Rejected):p.validate_backend(local,RUN,bad,len(rows))

if __name__=='__main__':unittest.main()
