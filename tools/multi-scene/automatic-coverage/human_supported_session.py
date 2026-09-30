"""One supported Xcode session, with request-bound, unmodified tool evidence.

The tool owner calls Xcode. This module only publishes requests and validates
actual returns; it cannot synthesize input or replace a missing observation.
"""
import hashlib
import json
import math
from pathlib import Path
import re
import time
import uuid


START = 'DeviceInteractionStartSession'
CAPTURE = 'DeviceInteractionSynthesize'
END = 'DeviceInteractionEndSession'
TOOLS = {'start': START, 'capture': CAPTURE, 'end': END}
HOME_IDS = ('screen.home', 'home.tap', 'home.toggle', 'home.scroll', 'home.receipt', 'home.next')


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    # A response is published last. Readers never consume a partial file.
    path = Path(path)
    pending = path.with_name(path.name + '.' + str(uuid.uuid4()) + '.pending')
    with pending.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')
        stream.flush()
        __import__('os').fsync(stream.fileno())
    try:
        __import__('os').link(pending, path)
    finally:
        pending.unlink()


def read(path):
    path = Path(path)
    require(path.is_file() and not path.is_symlink(), 'missing or redirected session artifact')
    return json.loads(path.read_bytes())


def reference(path):
    return dict(path=str(Path(path).resolve()), sha256=sha(path))


def tool_value(raw):
    require(isinstance(raw, dict) and not raw.get('isError'), 'Xcode tool returned an error')
    if isinstance(raw.get('structuredContent'), dict):
        return raw['structuredContent']
    blocks = raw.get('content', [])
    texts = [row['text'] for row in blocks if row.get('type') == 'text']
    require(len(texts) == 1, 'ambiguous Xcode tool result')
    value = json.loads(texts[0])
    require(isinstance(value, dict), 'invalid Xcode tool result')
    return value


def arguments(phase, binding, session_key=None):
    require(phase in TOOLS, 'unsupported session phase')
    if phase == 'start':
        require(session_key is None, 'start must not reuse a session key')
        return dict(deviceIdentifier=binding['device'], sessionIdentifier='RUM SwiftUI ' + binding['run_id'])
    require(isinstance(session_key, str) and session_key.strip(), 'missing actual session key')
    if phase == 'capture':
        return dict(interactSessionKey=session_key, interactionCommand='')
    return dict(interactionSessionKey=session_key)


def validate_request(request):
    require(request.get('kind') == 'SUPPORTED_SESSION_REQUEST' and request.get('schema_version') == 1,
            'foreign session request')
    phase = request['phase']
    binding = request['binding']
    for key in ('owner', 'device', 'bundle', 'run_id', 'product_sha256', 'plan_sha256'):
        require(isinstance(binding.get(key), str) and binding[key].strip(), 'missing session binding: ' + key)
    require(request['tool'] == TOOLS[phase]
            and request['arguments'] == arguments(phase, binding, request.get('session_key')),
            'unrequested tool, input or activation')
    require(str(uuid.UUID(request['request_id'])) == request['request_id'], 'invalid request identity')
    if phase != 'start':
        require(type(binding.get('pid')) is int and binding['pid'] > 0 or phase == 'end',
                'capture requires actual launch PID')
        require(isinstance(request.get('start_response_sha256'), str)
                and len(request['start_response_sha256']) == 64, 'capture/end precedes session receipt')
    require(all(type(request[k]) in (int, float) and math.isfinite(request[k])
                for k in ('issued_at', 'deadline')) and request['issued_at'] < request['deadline'],
            'invalid fixed session clock')
    return request


def publish_response(request_path, raw, *, owner, started_at, finished_at, published_at=None):
    """Called by the same tool owner after its actual awaited Xcode call.

    Preserve errors and late returns too. Acceptance checks are deliberately
    separate so a failing response cannot disappear during validation.
    """
    request_path = Path(request_path)
    request = read(request_path)
    folder = request_path.parent
    save(folder/'tool-result.json', raw)
    value = dict(kind='SUPPORTED_SESSION_RESPONSE', request_id=request['request_id'],
                 request_sha256=sha(request_path), binding=request['binding'],
                 tool=request['tool'], arguments=request['arguments'], owner=owner,
                 started_at=started_at, finished_at=finished_at,
                 published_at=time.time() if published_at is None else published_at,
                 result=reference(folder/'tool-result.json'))
    save(folder/'response.json', value)
    if request['phase'] == 'end':
        # The owner publishes this only after its final awaited tool call and
        # must then leave the transaction without further device operations.
        save(folder.parent/'worker-completed.json', dict(kind='SUPPORTED_TOOL_OWNER_COMPLETED',
             owner=owner, binding=request['binding'], final_response=reference(folder/'response.json'),
             pending_calls=0, input_commands=0, at=time.time() if published_at is None else published_at))
    return value


