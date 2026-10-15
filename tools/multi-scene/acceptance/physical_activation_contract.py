"""H04: actual physical activation and background boundaries with exact owners."""
import json
from pathlib import Path
from acceptance_common import require, require_before, require_identity, unique
from physical_same_key_contract import validate_backend as complete_backend_inventory

SCENARIO = 'windows.activation-sequence'
PHASES = ['after-initial-activate-B', 'after-activate-A', 'after-reactivate-B',
          'after-reactivate-A', 'after-activated-peer-close']
SCENES = ['scene-B', 'scene-A', 'scene-B', 'scene-A', 'scene-A']


def validate_local(records, run_id):
    manifest = unique([r['manifest'] for r in records if r['type'] == 'manifest'], 'manifest')
    expected = json.loads(Path(__file__).with_name('physical-activation-scenario-contract.json').read_text())
    require(manifest.get('runID') == run_id and manifest.get('runMode') == 'clean'
            and not manifest.get('validationErrors'), 'stale/invalid activation manifest')
    require_identity(manifest.get('scenario'), expected, 'activation scenario')
    signals = [r['signal'] for r in records if r['type'] == 'signal']
    require(signals and all(s.get('runID') == run_id and s.get('scenarioID') == SCENARIO
                           and s.get('schemaVersion') == 5 for s in signals), 'stale activation signals')
    require([s['sequence'] for s in signals] == list(range(1, len(signals)+1)), 'incomplete signal sequence')
    require(not any(s.get('result') in ['FAIL', 'INCONCLUSIVE'] for s in signals), 'native activation failed', 'INCONCLUSIVE')
    terminal = unique([r for r in records if r['type'] == 'semantic-result'], 'terminal')
    result = terminal.get('result', {})
    require(terminal.get('runID') == run_id and result.get('scenarioID') == SCENARIO
            and result.get('state') == 'PASS' and result.get('matchedExpectationCount') == 19
            and not result.get('issues'), 'original 19 activation expectations failed', 'FAIL')
    starts = [s for s in signals if s.get('kind') == 'step-started']
    acks = [s for s in signals if s.get('kind') == 'step-acknowledged']
    require(len(starts) == len(acks) == 16, 'incomplete activation driver')
    for i, (step, start, ack) in enumerate(zip(expected['steps'], starts, acks)):
        require(start.get('stepIndex') == ack.get('stepIndex') == i
                and start.get('stepKind') == ack.get('stepKind') == step['kind'], 'step identity')
        require_before(start, ack, 'step acknowledgement')
        evidence = unique([s for s in signals if s['sequence'] == ack.get('acknowledgedSignalSequence')], 'ack evidence')
        require_before(evidence, ack, 'native evidence before ack')
        if step['kind'] not in ['wait-for-scene-ready', 'wait-for-signal']:
            require_before(start, evidence, 'fresh command evidence')
        if i < 15: require_before(ack, starts[i+1], 'ordered driver')
    lifecycle = [s for s in signals if s.get('kind') == 'scene-lifecycle']
    def scene(s): return s.get('semanticContext', {}).get('logicalSceneID')
    def native(s): return s.get('semanticContext', {}).get('nativeSceneID')
    identities = {}
    for label in ['scene-A', 'scene-B']:
        ids = {native(s) for s in lifecycle if scene(s) == label}
        require(len(ids) == 1 and next(iter(ids)), 'native scene identity changed')
        identities[label] = next(iter(ids))
    require(len(set(identities.values())) == 2, 'native scenes alias')
    view_signals = [s for s in signals if s.get('kind') == 'rum-view-snapshot']
    inventory = {}
    semantic = {'scene-A': [], 'scene-B': []}
    for s in view_signals:
        c = s.get('rumContext', {})
        require(s.get('evidenceSource') == 'rum-mapper' and c.get('viewID') and c.get('sessionID'), 'mapper view missing')
        v = dict(view_id=c['viewID'], session_id=c['sessionID'], name=c.get('viewName'))
        require(c['viewID'] not in inventory or inventory[c['viewID']] == v, 'mutated view identity')
        inventory[c['viewID']] = v
        if scene(s) in semantic:
            require(native(s) in [None, identities[scene(s)]] and s['semanticContext'].get('screen') == 'home', 'foreign semantic owner')
            if c['viewID'] not in semantic[scene(s)]: semantic[scene(s)].append(c['viewID'])
    require(inventory and len({v['session_id'] for v in inventory.values()}) == 1, 'foreign RUM session')
    require([len(semantic[s]) for s in ['scene-A','scene-B']] == [3,2]
            and len(set(semantic['scene-A']+semantic['scene-B'])) == 5, 'wrong five Home occurrences', 'FAIL')
    session = next(iter(inventory.values()))['session_id']
    work = []
    for s in signals:
        kind = s.get('kind')
        require(kind != 'rum-error', 'native RUM error', 'FAIL')
        if kind not in ['rum-action','rum-resource']: continue
        c, source = s.get('rumContext', {}), s.get('sourceContext', {})
        require(s.get('evidenceSource') == 'rum-mapper' and c.get('sessionID') == session
                and c.get('viewID') in inventory and s.get('eventID'), 'work owner not independent native view', 'FAIL')
        work.append(dict(kind=kind.removeprefix('rum-'),event_id=s['eventID'],session_id=session,
                         view_id=c['viewID'],phase=s.get('name'),source_scene=source.get('logicalSceneID')))
    require(len({(w['kind'],w['event_id']) for w in work}) == len(work), 'duplicate native work')
    wanted = [semantic['scene-B'][0],semantic['scene-A'][1],semantic['scene-B'][1],semantic['scene-A'][2],semantic['scene-A'][2]]
    for j,(phase,label,owner,step_index) in enumerate(zip(PHASES,SCENES,wanted,[4,7,10,13,15])):
        action = unique([s for s in signals if s.get('kind') == 'rum-action' and s.get('name') == phase],phase+' action')
        resource = unique([s for s in signals if s.get('kind') == 'rum-resource' and s.get('name') == phase],phase+' resource')
        for s in [action,resource]:
            require(s['rumContext']['viewID'] == owner and s.get('sourceContext',{}).get('logicalSceneID') == label
                    and s['sourceContext'].get('nativeSceneID') == identities[label], 'wrong exact/native marker owner', 'FAIL')
            require_before(starts[step_index],s,'marker after its command')
        preceding = [s for s in view_signals if s['rumContext']['viewID'] == owner and s['sequence'] < action['sequence']]
        require(preceding and preceding[-1]['rumContext'].get('viewActive') is True, 'marker on inactive view', 'FAIL')
        if j < 4:
            activation = unique([s for s in signals if s['sequence'] == acks[step_index-2]['acknowledgedSignalSequence']], 'activation ack')
            require(activation.get('kind') == 'scene-lifecycle' and scene(activation) == label
                    and activation.get('activationState') == 'foreground-active', 'no actual target activation', 'INCONCLUSIVE')
            previous = starts[1]['sequence'] if j == 0 else starts[step_index-3]['sequence']
            for target,state in [(label,'foreground-active'),('scene-A' if label=='scene-B' else 'scene-B','background')]:
                latest = [s for s in lifecycle if scene(s) == target and s['sequence'] < starts[step_index]['sequence']]
                require(latest and latest[-1].get('activationState') == state and latest[-1]['sequence'] > previous,
                        'stale/late target activation or peer background', 'INCONCLUSIVE')
    disconnected = unique([s for s in lifecycle if scene(s) == 'scene-B' and s.get('scenePhase') == 'disconnected'], 'actual B disconnect')
    requested = unique([s for s in signals if s.get('name') == 'physical-scene-destruction-requested'], 'exact native destruction request')
    require(scene(requested) == 'scene-B' and native(requested) == identities['scene-B'], 'wrong destruction target')
    require_before(starts[14], requested, 'fresh destruction request')
    require_before(requested, disconnected, 'actual callback after destruction request')
    require_before(starts[14], disconnected, 'fresh OS disconnect')
    require_before(disconnected, starts[15], 'disconnect before peer work')
    require(not any(s['rumContext']['viewID'] == wanted[-1] and s['rumContext'].get('viewActive') is False
                    and starts[14]['sequence'] < s['sequence'] < acks[15]['sequence'] for s in view_signals), 'peer close stopped A', 'FAIL')
    return dict(state='PASS',session_id=session,views=list(inventory.values()),work=work,
                native_scenes=identities,home_occurrences=semantic,marker_owners=dict(zip(PHASES,wanted)),native_expectations=19)


def validate_backend(local,run_id,rows,count):
    result = complete_backend_inventory(local,run_id,rows,count)
    result['marker_pairs'] = 5
    return result
