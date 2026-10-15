"""Exclusive supported-tool transport for one automatic diagnostic prefix.

The worker claims each request before its actual awaited call and publishes the
unaltered return. This protocol is separate from the empty-only human adapter.
"""
import argparse
import json
import math
from pathlib import Path
import sys
import time
import uuid

import human_supported_session as evidence
import prefix_input

require = evidence.require
TOOLS = dict(start=evidence.START, capture=evidence.CAPTURE, action=evidence.CAPTURE, end=evidence.END)


def artifacts(folder, raw):
    result = {}
    try:
        value = evidence.tool_value(raw)
    except Exception:
        return result
    for name in ('hierarchy', 'screenshot', 'logs'):
        path = value.get(name + 'Path')
        if not path:
            continue
        source = Path(path)
        if not (source.is_absolute() and source.is_file() and not source.is_symlink()
                and source.stat().st_size <= 25 * 1024 * 1024):
            continue
        target = folder / ('returned-' + name + source.suffix)
        with target.open('xb') as stream:
            stream.write(source.read_bytes())
        result[name] = dict(source_path=str(source), **evidence.reference(target))
    return result


def validate(request):
    require(request['kind'] == 'AUTOMATIC_PREFIX_TOOL_REQUEST' and request['operation'] in TOOLS
            and request['tool'] == TOOLS[request['operation']], 'foreign prefix request')
    binding = request['binding']; operation = request['operation']; args = request['arguments']
    require(all(isinstance(binding[k], str) and binding[k] for k in
                ('owner', 'device', 'bundle', 'run_id', 'plan_sha256', 'product_sha256')), 'incomplete tool binding')
    require(all(type(request[k]) in (int, float) and math.isfinite(request[k]) for k in ('issued_at', 'deadline'))
            and request['issued_at'] < request['deadline'], 'invalid fixed tool budget')
    require(str(uuid.UUID(request['request_id'])) == request['request_id'], 'invalid tool request id')
    if operation == 'start':
        require(args == dict(deviceIdentifier=binding['device'], sessionIdentifier='RUM prefix ' + binding['run_id'])
                and request['session_key'] is None, 'start reused identity or session')
    else:
        require(isinstance(request['session_key'], str) and request['session_key'], 'missing actual session key')
        start = Path(request['session_root']) / 'start'
        actual = evidence.tool_value(evidence.read(start / 'tool-result.json'))
        require(actual.get('deviceUUID') == binding['device'] and actual.get('deviceIsSimulator') is True
                and actual.get('interactionSessionKey') == request['session_key']
                and request['start_response'] == evidence.reference(start / 'response.json'), 'foreign session chain')
        if operation == 'end':
            require(args == dict(interactionSessionKey=request['session_key']), 'wrong end arguments')
        else:
            require(type(binding.get('pid')) is int and binding['pid'] > 0, 'capture has no original PID')
            command = ''
            if operation == 'action':
                ref = request['selection']; require(evidence.reference(ref['path']) == ref, 'selection changed')
                selected = evidence.read(ref['path'])
                require(selected['step'] == request['step'] and request['step'] in prefix_input.journey.flow('split','initial')
                        and selected['binding'] == binding
                        and selected['before_response'] == request['before_response'], 'foreign input selection')
                command = selected['selection']['command']
                require(command.startswith('t ') and command, 'non-prefix command')
            require(args == dict(interactSessionKey=request['session_key'], interactionCommand=command),
                    'unrequested input or activation')
    return request


