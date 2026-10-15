"""H10 phase bytes only. Validation does not authorize input or native admission."""
import base64
from pathlib import Path
import re
import uuid

import operation_transport as t
import scene_background_capture as capture
import scene_background_cycle as cycle

PHASES = ['initial-both-foreground', 'A-background-B-foreground',
          'A-foreground-B-foreground', 'collection-seal']
IDENTITY_KEYS = {'schemaVersion', 'runID', 'processID', 'scenarioID', 'profile',
                 'sourceRevision', 'installedCodeSHA256', 'challengeID',
                 'executionDeadlineMilliseconds', 'cleanupDeadlineMilliseconds'}


def identity(value):
    t.require(isinstance(value, dict) and set(value) == IDENTITY_KEYS, 'H10 identity shape differs')
    t.require(type(value['schemaVersion']) is int and value['schemaVersion'] == 1
              and type(value['processID']) is int and value['processID'] > 0
              and isinstance(value['runID'], str) and re.fullmatch('[a-z0-9-]{1,96}', value['runID'])
              and value['scenarioID'] == cycle.SCENARIO and value['profile'] == cycle.PROFILE,
              'H10 run, process or scenario differs')
    t.require(isinstance(value['sourceRevision'], str) and re.fullmatch('[a-f0-9]{40}', value['sourceRevision'])
              and t.digest(value['installedCodeSHA256']) and t.identifier(value['challengeID'])
              and value['challengeID'] == value['challengeID'].lower(), 'H10 source or challenge differs')
    execution, cleanup = value['executionDeadlineMilliseconds'], value['cleanupDeadlineMilliseconds']
    t.require(type(execution) is int and type(cleanup) is int and 0 < execution < cleanup,
              'H10 cutoffs differ')


def challenge(raw, expected, index, consumed):
    identity(expected)
    value = t.load(raw)
    fields = {'identity', 'phase', 'name', 'challengeID', 'maximumInspections'}
    if index == 3: fields |= {'consumedPhaseReplies', 'finalInvocationSequence'}
    t.require(type(index) is int and 0 <= index < 4 and len(consumed) == index,
              'H10 phase requested out of order')
    t.require(isinstance(value, dict) and set(value) == fields and t.encode(value) == raw
              and t.encode(value['identity']) == t.encode(expected), 'H10 challenge bytes differ')
    t.require(type(value['phase']) is int and value['phase'] == index and value['name'] == PHASES[index]
              and type(value['maximumInspections']) is int and value['maximumInspections'] == 24
              and t.identifier(value['challengeID']) and value['challengeID'] == value['challengeID'].lower(),
              'H10 challenge phase differs')
    if index == 3:
        t.require(value['consumedPhaseReplies'] == consumed and len(set(consumed)) == 3
                  and all(t.digest(item) for item in consumed)
                  and type(value['finalInvocationSequence']) is int and value['finalInvocationSequence'] > 0,
                  'H10 collection does not join consumed phases')
    return value


def request(challenge, sequence, operation, previous, *, inspected=None, display=None, proof=None, command_id=None):
    t.require(type(sequence) is int and sequence > 0 and t.digest(previous), 'H10 request chain differs')
    t.require(operation == 'inspect' or operation == ('seal' if challenge['phase'] == 3 else 'permit'),
              'unsupported H10 phase operation')
    command_id = command_id or str(uuid.uuid4())
    t.require(t.identifier(command_id) and command_id == command_id.lower(), 'invalid H10 command ID')
    value = dict(challenge=challenge, sequence=sequence, commandID=command_id,
                 operation=operation, previousReplySHA256=previous)
    if operation == 'inspect':
        t.require(inspected is None and display is None and proof is None, 'H10 inspect carries permission')
    else:
        t.require(t.digest(inspected) and inspected == previous and t.digest(display), 'H10 permission is stale')
        value.update(inspectedReplySHA256=inspected, displayReceiptSHA256=display)
        if operation == 'seal':
            t.require(isinstance(proof, bytes) and 0 < len(proof) <= t.MAX_BYTES, 'H10 seal proof missing')
            value['semanticProof'] = base64.b64encode(proof).decode()
        else: t.require(proof is None, 'H10 permit carries a seal')
    return t.encode(value)


def reply(raw, sent, *, received_ms):
    message = t.load(sent); value = t.load(raw)
    operation = message['operation']
    fields = {'challenge', 'sequence', 'commandID', 'requestSHA256', 'operation', 'outcome'}
    fields |= {'observation', 'observationSHA256'} if operation == 'inspect' else {
        'inspectedReplySHA256', 'displayReceiptSHA256'}
    if operation == 'seal': fields.add('seal')
    t.require(isinstance(value, dict) and set(value) == fields and t.encode(value) == raw,
              'H10 reply shape or canonical bytes differ')
    t.require(all(t.encode(value[key]) == t.encode(message[key]) for key in ['challenge', 'sequence', 'commandID', 'operation'])
              and value['requestSHA256'] == t.sha(sent)
              and value['outcome'] == {'inspect': 'observed', 'permit': 'granted', 'seal': 'sealed'}[operation],
              'H10 reply joins a different request')
    t.require(type(received_ms) is int and 0 < received_ms < message['challenge']['identity']['executionDeadlineMilliseconds'],
              'H10 reply missed the original cutoff')
    if operation == 'inspect':
        observation = capture.decode(value['observation'])
        t.require(value['observationSHA256'] == t.sha(observation), 'H10 observation changed')
        reference = t.load(observation)
    else:
        t.require(all(value[key] == message[key] for key in ['inspectedReplySHA256', 'displayReceiptSHA256']),
                  'H10 permission evidence changed')
        reference = t.load(capture.decode(value['seal'])) if operation == 'seal' else None
    if reference is not None: artifact_reference(reference)
    return value, reference


def artifact_reference(value):
    t.require(isinstance(value, dict) and set(value) == {'name', 'sha256', 'bytes'}
              and isinstance(value['name'], str) and re.fullmatch('[a-z-]+-[a-f0-9]{64}\\.json', value['name'])
              and t.digest(value['sha256']) and value['name'].endswith(value['sha256'] + '.json')
              and type(value['bytes']) is int and 0 < value['bytes'] <= capture.MAXIMUM_BYTES,
              'H10 artifact reference differs')


def consumed(raw, sent, returned):
    value = t.load(raw)
    t.require(t.encode(value) == raw and value == dict(permitRequestSHA256=t.sha(sent), permitReplySHA256=t.sha(returned)),
              'H10 consumed permit differs')


def semantic_proof(directory, reference, phase, display):
    t.require(phase['phase'] == 3 and t.digest(display), 'H10 collection proof is out of phase')
    observed = capture.read_capture(directory, reference, phase['identity'])
    t.require(observed['terminal'] is None and capture.final_invocation(observed['signals']) == phase['finalInvocationSequence'],
              'H10 actual final invocation differs')
    result = cycle.validate_local(observed['signals'], phase['identity']['runID'], profile=cycle.PROFILE)
    return t.encode(dict(identity=phase['identity'], captureSHA256=reference['sha256'],
        oracleSourceSHA256=t.sha(Path(cycle.__file__).read_bytes()), displayReceiptSHA256=display,
        consumedPhaseReplies=phase['consumedPhaseReplies'], finalInvocationSequence=phase['finalInvocationSequence'],
        localResult=base64.b64encode(t.encode(result)).decode()))
