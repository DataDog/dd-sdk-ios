"""H04 activation-only semantics. No display, disconnect or peer-continuity credit."""
import json
import math
from pathlib import Path
from acceptance_common import require, require_before, require_identity, unique
from physical_same_key_contract import validate_backend as complete_backend_inventory

SCENARIO = 'windows.focus-activation-only'
PROFILE = 'physical-focus-activation-only'
PHASES = ['after-initial-activate-B','after-activate-A','after-reactivate-B','after-reactivate-A']
SCENES = ['scene-B','scene-A','scene-B','scene-A']
MARKERS = [4,7,10,13]


def contract():
    return json.loads(Path(__file__).with_name('focus-activation-scenario-contract.json').read_text())


def label(signal):
    return signal.get('semanticContext',{}).get('logicalSceneID')


def witness(signal, target, identities=None):
    require(signal.get('kind') == 'assertion' and signal.get('evidenceSource') == 'probe'
            and signal.get('result') == 'PASS' and signal.get('stepKind') == 'emit-marker', 'invalid focus witness')
    try:value = json.loads(signal['reason'])
    except (ValueError,TypeError,KeyError):require(False,'malformed focus witness')
    require(isinstance(value,dict),'focus witness is not an object')
    require(value.get('failure') is None and value.get('applicationActive') is True, 'native focus capture failed')
    continuity = value.get('continuity',{})
    require(continuity.get('failure') is None and continuity.get('owners'), 'missing focus continuity history')
    owners = continuity['owners']; scenes=value['scenes']; inputs=value['input']; inventory=value['inventory']
    require(all([x.get('logicalSceneID') for x in rows] == ['scene-A','scene-B'] for rows in [owners,scenes,inputs]),
            'missing, aliased or unordered focus owners')
    for key in ['nativeSceneID','sceneIdentity','windowIdentity','rootIdentity']:
        require(len({x.get(key) for x in owners}) == 2 and all(isinstance(x.get(key),str) and x[key] for x in owners),
                'missing or aliased '+key)
    require(all(type(x.get('generation')) is int and x['generation'] >= 0 for x in owners), 'invalid native generation')
    native = sorted(x['nativeSceneID'] for x in owners)
    require(sorted(value['connectedSceneIDs']) == native == sorted(x['nativeSceneID'] for x in inventory),
            'complete connected-scene inventory differs')
    result = {}
    for owner,scene,input_row in zip(owners,scenes,inputs):
        name=owner['logicalSceneID']; row=unique([x for x in inventory if x['nativeSceneID']==owner['nativeSceneID']], 'scene inventory')
        for key in ['logicalSceneID','nativeSceneID','generation','windowIdentity','rootIdentity']:
            require(scene.get(key)==input_row.get(key)==owner[key], 'changed native owner')
        require(scene.get('connected') is True and all(input_row.get(k) is True for k in ['attached','enabled','reliable'])
                and type(input_row.get('touches')) is int and input_row['touches']==0,
                'active or unobservable native input')
        observer=input_row.get('observerIdentity');require(isinstance(observer,str) and observer, 'missing input observer')
        expected='foreground-active' if name==target else 'background'
        require(scene.get('activationState')==row.get('activationState')==expected,'target not active or peer not background','INCONCLUSIVE')
        windows=row['windows'];require(len({x['identity'] for x in windows})==len(windows),'duplicate window inventory')
        window=unique([x for x in windows if x.get('fixtureOwner')==name], 'fixture-owned window')
        require(window['identity']==owner['windowIdentity'] and window.get('rootIdentity')==owner['rootIdentity']
                and window.get('sceneMatches') is True,'fixture window/controller mismatch')
        key=row.get('keyWindowIdentity');require([x['identity'] for x in windows if x.get('key') is True]==([] if key is None else [key]), 'key-window inventory differs')
        if name==target:
            alpha=window.get('alpha')
            require(key==owner['windowIdentity'] and window.get('hidden') is False and window.get('mounted') is True
                    and type(alpha) in [int,float] and math.isfinite(alpha) and alpha>0,'active owner is not the visible key window')
        result[name]=dict(owner,observerIdentity=observer)
    require(len({x['observerIdentity'] for x in result.values()})==2,'input observers alias')
    if identities is not None:require_identity(result,identities,'focus native owner binding')
    events=continuity.get('events');require(isinstance(events,list) and all(type(x.get('revision')) is int for x in events)
                and [x['revision'] for x in events]==list(range(1,len(events)+1)),'lost or reordered lifecycle history')
    return result,events


