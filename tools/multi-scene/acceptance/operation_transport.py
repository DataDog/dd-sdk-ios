"""H06 input transport only: no SDK admission, device input or teardown authority."""
import base64
import hashlib
import json
import math
import os
from pathlib import Path
import re
import time
import uuid

MAX_BYTES = 65_536
MAX_CONTEXT_BYTES = 1_048_576
IDENTITY_KEYS = {'schemaVersion', 'runID', 'processID', 'profile', 'challengeID',
                 'installedCodeSHA256', 'executionArmed'}
PROFILE_KEYS = {'sourceRevision', 'buildConfiguration', 'scenarioSHA256', 'inference'}
MESSAGE_KEYS = {'schemaVersion', 'runID', 'processID', 'challengeID', 'commandID', 'inputRequest'}
SETUP_KEYS = {'variant', 'scenario', 'fullScenarioSHA256', 'setupPrefixSHA256',
              'setupBoundaryIndex', 'firstOperationIndex', 'lastOperationIndex', 'ownerBindingVersion'}


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def encode(value):
    # This is also the Swift channel's canonical outer encoding. No newline.
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False).encode()


def load(raw, *, maximum=MAX_BYTES):
    require(isinstance(raw, bytes) and len(raw) <= maximum, 'oversized or absent channel bytes')
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, 'duplicate channel field')
            result[key] = value
        return result
    def invalid(_):
        raise ValueError('nonfinite channel number')
    return json.loads(raw, object_pairs_hook=unique, parse_constant=invalid)


def digest(value):
    return isinstance(value, str) and re.fullmatch('[a-f0-9]{64}', value) is not None


def identifier(value):
    try:
        return isinstance(value, str) and str(uuid.UUID(value)).lower() == value.lower()
    except (ValueError, TypeError):
        return False


def validate_setup(profile):
    require(isinstance(profile, dict) and set(profile) == SETUP_KEYS, 'setup profile shape changed')
    require(profile['variant'] == 'post-arrangement-owners-v1'
            and profile['scenario'] == 'operations.cross-scene.physical-setup'
            and digest(profile['fullScenarioSHA256']) and digest(profile['setupPrefixSHA256']),
            'setup variant or digest changed')
    for field, expected in [('setupBoundaryIndex', 4), ('firstOperationIndex', 6),
                            ('lastOperationIndex', 21), ('ownerBindingVersion', 1)]:
        require(type(profile[field]) is int and profile[field] == expected, 'setup boundary/version changed')


def challenge(raw, *, run_id, process_id, profile, installed_code, setup_profile=None):
    value = load(raw)
    fields = IDENTITY_KEYS | ({'setupProfile'} if setup_profile is not None else set())
    require(isinstance(value, dict) and set(value) == fields, 'channel challenge shape changed')
    version = 2 if setup_profile is not None else 1
    require(type(value['schemaVersion']) is int and value['schemaVersion'] == version, 'channel schema changed')
    if setup_profile is not None:
        validate_setup(setup_profile)
        require(encode(value['setupProfile']) == encode(setup_profile), 'setup profile differs from frozen contract')
    require(isinstance(run_id, str) and re.fullmatch('[a-z0-9-]+', run_id), 'invalid run identity')
    require(type(process_id) is int and process_id > 0 and type(value['processID']) is int,
            'invalid process identity')
    require(value['runID'] == run_id and value['processID'] == process_id, 'foreign channel process/run')
    require(isinstance(profile, dict) and set(profile) == PROFILE_KEYS and value['profile'] == profile,
            'channel profile changed')
    require(re.fullmatch('[a-f0-9]{40}', profile['sourceRevision']) and digest(profile['scenarioSHA256'])
            and profile['buildConfiguration'] == 'Debug'
            and profile['inference'] == 'debug-rum-ui-event-network-context', 'unsupported Operation profile')
    require(identifier(value['challengeID']) and value['installedCodeSHA256'] == sha(installed_code),
            'challenge or installed bytes differ')
    require(value['executionArmed'] is False, 'capture-only channel unexpectedly armed')
    # Binary/source comparison remains installed_code.validate's responsibility.
    code = load(installed_code)
    require(code.get('runID') == run_id and type(code.get('processID')) is int
            and code['processID'] == process_id and code.get('sourceRevision') == profile['sourceRevision']
            and code.get('boundary') == 'before-sdk-initialization', 'installed identity differs')
    return value


