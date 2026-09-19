"""H01: precritical physical topology, original same-key semantics and exact backend owners."""
import hashlib
import json
import math
from pathlib import Path
import re
from acceptance_common import require, require_identity, require_before, unique

SCENARIO = 'swiftui.coexistence.same-key-manual-two-scenes'
CONTRACT = 'physical-same-key-scenario-contract.json'
PHASES = ['same-key-home-a-before-manual', 'same-key-home-b-before-manual',
          'same-key-compose-a-active', 'same-key-compose-b-active',
          'same-key-home-b-returned', 'same-key-compose-a-after-b-stop', 'same-key-home-a-returned']
SCENES = ['scene-A', 'scene-B', 'scene-A', 'scene-B', 'scene-B', 'scene-A', 'scene-A']


def validate_scenes(scenes, identities=None):
    require([s.get('logicalSceneID') for s in scenes] == ['scene-A', 'scene-B'], 'two native scene observations required')
    actual = {s['logicalSceneID']: (s.get('nativeSceneID'), s.get('generation')) for s in scenes}
    require(len({x[0] for x in actual.values()}) == 2 and all(isinstance(x[0], str) and x[0] for x in actual.values()), 'native scene alias')
    for scene in scenes:
        require(scene.get('connected') is True and scene.get('hidden') is False
                and isinstance(scene.get('alpha'), (int, float)) and math.isfinite(scene['alpha']) and scene['alpha'] > 0
                and scene.get('activationState') in ['foreground-active', 'foreground-inactive'], 'hidden/background/detached physical window', 'INCONCLUSIVE')
        require(type(scene.get('generation')) is int and scene['generation'] >= 0, 'invalid scene generation')
        geometry = scene.get('geometry', {})
        require(all(isinstance(geometry.get(k), (int, float)) and math.isfinite(geometry[k]) for k in ['x', 'y', 'width', 'height'])
                and geometry['width'] > 0 and geometry['height'] > 0, 'missing native geometry')
    if identities is not None:
        require(actual == identities, 'native identity/generation changed', 'INCONCLUSIVE')
    return actual


