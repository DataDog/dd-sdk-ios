"""Synthetic oracle controls only; these fixtures are never physical evidence."""
import copy
import json
import re
from pathlib import Path
import unittest
from acceptance_common import Rejected
from physical_serial_contract import validate_local, validate_backend, validate_shared_span_backend, APP_ID, SERVICE, SHARED


def fixture(gate):
    contract=json.loads(Path(__file__).with_name('physical-serial-scenario-contracts.json').read_text())[gate]
    signals=[]; latest={}; natives={'scene-A':'native-a','scene-B':'native-b'}
    def emit(kind,**fields):
        s=dict(kind=kind,runID='unit',scenarioID=contract['identifier'],schemaVersion=5,sequence=len(signals)+1,**fields)
        signals.append(s);return s
    def ready(label):
        latest[label]=emit('scene-ready',semanticContext=dict(logicalSceneID=label,nativeSceneID=natives[label]))
        owner=label+'-home';semantic=dict(logicalSceneID=label,nativeSceneID=natives[label],screen='home')
        fields=dict(evidenceSource='rum-mapper',rumContext=dict(sessionID='session',viewID=owner,viewName='ProbeHomeView',viewActive=True))
        if gate=='H05' and label=='scene-B':fields['rumContext']['viewName']='Automatic B'
        else:fields['semanticContext']=semantic
        emit('rum-view-snapshot',**fields)
    ready('scene-A')
    for index,step in enumerate(contract['steps']):
        emit('step-started',stepIndex=index,stepKind=step['kind'])
        kind=step['kind'];label=step.get('scene');phase=step.get('value')
        if kind in ['emit-marker','emit-scene-context-marker']:
            for family in ['action','resource']:
                evidence=emit('rum-'+family,evidenceSource='rum-mapper',eventID=family+'-'+phase,name=phase,
                              sourceContext=dict(logicalSceneID=label,nativeSceneID=natives[label]),
                              rumContext=dict(sessionID='session',viewID=label+'-home'))
        elif kind=='open-window':
            ready('scene-B');evidence=latest['scene-B']
        elif kind in ['start-trace-only-url-session-request','join-trace-only-url-session-request','complete-trace-only-url-session-request']:
            suffix={'start-trace-only-url-session-request':'started','join-trace-only-url-session-request':'joined','complete-trace-only-url-session-request':'completed'}[kind]
            source='scene-B' if suffix=='joined' else 'scene-A'
            evidence=emit('assertion',name='trace-only-request-'+suffix+'-'+SHARED,result='PASS',sourceContext=dict(logicalSceneID=source))
            if suffix=='completed':
                evidence=emit('rum-trace',evidenceSource='trace-mapper',name=SHARED,eventID='000000000000000a',
                    sourceContext=dict(logicalSceneID='scene-A',screen='home'),rumContext=dict(sessionID='session',viewID='scene-A-home'),
                    trace=dict(operationName='urlsession.request',serviceName=SERVICE,resourceName='https://multi-scene-probe.invalid/trace-only/unit/scene-A/home/'+SHARED,
                               traceID='0000000000000001000000000000000a',spanID='000000000000000a',parentSpanID='0000000000000000',
                               rumApplicationID=APP_ID,rumSessionID='session',rumViewID='scene-A-home',isError=False,
                               startTimeNanoseconds=1789842000123456789,startTimeMilliseconds=1789842000123,durationNanoseconds=123456789))
        else:evidence=latest[label]
        emit('step-acknowledged',stepIndex=index,stepKind=kind,acknowledgedSignalSequence=evidence['sequence'])
    return [dict(type='manifest',manifest=dict(runID='unit',runMode='clean',validationErrors=[],scenario=contract))]+[dict(type='signal',signal=s) for s in signals]+[dict(type='semantic-result',runID='unit',result=dict(scenarioID=contract['identifier'],state='PASS',matchedExpectationCount=7 if gate=='H05' else 8,issues=[]))]