def message(identity, phase):
    require(phase in ['setup', 'cleanup'], 'unsupported channel phase')
    request = dict(runID=identity['runID'], processID=identity['processID'], profile=identity['profile'],
                   phase=phase, nonce=str(uuid.uuid4()))
    if identity['schemaVersion'] == 2:
        validate_setup(identity.get('setupProfile'))
        request['setupProfile'] = identity['setupProfile']
    else:
        require(identity['schemaVersion'] == 1 and 'setupProfile' not in identity, 'channel mode changed')
    raw = encode(request)
    value = dict(schemaVersion=identity['schemaVersion'], runID=identity['runID'], processID=identity['processID'],
                 challengeID=identity['challengeID'], commandID=str(uuid.uuid4()),
                 inputRequest=base64.b64encode(raw).decode())
    return encode(value), raw


def response(raw, request_raw, input_raw, identity):
    value, request = load(raw), load(request_raw)
    require(encode(request) == request_raw and encode(load(input_raw)) == input_raw, 'noncanonical channel request')
    require(encode(value) == raw, 'noncanonical channel response envelope')
    require(isinstance(value, dict) and set(value) in [
        {'identity', 'requestSHA256', 'commandID', 'capture'},
        {'identity', 'requestSHA256', 'rejection'},
        {'identity', 'requestSHA256', 'commandID', 'rejection'}], 'channel reply shape changed')
    require(encode(value['identity']) == encode(identity) and value['requestSHA256'] == sha(request_raw),
            'stale or foreign channel response')
    require('rejection' not in value, 'native channel rejected request')
    require(value['commandID'] == request['commandID'], 'channel command identity differs')
    capture_raw = base64.b64decode(value['capture'], validate=True)
    capture = load(capture_raw)
    required = {'request', 'requestSHA256', 'captureID', 'before', 'after'}
    require(isinstance(capture, dict) and set(capture) in [required, required | {'idleFailure'}],
            'native capture shape changed')
    require(encode(capture['request']) == input_raw and capture['requestSHA256'] == sha(input_raw)
            and identifier(capture['captureID']), 'capture request identity differs')
    require(isinstance(capture['before'], dict) and isinstance(capture['after'], dict), 'missing input snapshots')
    # Preserve non-idle captures. Semantic/input validation is separate; this
    # function proves only that these are the requested response bytes.
    return capture_raw, capture


def context_response(raw, *, completion_raw, reply_raw, request_raw, input_raw, identity, deadline):
    """Join captured bytes only; owner, release/display and SDK admission are separate."""
    capture_raw, _ = response(reply_raw, request_raw, input_raw, identity)
    completion = load(completion_raw)
    completion_keys = {'schemaVersion', 'identity', 'requestSHA256', 'replySHA256', 'captureSHA256',
                       'contextSHA256', 'status', 'statusSHA256', 'state', 'deadline', 'finishedAt'}
    require(isinstance(completion, dict) and set(completion) == completion_keys
            and type(completion['schemaVersion']) is int and completion['schemaVersion'] == 1
            and completion['state'] == 'CAPTURE_COMPLETE', 'missing terminal context receipt')
    require(encode(completion['identity']) == encode(identity)
            and completion['requestSHA256'] == sha(request_raw)
            and completion['replySHA256'] == sha(reply_raw) and completion['captureSHA256'] == sha(capture_raw)
            and completion['contextSHA256'] == sha(raw), 'terminal receipt joins different context bytes')
    require(type(completion['deadline']) in [int, float] and completion['deadline'] == deadline
            and type(completion['finishedAt']) in [int, float] and math.isfinite(completion['finishedAt'])
            and completion['finishedAt'] < deadline, 'terminal context receipt is late')
    require(isinstance(completion['status'], str), 'missing terminal status bytes')
    status_raw = base64.b64decode(completion['status'], validate=True)
    require(completion['statusSHA256'] == sha(status_raw), 'terminal status digest differs')
    status = load(status_raw)
    require(isinstance(status, dict) and set(status) == {'identity', 'sequence', 'state', 'requestSHA256',
                                                       'deadline', 'observedAt'}
            and encode(status['identity']) == encode(identity) and status['state'] == 'CONTEXT_PUBLISHED'
            and status['requestSHA256'] == sha(request_raw) and type(status['sequence']) is int
            and status['sequence'] > 0 and type(status['deadline']) in [int, float]
            and status['deadline'] == deadline and type(status['observedAt']) in [int, float]
            and math.isfinite(status['observedAt']) and status['observedAt'] <= completion['finishedAt'],
            'terminal publication status differs')
    value = load(raw, maximum=MAX_CONTEXT_BYTES)
    fields = {'schemaVersion', 'identity', 'requestSHA256', 'replySHA256', 'captureSHA256',
              'order', 'components', 'componentSHA256', 'state', 'deadline', 'finishedAt'}
    require(isinstance(value, dict) and set(value) in [fields, fields | {'failure'}],
            'context document shape changed')
    require(type(value['schemaVersion']) is int and value['schemaVersion'] == 1
            and identity['schemaVersion'] == 2 and 'setupProfile' in identity,
            'context capture mode changed')
    require(encode(value['identity']) == encode(identity) and value['requestSHA256'] == sha(request_raw)
            and value['replySHA256'] == sha(reply_raw) and value['captureSHA256'] == sha(capture_raw),
            'foreign context reply or capture')
    require(value['state'] == 'CAPTURED' and 'failure' not in value, 'incomplete or failed context capture')
    require(type(value['deadline']) in [int, float] and value['deadline'] == deadline
            and type(value['finishedAt']) in [int, float] and math.isfinite(value['finishedAt'])
            and value['finishedAt'] < deadline, 'context original deadline differs or expired')
    order = ['sdkBefore', 'mapper', 'sdkAfter']
    require(value['order'] == order and isinstance(value['components'], dict)
            and isinstance(value['componentSHA256'], dict)
            and set(value['components']) == set(order) and set(value['componentSHA256']) == set(order),
            'missing or reordered context component')
    decoded = {}
    for name in order:
        require(isinstance(value['components'][name], str), 'context component is not encoded bytes')
        component = base64.b64decode(value['components'][name], validate=True)
        require(value['componentSHA256'][name] == sha(component), 'context component digest differs')
        item = load(component, maximum=MAX_CONTEXT_BYTES)
        if name == 'mapper':
            require(isinstance(item, list) and all(isinstance(row, dict) for row in item),
                    'missing independent mapper snapshot')
        else:
            keys = {'sampledAt', 'before', 'after', 'reads'}
            require(isinstance(item, dict) and set(item) in [keys, keys | {'failure'}]
                    and type(item['sampledAt']) in [int, float] and math.isfinite(item['sampledAt'])
                    and isinstance(item['before'], dict) and isinstance(item['after'], dict)
                    and isinstance(item['reads'], list), 'missing SDK sample inventory')
        decoded[name] = item
    # Do not canonicalize Swift Date/geometry values or manufacture mapper rows.
    return value, decoded