def dispatch(request_path, owner, *, now=None):
    """The worker invokes this immediately before calling the returned tool."""
    request_path = Path(request_path); request = validate(evidence.read(request_path))
    now = time.time() if now is None else now
    require(owner == request['binding']['owner'] and request['issued_at'] <= now < request['deadline'],
            'wrong worker or expired tool request')
    root = Path(request['session_root'])
    for claim in root.glob('*/dispatch.json'):
        require(claim.with_name('response.json').is_file(), 'another supported call is unresolved')
    if request['operation'] == 'action':
        selected = evidence.read(request['selection']['path'])
        require(evidence.reference(selected['native_prefix']['path']) == selected['native_prefix'], 'native before bytes changed')
        prefix = Path(selected['native_prefix']['path']).read_bytes()
        before = selected['before']
        require(evidence.reference(request['before_response']['path']) == request['before_response'], 'actual before capture changed')
        captured = evidence.read(request['before_response']['path'])
        ref = captured['artifacts']['hierarchy']
        require(evidence.reference(ref['path']) == {k:ref[k] for k in ('path','sha256')}, 'input hierarchy changed')
        selected_binding = selected['selection']['provenance']['binding']
        require(selected['selection'] == prefix_input.select(Path(ref['path']).read_text(), before, request['step'],
                    selected_binding, request['binding']['bundle'], request['binding']['pid']), 'input command differs from current evidence')
        prefix_input.unconsumed(Path(selected['events_path']).read_bytes(), prefix, request['binding']['run_id'], before)
        # A process replacement cannot consume an old coordinate selection.
        import human_release
        require(human_release.process_identity(request['binding']['pid']) == selected['process_identity'], 'input process changed')
    evidence.save(request_path.with_name('dispatch.json'), dict(request=evidence.reference(request_path), owner=owner, at=now))
    return dict(tool=request['tool'], arguments=request['arguments'], deadline=request['deadline'])


def publish(request_path, raw, *, owner, started_at, finished_at):
    request_path = Path(request_path); folder = request_path.parent
    request = evidence.read(request_path)
    # Save the actual result even when late, erroneous or otherwise unqualified.
    evidence.save(folder / 'tool-result.json', raw)
    copied = {}; artifact_error = None
    try:
        copied = artifacts(folder, raw)
    except Exception as error:
        artifact_error = str(error)
    claim = evidence.read(folder / 'dispatch.json')
    value = dict(kind='AUTOMATIC_PREFIX_TOOL_RESPONSE', request=evidence.reference(request_path),
                 binding=request['binding'], owner=owner, tool=request['tool'], arguments=request['arguments'],
                 claim=evidence.reference(folder / 'dispatch.json'), started_at=started_at,
                 finished_at=finished_at, published_at=time.time(), result=evidence.reference(folder / 'tool-result.json'),
                 artifacts=copied, artifact_error=artifact_error)
    evidence.save(folder / 'response.json', value)
    require(claim['owner'] == owner, 'publisher differs from dispatched owner')
    if request['operation'] == 'end':
        claims = list(Path(request['session_root']).glob('*/dispatch.json'))
        require(all(p.with_name('response.json').is_file() for p in claims), 'pending supported call at completion')
        count = sum(evidence.read(p.with_name('request.json'))['operation'] == 'action' for p in claims)
        evidence.save(folder.parent / 'worker-completed.json', dict(owner=owner, pending_calls=0,
            input_commands=count, final_response=evidence.reference(folder / 'response.json'), at=time.time()))
    return value


def dispatch_or_reject(request_path, owner):
    """A rejected pre-call check has no invented MCP response or input count."""
    request_path=Path(request_path)
    try:
        return dict(state='DISPATCH', **dispatch(request_path,owner))
    except Exception as error:
        request=evidence.read(request_path)
        require(request['binding']['owner']==owner and not request_path.with_name('dispatch.json').exists()
                and not request_path.with_name('response.json').exists(), 'cannot relabel an already dispatched call')
        value=dict(kind='AUTOMATIC_PREFIX_NO_CALL',request=evidence.reference(request_path),
            binding=request['binding'],owner=owner,reason=str(error),published_at=time.time(),input_calls=0)
        evidence.save(request_path.with_name('response.json'),value)
        return dict(state='NO_CALL',response=evidence.reference(request_path.with_name('response.json')))