class PhysicalSerialContractTests(unittest.TestCase):
    def testFrozenStepKindsExistInTheSwiftWireSchema(self):
        repo=Path(__file__).resolve().parents[3]
        source=(repo/'Datadog/Example/MultiSceneProbe/Sources/Harness/ProbeStep.swift').read_text()
        wire_kinds=set(re.findall(r'case \w+ = "([^"]+)"',source))
        contracts=json.loads(Path(__file__).with_name('physical-serial-scenario-contracts.json').read_text())
        for gate,contract in contracts.items():
            for step in contract['steps']:
                self.assertIn(step['kind'],wire_kinds,(gate,step))

    def testBothOriginalContractsAndExactInventory(self):
        for gate in ['H05','H07']:
            local=validate_local(fixture(gate),'unit',gate)
            rows=[]
            for v in local['views']:
                rows.append(dict(id=v['view_id'],attributes=dict(custom=dict(type='view',session=dict(id='session'),view=dict(id=v['view_id'],name=v['name']),context=dict(probe=dict(run_id='unit'))))))
            for w in local['work']:
                p=dict(type=w['kind'],session=dict(id='session'),view=dict(id=w['view_id']),context=dict(probe=dict(run_id='unit',phase=w['phase'],source_scene=w['source_scene'])))
                p[w['kind']]=dict(id=w['event_id']);rows.append(dict(id=w['event_id'],attributes=dict(custom=p)))
            self.assertEqual(validate_backend(local,'unit',rows,len(rows))['state'],'PASS')
            for mutation in ['missing','duplicate','foreign-owner','stale-run']:
                bad=copy.deepcopy(rows)
                if mutation=='missing':bad.pop()
                elif mutation=='duplicate':bad.append(copy.deepcopy(bad[-1]))
                elif mutation=='foreign-owner':bad[-1]['attributes']['custom']['view']['id']='foreign'
                else:bad[-1]['attributes']['custom']['context']['probe']['run_id']='old'
                with self.subTest(gate=gate,mutation=mutation),self.assertRaises(Rejected):validate_backend(local,'unit',bad,len(rows))

    def testNativeNegativeControls(self):
        for gate in ['H05','H07']:
            for mutation in ['stale-manifest','changed-steps','stale-signal','missing-signal','failed-terminal','alias-native','marker-wrong-owner','stopped-owner','late-view','stale-ack']:
                records=fixture(gate);signals=[r['signal'] for r in records if r['type']=='signal']
                marker=next(s for s in signals if s['kind']=='rum-action' and s['sourceContext']['logicalSceneID']=='scene-B')
                if mutation=='stale-manifest':records[0]['manifest']['runID']='old'
                elif mutation=='changed-steps':records[0]['manifest']['scenario']['steps'].pop()
                elif mutation=='stale-signal':signals[-1]['runID']='old'
                elif mutation=='missing-signal':signals[-1]['sequence']+=1
                elif mutation=='failed-terminal':records[-1]['result']['state']='FAIL'
                elif mutation=='alias-native':next(s for s in signals if s['kind']=='scene-ready' and s['semanticContext']['logicalSceneID']=='scene-B')['semanticContext']['nativeSceneID']='native-a'
                elif mutation=='marker-wrong-owner':marker['rumContext']['viewID']='scene-A-home'
                elif mutation=='stopped-owner':next(s for s in signals if s['kind']=='rum-view-snapshot' and s['rumContext']['viewID']=='scene-B-home')['rumContext']['viewActive']=False
                elif mutation=='late-view':next(s for s in signals if s['kind']=='rum-view-snapshot' and s['rumContext']['viewID']=='scene-B-home')['sequence']=marker['sequence']+1
                else:next(s for s in signals if s['kind']=='step-acknowledged' and s['stepKind'] in ['emit-marker','emit-scene-context-marker'])['acknowledgedSignalSequence']=1
                with self.subTest(gate=gate,mutation=mutation),self.assertRaises(Rejected):validate_local(records,'unit',gate)

    def testFullSpanJoinAndNegativeControls(self):
        local=validate_local(fixture('H07'),'unit','H07');t=local['span']
        row=dict(traceid=t['traceID'],spanid=str(int(t['spanID'],16)),parentid='0',
                 operationname=t['operationName'],service=t['serviceName'],resourcename=t['resourceName'],status='ok',error={},
                 starttimestamp='2026-09-19T18:20:00.123Z',custom=dict(probe=dict(run_id='unit'),http=dict(url=t['resourceName']),duration=t['durationNanoseconds']))
        detail=dict(span_id=row['spanid'],parent_id='0',name=t['operationName'],service=t['serviceName'],resource=t['resourceName'],
                    meta={'_dd.p.ftid':t['traceID'],'probe.run_id':'unit','_dd.application.id':APP_ID,'_dd.session.id':'session',
                          '_dd.view.id':'scene-A-home','http.url':t['resourceName']})
        self.assertEqual(validate_shared_span_backend(local,'unit',[row],1,[detail])['state'],'PASS')
        for mutation in ['extra-span','wrong-span','wrong-trace','wrong-owner','duration-rounded','wrong-start','wrong-url','stale-run','foreign-action']:
            r=copy.deepcopy(row);d=copy.deepcopy(detail);count=1
            if mutation=='extra-span':count=2
            elif mutation=='wrong-span':r['spanid']='11'
            elif mutation=='wrong-trace':r['traceid']='b'*32
            elif mutation=='wrong-owner':d['meta']['_dd.view.id']='scene-B-home'
            elif mutation=='duration-rounded':r['custom']['duration']+=1
            elif mutation=='wrong-start':r['starttimestamp']='2026-09-19T18:20:00.124Z'
            elif mutation=='wrong-url':r['custom']['http']['url']='other'
            elif mutation=='stale-run':r['custom']['probe']['run_id']='old'
            else:d['meta']['_dd.action.id']='foreign'
            with self.subTest(mutation=mutation),self.assertRaises(Rejected):validate_shared_span_backend(local,'unit',[r],count,[d])


        from datetime import datetime, timezone, timedelta
        base=datetime(2026,9,19,18,20,tzinfo=timezone.utc)
        for nanoseconds,milliseconds in [(0,0),(123499999,123),(123500000,124),(123999999,124),(999499999,999),(999500000,1000)]:
            projected=copy.deepcopy(local)
            projected['span']['startTimeNanoseconds']=1789842000000000000+nanoseconds
            projected['span']['startTimeMilliseconds']=1789842000000+nanoseconds//1000000
            r=copy.deepcopy(row);r['starttimestamp']=base+timedelta(milliseconds=milliseconds)
            with self.subTest(nanoseconds=nanoseconds):
                result=validate_shared_span_backend(projected,'unit',[r],1,[detail])
                self.assertEqual(result['backend_start_milliseconds'],1789842000000+milliseconds)
                self.assertTrue(result['start_projection_inferred'])
            for shift in [-1,1]:
                r['starttimestamp']=base+timedelta(milliseconds=milliseconds+shift)
                with self.subTest(nanoseconds=nanoseconds,shift=shift),self.assertRaises(Rejected):
                    validate_shared_span_backend(projected,'unit',[r],1,[detail])
        for invalid in [None,datetime(2026,9,19,18,20),base+timedelta(microseconds=123001)]:
            r=copy.deepcopy(row);r['starttimestamp']=invalid
            with self.subTest(invalid=invalid),self.assertRaises(Rejected):
                validate_shared_span_backend(local,'unit',[r],1,[detail])

    def testSharedSpanIdentityAndCapturedOwnerControls(self):
        for field,value in [('rumViewID','scene-B-home'),('rumApplicationID','foreign'),('traceID','x'),('spanID','a'),('startTimeNanoseconds',1.2),('durationNanoseconds',0),('isError',True),('rumActionIDs',['foreign'])]:
            records=fixture('H07');signal=next(r['signal'] for r in records if r['type']=='signal' and r['signal']['kind']=='rum-trace');signal['trace'][field]=value
            with self.subTest(field=field),self.assertRaises(Rejected):validate_local(records,'unit','H07')


if __name__=='__main__':unittest.main()
