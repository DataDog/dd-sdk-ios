"""Synthetic H04 discriminators only; these records never qualify a device run."""
import copy
import json
from pathlib import Path
import unittest
from acceptance_common import Rejected
import focus_activation_contract as p
import focus_activation_fixture as f

RUN='focus-unit-only'


def snapshot(target,native):
    owners=[];scenes=[];inputs=[];inventory=[]
    for label in ['scene-A','scene-B']:
        owner=dict(logicalSceneID=label,nativeSceneID=native[label],generation=0,
                   sceneIdentity='scene-object-'+label,windowIdentity='window-'+label,rootIdentity='root-'+label)
        owners.append(owner)
        active=label==target;state='foreground-active' if active else 'background'
        scenes.append({k:owner[k] for k in ['logicalSceneID','nativeSceneID','generation','windowIdentity','rootIdentity']} |
                      dict(connected=True,activationState=state,hidden=False,alpha=1,geometry=dict(x=0,y=0,width=1194,height=834)))
        inputs.append({k:owner[k] for k in ['logicalSceneID','nativeSceneID','generation','windowIdentity','rootIdentity']} |
                      dict(observerIdentity='observer-'+label,attached=True,enabled=True,reliable=True,touches=0,revision=0,mounted=True,transitioning=False,resizing=False))
        windows=[dict(identity=owner['windowIdentity'],rootIdentity=owner['rootIdentity'],fixtureOwner=label,sceneMatches=True,
                      key=active,hidden=False,alpha=1,mounted=True,geometry=dict(x=0,y=0,width=1194,height=834))]
        inventory.append(dict(nativeSceneID=native[label],activationState=state,keyWindowIdentity=owner['windowIdentity'] if active else None,
                              geometry=dict(x=0,y=0,width=1194,height=834),screenGeometry=dict(x=0,y=0,width=1194,height=834),windows=windows))
    return dict(scenes=scenes,input=inputs,connectedSceneIDs=sorted(native.values()),applicationActive=True,inventory=inventory,
                continuity=dict(owners=owners,events=[]))


def fixture():
    """Re-key test-only recorded shapes, then add explicitly synthetic guard data."""
    original=json.loads(Path(__file__).with_name('physical-activation-unit-fixture.json').read_text())['records']
    signals=[x['signal'] for x in original if x.get('type')=='signal']
    limit=next(s['sequence'] for s in signals if s.get('kind')=='step-started' and s.get('stepIndex')==14)
    native={label:next(s['semanticContext']['nativeSceneID'] for s in signals if s.get('kind')=='scene-lifecycle' and p.label(s)==label)
            for label in ['scene-A','scene-B']}
    selected=[copy.deepcopy(s) for s in signals if s['sequence']<limit or s.get('kind')=='rum-resource' and s.get('name') in p.PHASES]
    rows=[]
    for s in selected:
        s['runID']=RUN;s['scenarioID']=p.SCENARIO
        rows.append(s)
        if s.get('kind')=='step-started' and s.get('stepIndex') in p.MARKERS:
            i=s['stepIndex'];side='before'
        elif s.get('kind')=='rum-action' and s.get('name') in p.PHASES:
            i=p.MARKERS[p.PHASES.index(s['name'])];side='after'
        else:continue
        rows.append(dict(schemaVersion=5,sequence=f'{side}-{i}',runID=RUN,scenarioID=p.SCENARIO,kind='assertion',evidenceSource='probe',
                         stepIndex=i,stepKind='emit-marker',name=f'focus-activation-{side}-{i}',result='PASS',
                         reason=json.dumps(snapshot(p.SCENES[p.MARKERS.index(i)],native))))
    renumber={s['sequence']:i+1 for i,s in enumerate(rows)}
    for s in rows:
        s['sequence']=renumber[s['sequence']]
        if 'acknowledgedSignalSequence' in s:s['acknowledgedSignalSequence']=renumber[s['acknowledgedSignalSequence']]
    manifest=copy.deepcopy(original[0]['manifest']);manifest.update(runID=RUN,scenario=p.contract())
    return [dict(type='manifest',manifest=manifest)]+[dict(type='signal',signal=s) for s in rows]+[
        dict(type='semantic-result',runID=RUN,result=dict(scenarioID=p.SCENARIO,state='PASS',matchedExpectationCount=15,issues=[]))]