def returned(request_path, expected, *, now=None):
    request_path = Path(request_path); request = validate(evidence.read(request_path))
    require(request == expected, 'tool request changed after publication')
    response = evidence.read(request_path.with_name('response.json')); now = time.time() if now is None else now
    if response.get('kind')=='AUTOMATIC_PREFIX_NO_CALL':
        require(response['request']==evidence.reference(request_path) and response['binding']==request['binding']
                and response['owner']==request['binding']['owner'] and response['input_calls']==0
                and request['issued_at']<=response['published_at']<=now
                and not request_path.with_name('dispatch.json').exists()
                and not request_path.with_name('tool-result.json').exists(), 'foreign or contradictory no-call failure')
        raise ValueError('worker did not dispatch: '+response['reason'])
    claim = evidence.read(request_path.with_name('dispatch.json'))
    require(response['kind'] == 'AUTOMATIC_PREFIX_TOOL_RESPONSE'
            and response['request'] == evidence.reference(request_path) and response['binding'] == request['binding']
            and response['owner'] == request['binding']['owner'] and response['tool'] == request['tool']
            and response['arguments'] == request['arguments'] and response['claim'] == evidence.reference(request_path.with_name('dispatch.json'))
            and claim['request'] == evidence.reference(request_path) and claim['owner'] == response['owner'], 'foreign response or dispatch')
    clocks = [request['issued_at'], claim['at'], response['started_at'], response['finished_at'], response['published_at'], now]
    require(all(type(n) in (int, float) and math.isfinite(n) for n in clocks)
            and clocks == sorted(clocks) and now < request['deadline'], 'late or reordered tool response')
    require(response['result'] == evidence.reference(request_path.with_name('tool-result.json')), 'actual return changed')
    require(response['artifact_error'] is None, 'actual returned files could not be preserved')
    for ref in response['artifacts'].values():
        require(evidence.reference(ref['path']) == {k: ref[k] for k in ('path', 'sha256')}, 'actual returned artifact changed')
    return response, evidence.tool_value(evidence.read(request_path.with_name('tool-result.json')))