def validate_local(records, run_id):
    manifest = unique([r['manifest'] for r in records if r['type'] == 'manifest'], 'manifest')
    require(manifest.get('runID') == run_id and manifest.get('runMode') == 'clean'
            and not manifest.get('validationErrors'), 'stale or invalid physical manifest')
    expected = json.loads(Path(__file__).with_name(CONTRACT).read_text())
    require_identity(manifest.get('scenario'), expected, 'same-key scenario')
    signals = [r['signal'] for r in records if r['type'] == 'signal']
    require(signals and all(s.get('runID') == run_id and s.get('scenarioID') == SCENARIO
                           and s.get('schemaVersion') == 5 for s in signals), 'stale physical signals')
    require([s['sequence'] for s in signals] == list(range(1, len(signals)+1)), 'incomplete signal sequence')
    require(not any(s.get('result') in ['FAIL', 'INCONCLUSIVE'] for s in signals), 'native admission/assertion failed', 'INCONCLUSIVE')
    terminal = unique([r for r in records if r['type'] == 'semantic-result'], 'terminal')
    result = terminal.get('result', {})
    require(terminal.get('runID') == run_id and result.get('scenarioID') == SCENARIO
            and result.get('state') == 'PASS' and result.get('matchedExpectationCount') == 22
            and result.get('issues') == [], 'original 22 same-key expectations did not pass', 'FAIL')
    starts = [s for s in signals if s.get('kind') == 'step-started']
    acks = [s for s in signals if s.get('kind') == 'step-acknowledged']
    require(len(starts) == len(acks) == 17, 'incomplete physical driver')
    admitted = unique([s for s in signals if s.get('name') == 'physical-topology-admitted'], 'physical admission')
    topology = admitted.get('physicalTopology', {})
    require(admitted.get('kind') == 'assertion' and admitted.get('result') == 'PASS'
            and topology.get('nonce') and topology.get('captureID')
            and re.fullmatch('[a-f0-9]{64}', topology.get('evidenceSHA256', '')), 'missing independent display identity')
    identities = validate_scenes(topology.get('scenes', []))
    observations = [s for s in signals if s.get('physicalTopology')]
    require(len(observations) == 23, 'missing or repeated critical topology observation')
    for index, (step, start, ack) in enumerate(zip(expected['steps'], starts, acks)):
        require(start.get('stepIndex') == ack.get('stepIndex') == index
                and start.get('stepKind') == ack.get('stepKind') == step['kind'], 'driver step identity')
        require_before(start, ack, 'step acknowledgement')
        evidence = unique([s for s in signals if s['sequence'] == ack.get('acknowledgedSignalSequence')], 'acknowledged native signal')
        require_before(evidence, ack, 'ack evidence')
        if index < 16:
            require_before(ack, starts[index+1], 'ordered native steps')
        if index < 6:
            continue
        before = unique([s for s in observations if s.get('name') == f'physical-topology-before-{index}'], 'before mutation topology')
        after = unique([s for s in observations if s.get('name') == f'physical-topology-after-{index}'], 'after mutation topology')
        require_before(admitted, before, 'admission before mutation')
        require_before(start, before, 'fresh before observation')
        require_before(before, after, 'observation ordering')
        require_before(after, ack, 'critical interval before acknowledgement')
        if step['kind'] != 'wait-for-signal':
            require_before(before, evidence, 'precritical observation')
        for observation in [before, after]:
            t = observation['physicalTopology']
            require(observation.get('kind') == 'assertion' and observation.get('result') == 'PASS', 'invalid topology guard')
            require(all(t.get(k) == topology[k] for k in ['nonce', 'captureID', 'evidenceSHA256']), 'changed/reused receipt identity')
            validate_scenes(t.get('scenes', []), identities)
    end = next(s for s in observations if s.get('name') == 'physical-topology-after-16')
    for s in signals:
        if admitted['sequence'] < s['sequence'] < end['sequence'] and s.get('kind') in ['scene-lifecycle', 'scene-geometry']:
            require(s.get('activationState') not in ['background', 'unattached'] and s.get('scenePhase') != 'disconnected',
                    'native lifecycle lost during manual interval', 'INCONCLUSIVE')
    view_signals = [s for s in signals if s.get('kind') == 'rum-view-snapshot']
    inventory = {}
    for s in view_signals:
        c = s.get('rumContext', {})
        require(s.get('evidenceSource') == 'rum-mapper' and c.get('viewID') and c.get('sessionID'), 'independent mapper missing')
        v = {'view_id': c['viewID'], 'session_id': c['sessionID'], 'name': c.get('viewName')}
        require(c['viewID'] not in inventory or inventory[c['viewID']] == v, 'mutated view identity')
        inventory[c['viewID']] = v
    require(inventory and len({v['session_id'] for v in inventory.values()}) == 1, 'foreign native session')
    session = next(iter(inventory.values()))['session_id']
    work = []
    for s in signals:
        kind = s.get('kind')
        require(kind != 'rum-error', 'native RUM error', 'FAIL')
        if kind not in ['rum-action', 'rum-resource']:
            continue
        c, source = s.get('rumContext', {}), s.get('sourceContext', {})
        require(s.get('evidenceSource') == 'rum-mapper' and c.get('sessionID') == session
                and c.get('viewID') in inventory and s.get('eventID'), 'work owner is not an independent native view', 'FAIL')
        work.append({'kind': kind.removeprefix('rum-'), 'event_id': s['eventID'], 'session_id': session,
                     'view_id': c['viewID'], 'phase': s.get('name'), 'source_scene': source.get('logicalSceneID')})
    require(len({(w['kind'], w['event_id']) for w in work}) == len(work), 'duplicate native work')
    owners = []
    for phase, scene in zip(PHASES, SCENES):
        action = unique([s for s in signals if s.get('kind') == 'rum-action' and s.get('name') == phase], phase+' action')
        resource = unique([s for s in signals if s.get('kind') == 'rum-resource' and s.get('name') == phase], phase+' resource')
        owner = action['rumContext']['viewID']
        require(resource['rumContext']['viewID'] == owner, 'captured Resource owner differs', 'FAIL')
        for s in [action, resource]:
            require(s.get('sourceContext', {}).get('logicalSceneID') == scene
                    and s['sourceContext'].get('nativeSceneID') == identities[scene][0], 'wrong native marker source', 'FAIL')
        preceding = [v for v in view_signals if v['rumContext']['viewID'] == owner and v['sequence'] < action['sequence']]
        require(preceding and preceding[-1]['rumContext'].get('viewActive') is True, 'marker on stopped/missing view', 'FAIL')
        owners.append(owner)
    require(len(set(owners[:5] + owners[6:])) == 6 and owners[2] == owners[5], 'same-key peer ownership or fresh Home failed', 'FAIL')
    require(all(inventory[owners[i]]['name'] == 'ProbeKeyedManualView' for i in [2, 3, 5]), 'Compose owner not manual', 'FAIL')
    a_stop = starts[15]
    require(not any(v['rumContext']['viewID'] == owners[2] and v['rumContext'].get('viewActive') is False
                    and starts[9]['sequence'] < v['sequence'] < a_stop['sequence'] for v in view_signals),
            'peer stop ended A Compose', 'FAIL')
    return {'state': 'PASS', 'session_id': session, 'views': list(inventory.values()), 'work': work,
            'marker_owners': dict(zip(PHASES, owners)), 'native_scenes': {k: v[0] for k, v in identities.items()},
            'admission': admitted, 'critical_end': end, 'physical_display_proof_still_required': True}