def guard(rows,side='before',index=4):
    return next(x['signal'] for x in rows if x.get('signal',{}).get('name')==f'focus-activation-{side}-{index}')


def mutate_guard(rows,change,side='before',index=4):
    s=guard(rows,side,index);value=json.loads(s['reason']);change(value);s['reason']=json.dumps(value)


def backend(local):
    identity=dict(application_id='app-unit',service='focus-fixture',source='ios');rows=[]
    for v in local['views']:
        rows.append(dict(id=str(len(rows)),attributes=dict(custom=dict(type='view',session=dict(id=local['session_id']),view=dict(id=v['view_id'],name=v['name']),context=dict(probe=dict(run_id=RUN))))))
    for w in local['work']:
        value=dict(type=w['kind'],session=dict(id=local['session_id']),view=dict(id=w['view_id']),context=dict(probe=dict(run_id=RUN,phase=w['phase'],source_scene=w['source_scene'])))
        value[w['kind']]=dict(id=w['event_id']);rows.append(dict(id=str(len(rows)),attributes=dict(custom=value)))
    for r in rows:r['attributes']['custom'].update(application=dict(id=identity['application_id']),service=identity['service'],source=identity['source'])
    return rows,identity


class FocusActivationTests(unittest.TestCase):
    def validate(self,rows):return p.validate_local(rows,RUN,profile=p.PROFILE)

    def test_explicit_complete_scope(self):
        value=self.validate(fixture());self.assertEqual(len(value['marker_owners']),4)
        self.assertEqual([len(x) for x in value['home_occurrences'].values()],[3,2]);self.assertFalse(value['display_credit'])
        self.assertEqual((len(p.contract()['steps']),len(p.contract()['expectedSemanticTimeline']),value['native_expectations']),(14,13,15))

    def test_native_identity_and_state_discriminators(self):
        cases=['inactive-peer','two-active','native-alias','window-replaced','root-replaced','observer-replaced','extra-connected','missing-inventory','wrong-key','touches','unreliable','lost-history','missing-continuity','nonfinite-alpha']
        for case in cases:
            rows=fixture()
            def change(v):
                if case in ['inactive-peer','two-active']:v['scenes'][0]['activationState']='foreground-inactive' if case=='inactive-peer' else 'foreground-active'
                elif case=='native-alias':v['continuity']['owners'][0]['nativeSceneID']=v['continuity']['owners'][1]['nativeSceneID']
                elif case=='window-replaced':v['input'][0]['windowIdentity']='other'
                elif case=='root-replaced':v['input'][1]['rootIdentity']='other'
                elif case=='observer-replaced':v['input'][1]['observerIdentity']='other'
                elif case=='extra-connected':v['connectedSceneIDs'].append('foreign')
                elif case=='missing-inventory':v['inventory'].pop()
                elif case=='wrong-key':v['inventory'][1]['keyWindowIdentity']='other'
                elif case=='touches':v['input'][1]['touches']=1
                elif case=='unreliable':v['input'][1]['reliable']=False
                elif case=='lost-history':v['continuity']['events']=[dict(revision=2,kind='scene-state',owner=v['continuity']['owners'][1])]
                elif case=='missing-continuity':v.pop('continuity')
                elif case=='nonfinite-alpha':v['inventory'][1]['windows'][0]['alpha']=float('nan')
            mutate_guard(rows,change,side='after')
            with self.subTest(case=case),self.assertRaises(Rejected):self.validate(rows)

    def test_auxiliary_window_is_not_rejected_by_count(self):
        rows=fixture()
        for row in rows:
            if row.get('signal',{}).get('name','').startswith('focus-activation-'):
                value=json.loads(row['signal']['reason']);value['inventory'][1]['windows'].append(dict(identity='auxiliary',key=False,fixtureOwner=None,sceneMatches=True));row['signal']['reason']=json.dumps(value)
        self.validate(rows)

    def test_mid_interval_lifecycle_revision_rejects_returned_matching_state(self):
        rows=fixture();mutate_guard(rows,lambda v:v['continuity']['events'].append(dict(revision=1,kind='activation',owner=v['continuity']['owners'][1])),side='after')
        with self.assertRaises(Rejected):self.validate(rows)

    def test_unowned_or_foreign_intervening_event_rejects(self):
        for owner in [None, dict(logicalSceneID='foreign',nativeSceneID='foreign')]:
            rows=fixture()
            mutate_guard(rows,lambda v:v['continuity']['events'].append(
                dict(revision=1,kind='window-notification',owner=owner)),side='after')
            with self.subTest(owner=owner),self.assertRaisesRegex(Rejected,'lifecycle changed'):
                self.validate(rows)

    def test_terminal_seals_all_semantic_signals(self):
        for kind in ['assertion','scene-lifecycle','rum-view-snapshot']:
            rows=fixture();last=max(r.get('signal',{}).get('sequence',0) for r in rows)
            rows.append(dict(type='signal',signal=dict(schemaVersion=5,sequence=last+1,
                runID=RUN,scenarioID=p.SCENARIO,kind=kind,name='late-record')))
            with self.subTest(kind=kind),self.assertRaisesRegex(Rejected,'after focus seal'):
                self.validate(rows)

    def test_ordered_history_cannot_reset_between_markers(self):
        rows=fixture()
        for side in ['before','after']:mutate_guard(rows,lambda v:v['continuity']['events'].append(dict(revision=1,kind='activation',owner=v['continuity']['owners'][1])),side=side)
        with self.assertRaises(Rejected):self.validate(rows)

    def test_wrong_profile_and_old_manifest(self):
        with self.assertRaises(Rejected):p.validate_local(fixture(),RUN,profile='physical-activation')
        rows=fixture();rows[0]['manifest']['scenario']['identifier']='windows.activation-sequence'
        with self.assertRaises(Rejected):self.validate(rows)

    def test_stale_lifecycle_and_wrong_native_identity(self):
        for case in ['stale','native']:
            rows=fixture();signals=[r['signal'] for r in rows if r.get('type')=='signal'];ack=next(s for s in signals if s.get('kind')=='step-acknowledged' and s.get('stepIndex')==5)
            if case=='stale':ack['acknowledgedSignalSequence']=next(s['sequence'] for s in signals if s.get('kind')=='scene-lifecycle')
            else:next(s for s in signals if s['sequence']==ack['acknowledgedSignalSequence'])['semanticContext']['nativeSceneID']='foreign'
            with self.subTest(case=case),self.assertRaises(Rejected):self.validate(rows)

    def test_wrong_missing_duplicate_work_and_home(self):
        for case in ['action-owner','resource-owner','phase','missing-home','aliased-home','duplicate-work','run']:
            rows=fixture();signals=[r['signal'] for r in rows if r.get('type')=='signal'];action=next(s for s in signals if s.get('kind')=='rum-action' and s.get('name')==p.PHASES[1]);resource=next(s for s in signals if s.get('kind')=='rum-resource' and s.get('name')==p.PHASES[1])
            if case=='action-owner':action['rumContext']['viewID']='foreign'
            elif case=='resource-owner':resource['rumContext']['viewID']='foreign'
            elif case=='phase':resource['sourceContext']['phase']='other'
            elif case=='missing-home':
                for s in signals:
                    if s.get('kind')=='rum-view-snapshot' and p.label(s)=='scene-B':s.pop('semanticContext')
            elif case=='aliased-home':
                for s in signals:
                    if s.get('kind')=='rum-view-snapshot' and p.label(s)=='scene-B':s['rumContext']['viewID']=action['rumContext']['viewID']
            elif case=='duplicate-work':resource['eventID']=next(s['eventID'] for s in signals if s.get('kind')=='rum-resource')
            elif case=='run':action['runID']='old'
            with self.subTest(case=case),self.assertRaises(Rejected):self.validate(rows)

    def test_missing_late_guard_and_terminal_completion(self):
        for case in ['missing','late','terminal','resource-after-seal','disconnect']:
            rows=fixture()
            if case=='missing':guard(rows)['name']='missing'
            elif case=='late':guard(rows)['sequence']=guard(rows,'after')['sequence']
            elif case=='terminal':rows[-1]['result']['matchedExpectationCount']=13
            elif case=='resource-after-seal':
                row=next(r for r in rows if r.get('signal',{}).get('kind')=='rum-resource' and r['signal'].get('name')==p.PHASES[-1]);rows.remove(row);rows.append(row)
            else:
                last=max(r.get('signal',{}).get('sequence',0) for r in rows);rows.insert(-1,dict(type='signal',signal=dict(schemaVersion=5,sequence=last+1,runID=RUN,scenarioID=p.SCENARIO,kind='scene-lifecycle',scenePhase='disconnected')))
            with self.subTest(case=case),self.assertRaises(Rejected):self.validate(rows)

    def test_elapsed_time_is_not_an_acceptance_threshold(self):
        rows=fixture()
        for r in rows:
            if r.get('type')=='signal':r['signal']['timestampMilliseconds']=r['signal']['sequence']*100000000
        self.validate(rows)

    def test_backend_complete_identity_and_pagination(self):
        local=self.validate(fixture());rows,identity=backend(local);self.assertEqual(p.validate_backend(local,RUN,rows,len(rows),identity=identity)['marker_pairs'],4)
        for case in ['app','service','source','truncated','duplicate','owner','run','session','error']:
            bad=copy.deepcopy(rows);last=bad[-1]['attributes']['custom']
            if case=='app':last['application']['id']='foreign'
            elif case in ['service','source']:last[case]='foreign'
            elif case=='truncated':bad.pop()
            elif case=='duplicate':bad.append(copy.deepcopy(bad[-1]))
            elif case=='owner':last['view']['id']='foreign'
            elif case=='run':last['context']['probe']['run_id']='old'
            elif case=='session':last['session']['id']='foreign'
            elif case=='error':last['type']='error'
            with self.subTest(case=case),self.assertRaises(Rejected):p.validate_backend(local,RUN,bad,len(rows),identity=identity)