def validate_local(records, run_id, *, profile):
    require(profile==PROFILE,'wrong activation profile')
    manifest=unique([r['manifest'] for r in records if r.get('type')=='manifest'],'manifest')
    expected=contract()
    require(manifest.get('runID')==run_id and manifest.get('runMode')=='clean' and not manifest.get('validationErrors'), 'stale focus manifest')
    require_identity(manifest.get('scenario'),expected,'focus scenario')
    signals=[r['signal'] for r in records if r.get('type')=='signal']
    require(signals and all(s.get('runID')==run_id and s.get('scenarioID')==SCENARIO and s.get('schemaVersion')==5 for s in signals),'foreign focus signal')
    require([s.get('sequence') for s in signals]==list(range(1,len(signals)+1)),'incomplete focus stream')
    require(not any(s.get('result') in ['FAIL','INCONCLUSIVE'] for s in signals),'native focus admission failed','INCONCLUSIVE')
    require(not any(s.get('scenePhase')=='disconnected' or s.get('stepKind')=='close-window'
                    or 'destruction-request' in s.get('name','') for s in signals),'disconnect is outside the focus-only contract')
    terminal=unique([r for r in records if r.get('type')=='semantic-result'],'terminal')
    terminal_index=records.index(terminal)
    require(not any(r.get('type')=='signal' for r in records[terminal_index+1:]),
            'signal recorded after focus seal')
    result=terminal.get('result',{})
    require(terminal.get('runID')==run_id and result.get('scenarioID')==SCENARIO and result.get('state')=='PASS'
            and result.get('matchedExpectationCount')==15 and not result.get('issues'), 'focus timeline/completion did not seal','FAIL')
    starts=[s for s in signals if s.get('kind')=='step-started'];acks=[s for s in signals if s.get('kind')=='step-acknowledged']
    require(len(starts)==len(acks)==14,'incomplete focus driver')
    for i,(step,start,ack) in enumerate(zip(expected['steps'],starts,acks)):
        require(start.get('stepIndex')==ack.get('stepIndex')==i and start.get('stepKind')==ack.get('stepKind')==step['kind']
                and label(start)==label(ack)==step['scene'],'driver step identity differs')
        require_before(start,ack,'focus step acknowledgement')
        evidence=unique([s for s in signals if s['sequence']==ack.get('acknowledgedSignalSequence')],'acknowledged evidence')
        require_before(evidence,ack,'focus native evidence')
        if step['kind'] not in ['wait-for-scene-ready','wait-for-signal']:require_before(start,evidence,'fresh focus command')
        if i<13:require_before(ack,starts[i+1],'ordered focus driver')
    guards=[s for s in signals if s.get('name','').startswith('focus-activation-')]
    require(len(guards)==8,'missing or duplicated focus witnesses')
    identities=None; histories=[]
    for phase,scene,i in zip(PHASES,SCENES,MARKERS):
        before=unique([s for s in guards if s.get('name')==f'focus-activation-before-{i}'],'before focus witness')
        after=unique([s for s in guards if s.get('name')==f'focus-activation-after-{i}'],'after focus witness')
        require(before.get('stepIndex')==after.get('stepIndex')==i,'wrong focus guard index')
        require_before(starts[i],before,'fresh focus guard');require_before(before,after,'focus witness ordering');require_before(after,acks[i],'post-dispatch witness')
        identities,old=witness(before,scene,identities);_,new=witness(after,scene,identities)
        require(new==old,'lifecycle changed or history lost during marker','INCONCLUSIVE')
        if histories:require(old[:len(histories[-1])]==histories[-1],'history reset between markers')
        histories.append(new)
        activation=unique([s for s in signals if s['sequence']==acks[i-2]['acknowledgedSignalSequence']],'actual activation')
        require(activation.get('kind')=='scene-lifecycle' and label(activation)==scene and activation.get('activationState')=='foreground-active' and activation.get('semanticContext',{}).get('nativeSceneID')==identities[scene]['nativeSceneID'],'no actual target activation','INCONCLUSIVE')
        floor=starts[1 if i==4 else i-2]['sequence']
        for target,state in [(scene,'foreground-active'),('scene-A' if scene=='scene-B' else 'scene-B','background')]:
            latest=[s for s in signals if s.get('kind')=='scene-lifecycle' and label(s)==target and s['sequence']<before['sequence']]
            require(latest and latest[-1].get('activationState')==state and latest[-1]['sequence']>floor and latest[-1].get('semanticContext',{}).get('nativeSceneID')==identities[target]['nativeSceneID'],'stale target/peer lifecycle','INCONCLUSIVE')
        marker=unique([s for s in signals if s.get('kind')=='rum-action' and s.get('name')==phase],'focus marker Action')
        require_before(before,marker,'focus guard before marker');require_before(marker,after,'marker before post guard')
    native={k:v['nativeSceneID'] for k,v in identities.items()}
    inventory={};semantic={'scene-A':[],'scene-B':[]};work=[]
    for signal in signals:
        kind=signal.get('kind');context=signal.get('rumContext',{})
        require(kind!='rum-error','native RUM error','FAIL')
        if kind=='rum-view-snapshot':
            require(signal.get('evidenceSource')=='rum-mapper' and context.get('viewID') and context.get('sessionID'),'independent mapper view missing')
            key=context['viewID'];item=dict(view_id=key,session_id=context['sessionID'],name=context.get('viewName'))
            require(key not in inventory or inventory[key]==item,'view identity mutated');inventory[key]=item
            scene=label(signal)
            if scene in semantic:
                require(signal['semanticContext'].get('screen')=='home' and signal['semanticContext'].get('nativeSceneID') in [None,native[scene]],'foreign semantic view')
                if key not in semantic[scene]:semantic[scene].append(key)
    require([len(semantic[k]) for k in ['scene-A','scene-B']]==[3,2] and len(set(semantic['scene-A']+semantic['scene-B']))==5,'five distinct Home occurrences required','FAIL')
    require(inventory and len({x['session_id'] for x in inventory.values()})==1,'foreign session')
    session=next(iter(inventory.values()))['session_id']
    for signal in signals:
        kind=signal.get('kind')
        if kind not in ['rum-action','rum-resource']:continue
        context=signal.get('rumContext',{});source=signal.get('sourceContext',{})
        require(signal.get('evidenceSource')=='rum-mapper' and context.get('sessionID')==session and context.get('viewID') in inventory
                and signal.get('eventID'),'unknown work owner','FAIL')
        work.append(dict(kind=kind.removeprefix('rum-'),event_id=signal['eventID'],session_id=session,view_id=context['viewID'],phase=signal.get('name'),source_scene=source.get('logicalSceneID')))
    require(len({(x['kind'],x['event_id']) for x in work})==len(work),'duplicate local work')
    owners=[semantic['scene-B'][0],semantic['scene-A'][1],semantic['scene-B'][1],semantic['scene-A'][2]]
    for phase,scene,owner in zip(PHASES,SCENES,owners):
        for kind in ['rum-action','rum-resource']:
            signal=unique([s for s in signals if s.get('kind')==kind and s.get('name')==phase],phase+' '+kind)
            require(next(i for i,r in enumerate(records) if r.get('signal') is signal)<terminal_index,'selected marker completed after seal')
            require(signal['rumContext']['viewID']==owner and signal.get('sourceContext',{}).get('logicalSceneID')==scene
                    and signal['sourceContext'].get('nativeSceneID')==native[scene] and signal['sourceContext'].get('phase')==phase,'wrong exact focus work owner','FAIL')
    return dict(state='PASS',profile=PROFILE,session_id=session,views=list(inventory.values()),work=work,native_scenes=native,
                home_occurrences=semantic,marker_owners=dict(zip(PHASES,owners)),native_expectations=15,
                display_credit=False,disconnect_credit=False,peer_continuity_credit=False)


def validate_backend(local,run_id,rows,count,*,identity):
    require(set(identity)=={'application_id','service','source'} and all(isinstance(v,str) and v for v in identity.values()),'backend application/service/source identity missing')
    for row in rows:
        payload=row.get('attributes',{}).get('custom',{})
        require(payload.get('application',{}).get('id')==identity['application_id'] and payload.get('service')==identity['service']
                and payload.get('source')==identity['source'],'foreign backend application/service/source')
    result=complete_backend_inventory(local,run_id,rows,count);result['marker_pairs']=4
    return result