def validate_display(local, run_id, proof):
    require(proof.get('run_id') == run_id and proof.get('device_reality') == 'physical', 'display evidence from wrong run/device')
    topology = local['admission']['physicalTopology']
    require(proof.get('capture_id') == topology['captureID'] and proof.get('nonce') == topology['nonce'], 'display capture/nonce mismatch')
    require(proof.get('visible_native_scenes') == local['native_scenes'] and proof.get('visibility_review') == 'both-window-content-visible-through-critical-interval', 'independent visibility not established')
    screenshot, video = proof.get('screenshot', {}), proof.get('video', {})
    receipt, challenge = proof.get('receipt', {}), proof.get('challenge', {})
    require(receipt.get('runID') == challenge.get('runID') == run_id
            and receipt.get('scenarioID') == challenge.get('scenarioID') == SCENARIO
            and receipt.get('nonce') == challenge.get('nonce') == topology['nonce']
            and receipt.get('processID') == challenge.get('processID') == proof.get('process_id')
            and type(proof.get('process_id')) is int and proof['process_id'] > 0,
            'display receipt/challenge process or run mismatch')
    require(receipt.get('captureID') == topology['captureID']
            and receipt.get('evidenceSHA256') == topology['evidenceSHA256']
            and receipt.get('nativeSceneIDs') == local['native_scenes']
            and receipt.get('generations') == {s['logicalSceneID']: s['generation'] for s in topology['scenes']},
            'display receipt differs from native admission')
    require(type(challenge.get('createdAtMilliseconds')) is int
            and receipt.get('capturedAtMilliseconds') == screenshot.get('captured_at_ms')
            and challenge['createdAtMilliseconds'] <= screenshot['captured_at_ms']
            and local['admission']['timestampMilliseconds'] - screenshot['captured_at_ms'] <= 60_000,
            'display evidence is stale or predates challenge')
    for item in [screenshot, video]:
        path = Path(item.get('path', ''))
        require(path.is_file() and path.stat().st_size > 0 and hashlib.sha256(path.read_bytes()).hexdigest() == item.get('sha256'), 'missing/changed display artifact')
    require(screenshot['sha256'] == topology['evidenceSHA256'], 'receipt screenshot differs')
    require(screenshot['captured_at_ms'] <= local['admission']['timestampMilliseconds']
            and video['start_ms'] <= screenshot['captured_at_ms']
            and video['end_ms'] >= local['critical_end']['timestampMilliseconds'], 'display proof starts late or ends early')
    return {'state': 'PASS', 'capture_id': topology['captureID']}


def validate_backend(local, run_id, rows, count):
    require(count == len(rows) == len({r['id'] for r in rows}), 'incomplete backend count/pagination')
    payloads = [r.get('attributes', {}).get('custom', {}) for r in rows]
    require(all(p.get('session', {}).get('id') == local['session_id'] and p.get('context', {}).get('probe', {}).get('run_id') == run_id
                for p in payloads), 'foreign/stale backend session or run')
    actual_views = [dict(view_id=p['view']['id'], session_id=p['session']['id'], name=p['view'].get('name'))
                    for p in payloads if p.get('type') == 'view']
    require(sorted(actual_views, key=lambda v: v['view_id']) == sorted(local['views'], key=lambda v: v['view_id']), 'complete backend view inventory differs', 'FAIL')
    work = []
    for p in payloads:
        kind = p.get('type')
        require(kind in ['view', 'action', 'resource', 'session', 'long_task', 'vital'], 'unexpected backend error/event', 'FAIL')
        if kind in ['long_task', 'vital']:
            require(p.get('view', {}).get('id') in {v['view_id'] for v in local['views']}, 'foreign process-signal owner')
        if kind in ['action', 'resource']:
            context = p['context']['probe']
            work.append(dict(kind=kind, event_id=p[kind]['id'], session_id=p['session']['id'], view_id=p['view']['id'],
                             phase=context.get('phase'), source_scene=context.get('source_scene')))
    require(sorted(work, key=lambda w: (w['kind'], w['event_id'])) == sorted(local['work'], key=lambda w: (w['kind'], w['event_id'])),
            'missing/extra backend work or wrong exact owner', 'FAIL')
    return {'state': 'PASS', 'view_count': len(actual_views), 'work_count': len(work), 'marker_pairs': 7, 'error_crash_count': 0}
