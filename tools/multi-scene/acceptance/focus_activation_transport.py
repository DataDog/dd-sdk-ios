"""Private H04 byte protocol. Parsing grants neither native launch nor teardown."""
import base64
import re
import time
import uuid
import operation_transport as t

SCENARIO = 'windows.focus-activation-only'
PROFILE = 'physical-focus-activation-only'
IDENTITY_KEYS = {'schemaVersion','runID','processID','scenarioID','profile','sourceRevision',
                 'installedCodeSHA256','challengeID','executionDeadlineMilliseconds','cleanupDeadlineMilliseconds'}


def challenge(raw, installed, *, run_id, process_id, revision, execution_ms, cleanup_ms):
    value = t.load(raw)
    t.require(isinstance(value, dict) and set(value) == IDENTITY_KEYS and t.encode(value) == raw,
              'focus challenge shape or canonical bytes differ')
    t.require(type(value['schemaVersion']) is int and value['schemaVersion'] == 1
              and isinstance(run_id, str) and re.fullmatch('[a-z0-9-]{1,96}', run_id)
              and value['runID'] == run_id and type(process_id) is int and process_id > 0
              and type(value['processID']) is int and value['processID'] == process_id,
              'focus run or process differs')
    t.require(value['scenarioID'] == SCENARIO and value['profile'] == PROFILE
              and re.fullmatch('[a-f0-9]{40}', revision) and value['sourceRevision'] == revision
              and t.identifier(value['challengeID']) and value['challengeID'] == value['challengeID'].lower()
              and value['installedCodeSHA256'] == t.sha(installed), 'focus selected source or challenge differs')
    t.require(all(type(n) is int for n in [execution_ms,cleanup_ms,value['executionDeadlineMilliseconds'],
                                         value['cleanupDeadlineMilliseconds']])
              and value['executionDeadlineMilliseconds'] == execution_ms
              and value['cleanupDeadlineMilliseconds'] == cleanup_ms and 0 < execution_ms < cleanup_ms,
              'focus frozen cutoffs differ')
    code=t.load(installed, maximum=t.MAX_CONTEXT_BYTES)
    t.require(code.get('runID') == run_id and type(code.get('processID')) is int and code['processID'] == process_id
              and code.get('sourceRevision') == revision and code.get('boundary') == 'before-sdk-initialization',
              'focus installed receipt identity differs')
    return value


def request(identity, operation):
    t.require(operation in ['arm','stop'], 'unsupported focus operation')
    return t.encode(dict(identity=identity,commandID=str(uuid.uuid4()),operation=operation))


def opaque(value):
    t.require(isinstance(value,str), 'missing native opaque bytes')
    raw=base64.b64decode(value,validate=True)
    t.require(base64.b64encode(raw).decode() == value, 'noncanonical native opaque encoding')
    return raw,t.load(raw,maximum=t.MAX_CONTEXT_BYTES)