class Session:
    def __init__(self, folder, binding, *, seconds, deadline, emit=print):
        self.folder, self.binding = Path(folder), dict(binding)
        require(self.folder.is_dir() and not list(self.folder.iterdir()), 'consumed prefix session output')
        self.seconds, self.deadline, self.emit = seconds, deadline, emit
        self.key = None; self.start_response = None; self.ended = False; self.input_commands = 0
        check = self.folder / 'publication-preflight.json'
        evidence.save(check, dict(nonce=str(uuid.uuid4())))
        require(evidence.read(check)['nonce'], 'prefix response publication failed'); check.unlink()

    def exchange(self, label, operation, args, deadline, **extra):
        folder = self.folder / label; folder.mkdir()
        now = time.time()
        request = dict(kind='AUTOMATIC_PREFIX_TOOL_REQUEST', operation=operation,
            request_id=str(uuid.uuid4()), binding=dict(self.binding), tool=TOOLS[operation], arguments=args,
            session_root=str(self.folder), session_key=self.key, start_response=self.start_response,
            issued_at=now, deadline=min(deadline, now + self.seconds), **extra)
        validate(request); evidence.save(folder / 'request.json', request)
        self.emit(json.dumps(dict(automatic_prefix_tool=dict(request=str(folder / 'request.json'), operation=operation))))
        while time.time() < request['deadline']:
            if (folder / 'response.json').is_file():
                return returned(folder / 'request.json', request)
            time.sleep(.1)
        raise ValueError('supported prefix ' + operation + ' did not return before its fixed deadline')

    def start(self):
        _, actual = self.exchange('start', 'start', dict(deviceIdentifier=self.binding['device'],
            sessionIdentifier='RUM prefix ' + self.binding['run_id']), self.deadline)
        require(actual.get('deviceUUID') == self.binding['device'] and actual.get('deviceIsSimulator') is True,
                'wrong actual prefix device')
        self.key = actual.get('interactionSessionKey'); require(self.key, 'no actual prefix session key')
        self.start_response = evidence.reference(self.folder / 'start/response.json')

    def capture(self, pid):
        self.binding['pid'] = pid
        response, actual = self.exchange('initial', 'capture', dict(interactSessionKey=self.key, interactionCommand=''), self.deadline)
        self.hierarchy(response, actual)

    def hierarchy(self, response, actual):
        require(actual.get('applicationState') in ('Running', 'NotRun'), 'task is not foreground-capable')
        refs = response['artifacts']; require('hierarchy' in refs and 'screenshot' in refs, 'actual capture files incomplete')
        require(Path(refs['screenshot']['path']).read_bytes().startswith(b'\x89PNG\r\n\x1a\n'), 'actual screenshot is not PNG')
        raw = Path(refs['hierarchy']['path']).read_text()
        prefix_input.nodes(raw, self.binding['bundle'], self.binding['pid'])
        return raw

    def input(self, index, step, capture, before, deadline):
        require(index == self.input_commands + 1 and 1 <= index <= 13
                and step == prefix_input.journey.flow('split','initial')[index-1], 'skipped, duplicate or foreign prefix step')
        label = f'{index:02d}-before'
        response, actual = self.exchange(label, 'capture', dict(interactSessionKey=self.key, interactionCommand=''), deadline)
        raw = self.hierarchy(response, actual)
        selection = prefix_input.select(raw, before, step, capture.binding, self.binding['bundle'], self.binding['pid'])
        capture.live(deadline)
        prefix_input.unconsumed((capture.documents / 'events.jsonl').read_bytes(), capture.prefix, capture.run, before)
        folder = self.folder / label
        with (folder / 'native-prefix.jsonl').open('xb') as stream:
            stream.write(capture.prefix)
        selected = dict(step=step, binding=dict(self.binding), selection=selection, before=before,
            native_prefix=evidence.reference(folder / 'native-prefix.jsonl'), before_response=evidence.reference(folder / 'response.json'),
            events_path=str(capture.documents / 'events.jsonl'), process_identity=capture.process_identity)
        evidence.save(folder / 'selection.json', selected)
        response, actual = self.exchange(f'{index:02d}-action', 'action',
            dict(interactSessionKey=self.key, interactionCommand=selection['command']), deadline,
            step=step, selection=evidence.reference(folder / 'selection.json'), before_response=selected['before_response'])
        self.input_commands += 1
        self.hierarchy(response, actual)

    def end(self, deadline):
        require(not self.ended, 'prefix end consumed'); self.ended = True
        if self.key is None:
            # Failed start may still return a key. Recovery only; no input credit.
            actual = evidence.tool_value(evidence.read(self.folder / 'start/tool-result.json'))
            require(actual.get('deviceUUID') == self.binding['device'] and actual.get('deviceIsSimulator') is True, 'unresolved session owner')
            self.key = actual.get('interactionSessionKey'); require(self.key, 'unresolved session creation')
            self.start_response = evidence.reference(self.folder / 'start/response.json')
        _, actual = self.exchange('end', 'end', dict(interactionSessionKey=self.key), deadline)
        require(actual.get('userMessage') == 'Session stopped', 'session did not confirm End')
        end_request = evidence.read(self.folder / 'end/request.json')
        while not (self.folder / 'worker-completed.json').is_file():
            require(time.time() < end_request['deadline'], 'worker completion unavailable before deadline')
            time.sleep(.1)
        completed = evidence.read(self.folder / 'worker-completed.json')
        actual_count = sum(evidence.read(p.with_name('request.json'))['operation'] == 'action'
                           for p in self.folder.glob('*/dispatch.json'))
        require(completed['owner'] == self.binding['owner'] and completed['pending_calls'] == 0
                and type(completed['input_commands']) is int and completed['input_commands'] == actual_count
                and completed['final_response'] == evidence.reference(self.folder / 'end/response.json')
                and end_request['issued_at'] <= completed['at'] <= time.time() < end_request['deadline'], 'worker has not quiesced')
        self.input_commands = completed['input_commands']
        evidence.save(self.folder / 'ended.json', dict(state='PASS', completion=evidence.reference(self.folder / 'worker-completed.json'),
                                                       input_commands=self.input_commands))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['dispatch', 'publish'])
    parser.add_argument('--request', type=Path, required=True); parser.add_argument('--owner', required=True)
    parser.add_argument('--started', type=float); parser.add_argument('--finished', type=float); args = parser.parse_args()
    if args.action == 'dispatch': print(json.dumps(dispatch_or_reject(args.request, args.owner)))
    else:
        publish(args.request, json.load(sys.stdin), owner=args.owner, started_at=args.started, finished_at=args.finished)
        print(json.dumps(dict(state='ACTUAL_RETURN_PUBLISHED')))