class FocusFixtureTests(unittest.TestCase):
    def test_separate_scenario_leaves_original_block_identical(self):
        raw=(f.PROBE/f.CATALOG).read_bytes();rendered=f.render(f.CATALOG,raw).decode();old=raw.decode()
        start='    private static let windowsActivationSequence = ProbeScenario(';end='    private static let actionsExactSourceHandoff = ProbeScenario('
        self.assertEqual(old[old.index(start):old.index(end)],rendered[rendered.index(start):rendered.index(end)])
        fresh=rendered[rendered.index('    private static let windowsFocusActivationOnly'):rendered.index(start)]
        self.assertNotIn('.closeWindow',fresh);self.assertNotIn('.sceneDisconnected',fresh);self.assertEqual(fresh.count('ProbeStep('),14)

    def test_stale_catalog_and_app_reject_before_copy(self):
        for name in f.ORIGINAL:
            with self.subTest(name=name),self.assertRaises(Rejected):f.render(name,(f.PROBE/name).read_bytes()+b'\n')

    def test_profile_is_required_before_input_observer_and_marker_dispatch(self):
        text=f.render(f.APP,(f.PROBE/f.APP).read_bytes()).decode()
        self.assertIn('DD_PROBE_FOCUS_ACTIVATION_PROFILE',text);self.assertIn('focus activation profile is not armed',text)
        self.assertIn('focus.check(index: index, step: step, after: after)',text)
        self.assertNotIn('requestSceneSessionDestruction',text[text.index('private final class ProbeFocusActivationAdmission'):])


if __name__=='__main__':unittest.main()