def idle(snapshot, operation):
    t.require(isinstance(snapshot,dict) and not snapshot.get('failure'), 'native input failure')
    scenes=snapshot.get('scenes',[]);inputs=snapshot.get('input',[]);inventory=snapshot.get('inventory',[])
    continuity=snapshot.get('continuity',{});owners=continuity.get('owners',[])
    labels=[s.get('logicalSceneID') for s in scenes]
    t.require(snapshot.get('applicationActive') is True and (labels == ['scene-A'] or
              operation == 'stop' and labels == ['scene-A','scene-B']) and not continuity.get('failure')
              and [o.get('logicalSceneID') for o in owners] == labels
              and [i.get('logicalSceneID') for i in inputs] == labels, 'incomplete focus idle owners')
    for key in ['nativeSceneID','windowIdentity','rootIdentity']:
        t.require(all(isinstance(o.get(key),str) and o[key] for o in owners)
                  and len({o[key] for o in owners}) == len(labels), 'aliased focus owner')
    t.require(all(isinstance(i.get('observerIdentity'),str) and i['observerIdentity'] for i in inputs)
              and len({i['observerIdentity'] for i in inputs}) == len(labels), 'aliased focus observer')
    natives=sorted(o['nativeSceneID'] for o in owners)
    t.require(snapshot.get('connectedSceneIDs') == natives
              and sorted(i.get('nativeSceneID','') for i in inventory) == natives
              and any(s.get('activationState') == 'foreground-active' for s in scenes), 'focus connected inventory differs')
    for o,s,i in zip(owners,scenes,inputs):
        t.require(type(o.get('generation')) is int and o['generation'] >= 0
                  and all(i.get(k) == o.get(k) == s.get(k) for k in ['nativeSceneID','generation','windowIdentity','rootIdentity']),
                  'focus observer does not own original scene')
        t.require(s.get('connected') is True and all(i.get(k) is True for k in ['attached','enabled','reliable'])
                  and type(i.get('touches')) is int and i['touches'] == 0
                  and type(i.get('revision')) is int and i['revision'] >= 0
                  and i.get('transitioning') is False and i.get('resizing') is False, 'focus input is not idle')
        state=s.get('activationState'); scene=next(v for v in inventory if v['nativeSceneID'] == o['nativeSceneID'])
        t.require(state in ['foreground-active','foreground-inactive','background']
                  and scene.get('activationState') == state, 'focus activation inventory differs')
        windows=scene.get('windows',[]);owned=[w for w in windows if w.get('fixtureOwner') == o['logicalSceneID']]
        t.require(len(owned) == 1, 'focus owned window missing or aliased');w=owned[0]
        t.require(w.get('identity') == o['windowIdentity'] and w.get('rootIdentity') == o['rootIdentity']
                  and w.get('sceneMatches') is True and sum(x.get('identity') == o['windowIdentity'] for x in windows) == 1
                  and [x.get('identity') for x in windows if x.get('key') is True] ==
                  ([scene['keyWindowIdentity']] if scene.get('keyWindowIdentity') is not None else []),
                  'focus window or key owner differs')
        if state != 'background':
            import math
            t.require(i.get('mounted') is True and w.get('mounted') is True and w.get('hidden') is False
                      and type(w.get('alpha')) in (int,float) and math.isfinite(w['alpha']) and w['alpha'] > 0,
                      'focus foreground owner is not mounted and visible')
        if state == 'foreground-active':
            t.require(scene.get('keyWindowIdentity') == o['windowIdentity'], 'focus key window is not owned')


def activity(snapshot):
    return [(s.get('nativeSceneID'),s.get('activationState'),s.get('keyWindowIdentity'),
             [(w.get('identity'),w.get('rootIdentity'),w.get('fixtureOwner'),w.get('sceneMatches'),w.get('key'),
               w.get('hidden'),w.get('mounted')) for w in s.get('windows',[])]) for s in snapshot['inventory']]


def reply(raw, sent, *, received_at_ms):
    message=t.load(sent);value=t.load(raw,maximum=t.MAX_CONTEXT_BYTES)
    operation=message['operation'];identity=message['identity']
    required={'identity','requestSHA256','commandID','outcome','driver','observation'}
    t.require(isinstance(value,dict) and required <= set(value) <= required|{'failure'}
              and value['identity'] == identity and value['requestSHA256'] == t.sha(sent)
              and value['commandID'] == message['commandID'], 'focus reply identity or request differs')
    deadline=identity['executionDeadlineMilliseconds' if operation == 'arm' else 'cleanupDeadlineMilliseconds']
    t.require(type(received_at_ms) is int and 0 < received_at_ms < deadline, 'focus reply is late')
    t.require(value['outcome'] == ('armed' if operation == 'arm' else 'stopped-idle'), 'focus native reply rejected')
    state=value['driver'];expected=operation == 'stop'
    t.require(isinstance(state,dict) and {'requested','stopped'} <= set(state) <= {'requested','stopped','terminal'}
              and state['requested'] is expected and state['stopped'] is expected, 'focus driver is not in required state')
    if operation == 'arm':t.require('failure' not in value, 'failed focus channel cannot arm')
    observation=value['observation']
    t.require(isinstance(observation,dict) and set(observation) == {'before','after','idle'}
              and observation['idle'] is True, 'focus native idle proof absent')
    before_raw,before=opaque(observation['before']);after_raw,after=opaque(observation['after'])
    idle(before,operation);idle(after,operation)
    t.require(all(before.get(k) == after.get(k) for k in ['input','continuity','applicationActive','connectedSceneIDs'])
              and activity(before) == activity(after), 'focus owner or contact changed across idle capture')
    return dict(state='QUALIFIED_PROTOCOL_ONLY',operation=operation,identity=identity,
                request_sha256=t.sha(sent),reply_sha256=t.sha(raw),before_sha256=t.sha(before_raw),
                after_sha256=t.sha(after_raw),driver=state,overall='UNQUALIFIED',cleanup='PENDING')