def validate_response(request_path, *, now=None, expected_request=None):
    request_path = Path(request_path)
    request = validate_request(read(request_path))
    require(expected_request is None or request == expected_request, 'session request changed after publication')
    response = read(request_path.with_name('response.json'))
    require(response.get('kind') == 'SUPPORTED_SESSION_RESPONSE'
            and response.get('request_id') == request['request_id']
            and response.get('request_sha256') == sha(request_path)
            and response.get('binding') == request['binding']
            and response.get('owner') == request['binding']['owner']
            and response.get('tool') == request['tool']
            and response.get('arguments') == request['arguments'], 'foreign or substituted session return')
    clocks = [response.get(k) for k in ('started_at', 'finished_at', 'published_at')]
    require(all(type(x) in (int, float) and math.isfinite(x) for x in clocks), 'invalid response clock')
    require(request['issued_at'] <= clocks[0] <= clocks[1] <= clocks[2]
            <= (time.time() if now is None else now) < request['deadline'], 'late or reordered session return')
    result_path = request_path.with_name('tool-result.json')
    require(response['result'] == reference(result_path), 'raw response replaced or changed')
    if request['phase'] != 'start':
        start_folder = request_path.parent.parent/'start'
        start_request = validate_request(read(start_folder/'request.json'))
        start_response = read(start_folder/'response.json')
        start_raw = tool_value(read(start_folder/'tool-result.json'))
        require(request['start_response_sha256'] == sha(start_folder/'response.json')
                and request['session_key'] == start_raw.get('interactionSessionKey')
                and all(request['binding'][k] == v for k,v in start_request['binding'].items())
                and start_response['finished_at'] <= request['issued_at'],
                'capture/end detached from actual session creation')
        if request['phase'] == 'capture':
            prior_request, prior_value = validate_response(start_folder/'request.json', now=start_response['published_at'])
            start_value(prior_request, prior_value)
    return request, tool_value(read(result_path))


def start_value(request, value):
    require(request['phase'] == 'start' and value.get('deviceIsSimulator') is True
            and value.get('deviceUUID') == request['binding']['device'], 'wrong supported session device')
    key = value.get('interactionSessionKey')
    require(isinstance(key, str) and key.strip(), 'Xcode did not return a session key')
    return key


def hierarchy_owner(raw, bundle, pid):
    headers = re.findall(r'Application bundle identifier: ([^\n]+)\nApplication UI orientation: [^\n]+\nApplication, pid: ([0-9]+),', raw)
    require(headers.count((bundle, str(pid))) == 1
            and sum(name == bundle for name, _ in headers) == 1,
            'hierarchy does not uniquely identify the launched task app')
    sections = re.split(r'(?=Application bundle identifier: )', raw)
    section = next(s for s in sections if s.startswith('Application bundle identifier: ' + bundle + '\n'))
    for identifier in HOME_IDS:
        require(re.search(r"identifier: ['\"]" + re.escape(identifier) + r"['\"]", section),
                'supported hierarchy missing source control: ' + identifier)
    return dict(bundle=bundle, pid=pid, identifiers=list(HOME_IDS))


def capture_value(request, value, folder):
    require(request['phase'] == 'capture', 'not a capture response')
    folder = Path(folder)
    artifacts = {}
    # Source paths come from this raw response only, never from older captures.
    for name, key in [('hierarchy', 'hierarchyPath'), ('screenshot', 'screenshotPath')]:
        source = Path(value.get(key, ''))
        require(source.is_absolute() and source.is_file() and not source.is_symlink(),
                'missing actual returned ' + name)
        raw = source.read_bytes()
        if name == 'screenshot':
            require(raw.startswith(b'\x89PNG\r\n\x1a\n'), 'actual screenshot is not PNG')
        target = folder/('returned-' + name + ('.png' if name == 'screenshot' else '.txt'))
        with target.open('xb') as stream:
            stream.write(raw)
        artifacts[name] = dict(source_path=str(source), **reference(target))
    require(value.get('applicationState') in ('NotRun', 'Running'), 'task is not observable in a foreground-capable state')
    proof = hierarchy_owner(Path(artifacts['hierarchy']['path']).read_text(),
                            request['binding']['bundle'], request['binding']['pid'])
    return dict(state='SUPPORTED_HIERARCHY_JOINED', owner=proof, artifacts=artifacts,
                application_state=value.get('applicationState'))