def save(path, raw):
    path = Path(path)
    require(path.parent.is_dir() and not path.is_symlink(), 'unprepared or symlinked output')
    with path.open('xb') as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())


class Channel:
    """Serialize transfers through the existing physical_io.Device instance.

    The caller freezes a single deadline and proves process, installed code,
    release and display prerequisites. This helper never launches or removes apps.
    """
    def __init__(self, remote, bundle, output, identity, *, deadline):
        require(type(deadline) in [int, float] and math.isfinite(deadline) and deadline > time.time(),
                'channel deadline expired')
        require(isinstance(bundle, str) and bundle and remote.identifier, 'missing transfer identity')
        self.remote, self.bundle, self.identity, self.deadline = remote, bundle, identity, deadline
        self.output = Path(output); self.output.mkdir()
        self.sequence = 0
        self.consumed = set()
        self.stopped = False
        save(self.output / 'identity.json', encode(identity))

    def live(self):
        require(time.time() < self.deadline, 'channel original deadline expired')

    def transfer(self, method, source, destination, label, *, optional=False):
        self.live()
        result, receipt = method(self.bundle, source, destination, label, self.deadline,
                                 **({'check': False} if optional else {}))
        self.live()
        require(type(receipt.get('returncode')) is int and receipt['remaining'] == []
                and receipt['before'] == [] and receipt.get('quiescence_error') is None,
                'unqualified transfer lifetime')
        require(receipt['finished_at'] < min(receipt['deadline'], self.deadline), 'late transfer')
        info = (result or {}).get('info', {}); args = info.get('arguments', [])
        command = 'devicectl.device.copy.from' if optional else 'devicectl.device.copy.to'
        require(isinstance(args, list), 'missing transfer arguments')
        for flag, expected in [('--device', self.remote.identifier), ('--domain-type', 'appDataContainer'),
                               ('--domain-identifier', self.bundle), ('--source', str(source)),
                               ('--destination', str(destination))]:
            require(args.count(flag) == 1 and args.index(flag) + 1 < len(args)
                    and args[args.index(flag) + 1] == expected, 'foreign transfer ' + flag)
        require(info.get('commandType') == command, 'wrong transfer operation')
        if receipt['returncode'] != 0:
            # The existing CoreDevice wrapper preserves the raw failure. Only a
            # missing response file is pending; other transport failures stop.
            signature = (result or {}).get('errorSignature', '')
            error = (result or {}).get('error', {})
            description = error.get('userInfo', {}).get('NSLocalizedDescription', {}).get('string')
            require(optional and info.get('outcome') == 'failed'
                    and signature == '(com.apple.dt.CoreDeviceError 7000)'
                    and error.get('domain') == 'com.apple.dt.CoreDeviceError'
                    and error.get('code') == 7000
                    and description == 'Failed to retrieve the file node for ' + str(source),
                    'native response transfer failed')
            return False
        require(info.get('outcome') == 'success', 'failed native transfer response')
        return True

    def collect_context(self, folder, fingerprint, returned, raw, inner):
        prefix = 'Documents/' + self.identity['runID'] + '.operations-'
        for attempt in range(1, 100_001):
            self.live()
            terminal_path = folder / f'context-result-{attempt:06d}.json'
            if self.transfer(self.remote.pull, prefix + 'context-' + fingerprint + '-result.json', terminal_path,
                             'operation-context-result', optional=True):
                require(terminal_path.is_file() and not terminal_path.is_symlink(),
                        'missing or symlinked terminal context receipt')
                with terminal_path.open('rb') as source:
                    terminal = source.read(MAX_BYTES + 1)
                completed = load(terminal)
                require(isinstance(completed, dict) and completed.get('state') == 'CAPTURE_COMPLETE',
                        'native context capture failed')
                # A terminal receipt requires its context to exist already. An
                # absent context here is invalid, not another readiness wait.
                destination = folder / 'context-000001.json'
                require(self.transfer(self.remote.pull, prefix + 'context-' + fingerprint + '.json', destination,
                                      'operation-context', optional=True), 'completed context is missing')
                require(destination.is_file() and not destination.is_symlink(), 'missing or symlinked native context')
                with destination.open('rb') as source:
                    observed = source.read(MAX_CONTEXT_BYTES + 1)
                context_response(observed, completion_raw=terminal, reply_raw=returned, request_raw=raw,
                                 input_raw=inner, identity=self.identity, deadline=self.deadline)
                self.live()
                save(folder / 'context.json', observed)
                save(folder / 'context-result.json', terminal)
                return sha(observed)
            time.sleep(min(.25, max(0, self.deadline - time.time())))
        raise ValueError('context terminal receipt attempt bound exhausted')

    def capture(self, phase, *, with_context=False):
        require(not with_context or self.identity.get('schemaVersion') == 2, 'context requires physical setup mode')
        require(not self.stopped or phase == 'cleanup', 'failed channel only permits cleanup capture')
        self.live(); self.sequence += 1
        folder = self.output / f'{self.sequence:04d}-{phase}'; folder.mkdir()
        raw, inner = message(self.identity, phase)
        fingerprint = sha(raw)
        require(fingerprint not in self.consumed, 'request publication reused')
        self.consumed.add(fingerprint)
        save(folder / 'request.json', raw); save(folder / 'input-request.json', inner)
        save(folder / 'marker', fingerprint.encode())
        prefix = 'Documents/' + self.identity['runID'] + '.operations-'
        try:
            self.transfer(self.remote.push, folder / 'request.json', prefix + 'request-' + fingerprint + '.json', 'operation-payload')
            self.transfer(self.remote.push, folder / 'marker', prefix + 'request', 'operation-publish')
            for attempt in range(1, 100_001):
                self.live()
                destination = folder / f'response-{attempt:06d}.json'
                if self.transfer(self.remote.pull, prefix + 'response-' + fingerprint + '.json', destination,
                                 'operation-response', optional=True):
                    require(destination.is_file() and not destination.is_symlink(), 'missing or symlinked native reply')
                    with destination.open('rb') as source:
                        returned = source.read(MAX_BYTES + 1)
                    # Actual downloaded bytes are retained before decoding.
                    capture_raw, capture = response(returned, raw, inner, self.identity)
                    save(folder / 'capture.json', capture_raw)
                    self.live()
                    context_hash = self.collect_context(folder, fingerprint, returned, raw, inner) if with_context else None
                    self.live()
                    save(folder / 'transport-result.json', encode(dict(state='CAPTURED', request_sha256=fingerprint,
                        response_sha256=sha(returned), capture_sha256=sha(capture_raw), context_sha256=context_hash,
                        idle_failure=capture.get('idleFailure'),
                        deadline=self.deadline, finished_at=time.time(), sdk_admitted=False, teardown_authorized=False)))
                    self.live()
                    return capture
                time.sleep(min(.25, max(0, self.deadline - time.time())))
            raise ValueError('channel response attempt bound exhausted')
        except Exception as error:
            self.stopped = True
            save(folder / 'transport-failure.json', encode(dict(state='INVALID', error_type=type(error).__name__,
                 deadline=self.deadline, finished_at=time.time(), sdk_admitted=False, teardown_authorized=False)))
            raise