class Session:
    def __init__(self, folder, binding, *, seconds, deadline, emit=print):
        self.folder = Path(folder)
        require(self.folder.is_dir() and not list(self.folder.iterdir()), 'session output already consumed')
        self.binding = dict(binding)
        self.seconds = seconds
        self.deadline = deadline
        self.emit = emit
        self.key = None
        self.start_sha = None
        self.ended = False
        check = self.folder/'publication-preflight.json'
        save(check, {'nonce': str(uuid.uuid4())})
        require(read(check)['nonce'], 'session publication failed')
        check.unlink()

    def exchange(self, phase, deadline):
        folder = self.folder/phase
        folder.mkdir()
        now = time.time()
        request = dict(kind='SUPPORTED_SESSION_REQUEST', schema_version=1, phase=phase,
                       request_id=str(uuid.uuid4()), binding=dict(self.binding), tool=TOOLS[phase],
                       arguments=arguments(phase, self.binding, self.key), session_key=self.key,
                       start_response_sha256=self.start_sha, issued_at=now,
                       deadline=min(deadline, now+self.seconds))
        validate_request(request)
        save(folder/'request.json', request)
        self.emit(json.dumps({'supported_session': dict(phase=phase, request=str(folder/'request.json'))}))
        while time.time() < request['deadline']:
            if (folder/'response.json').is_file():
                return validate_response(folder/'request.json', expected_request=request)
            time.sleep(.1)
        raise ValueError('supported ' + phase + ' response unavailable before its fixed deadline')

    def start(self):
        request, value = self.exchange('start', self.deadline)
        self.key = start_value(request, value)
        self.start_sha = sha(self.folder/'start/response.json')
        save(self.folder/'session.json', dict(key=self.key, binding=self.binding,
                                            start_response_sha256=self.start_sha))

    def capture(self, pid):
        require(self.key is not None and not self.ended and 'pid' not in self.binding,
                'capture is consumed or precedes supported start')
        self.binding['pid'] = pid
        request, value = self.exchange('capture', self.deadline)
        proof = capture_value(request, value, self.folder/'capture')
        save(self.folder/'capture/proof.json', proof)
        return proof

    def end(self, deadline):
        require(not self.ended, 'session end already consumed')
        self.ended = True
        # An erroneous/late start can still expose a key that needs restoration.
        # Retaining that response for cleanup never makes the start qualified.
        if self.key is None:
            response_path = self.folder/'start/response.json'
            require(response_path.exists(), 'session creation unresolved; task teardown is not authorized')
            response = read(response_path)
            require(response['published_at'] <= time.time(), 'session start publication is in the future')
            request, value = validate_response(self.folder/'start/request.json', now=response['published_at'])
            require(request['binding'] == self.binding, 'cleanup start belongs to another owner')
            self.key = start_value(request, value)
            self.start_sha = sha(response_path)
        request, value = self.exchange('end', deadline)
        require(value.get('userMessage') == 'Session stopped', 'supported session did not confirm closure')
        completed = self.folder/'worker-completed.json'
        while not completed.exists():
            require(time.time() < request['deadline'], 'tool owner completion unavailable')
            time.sleep(.1)
        worker = read(completed)
        require(worker == dict(kind='SUPPORTED_TOOL_OWNER_COMPLETED', owner=self.binding['owner'],
            binding=self.binding, final_response=reference(self.folder/'end/response.json'),
            pending_calls=0,input_commands=0,at=worker.get('at'))
            and request['issued_at'] <= worker['at'] <= time.time() < request['deadline'],
            'wrong or late tool owner completion')
        proof = dict(state='PASS', request=reference(self.folder/'end/request.json'),
                     response=reference(self.folder/'end/response.json'), finished_at=time.time())
        save(self.folder/'ended.json', proof)
        return proof
