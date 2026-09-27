"""One-use human setup and cleanup barriers for the existing same-key runner."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import time
import uuid

import same_key_contract as contract
_release_path = Path(__file__).resolve().parents[1] / 'interactive-transitions/physical_release.py'
_release_spec = importlib.util.spec_from_file_location('same_key_physical_release', _release_path)
physical_release = importlib.util.module_from_spec(_release_spec)
sys.modules[_release_spec.name] = physical_release
_release_spec.loader.exec_module(physical_release)
from capture_io import atomic, encoded


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def read(path):
    return json.loads(Path(path).read_bytes())


def publish(path, value):
    atomic(Path(path), encoded(value))


def envelope(value, identity):
    contract.require(all(value.get(k) == v for k, v in identity.items()), 'foreign human setup identity')


def idle(value, *, owners=None):
    rows = value.get('input')
    contract.require(isinstance(rows, list) and rows, 'native input inventory missing')
    contract.require(len({r['window'] for r in rows}) == len(rows), 'duplicate native input window')
    for row in rows:
        contract.require(row['window'] and row['controller'] and row['scene']
                         and type(row['touches']) is int and row['touches'] == 0
                         and row['transitioning'] is False and row['resizing'] is False,
                         'native input or window transition remains active')
    actual = {(r['scene'], r['window'], r['controller']) for r in rows}
    if owners is not None:
        expected = {(r['scene'], r['window'], r['controller']) for r in owners.values()}
        contract.require(actual == expected, 'native idle ownership differs')
    return sorted(actual)


def capture(raw, request_raw, identity, *, phase, owners=None):
    value = json.loads(raw); request = json.loads(request_raw)
    envelope(value, identity); envelope(request, identity)
    contract.require(value.get('phase') == phase and value.get('nonce') == request['nonce']
                     and value.get('request_sha256') == sha(request_raw), 'stale or foreign native capture')
    if phase == 'setup-ready':
        contract.require(value.get('operations') == [] and value.get('setup_admission') == {},
                         'API work preceded human setup')
        owners = contract.topology(value)
    idle(value, owners=owners)
    return value, owners


class Barrier:
    """The root runner owns calls; the input observer never changes deadlines."""
    def __init__(self, folder, documents, identity, setup_deadline, api_seconds=300):
        self.folder = Path(folder) / 'human-setup'; self.folder.mkdir()
        self.documents = Path(documents)
        self.identity = identity
        self.setup_deadline = setup_deadline
        self.api_seconds = api_seconds
        self.ready = None; self.start = None; self.owners = None
        self.setup_request = None
        self.operator_request = self.ask('setup', setup_deadline,
            'Arrange both task windows side by side. Release all input and confirm Ready. '
            'No API assertions have started; do not close either window.')

    def ask(self, phase, deadline, instruction):
        folder = self.folder / ('operator-' + phase); folder.mkdir()
        request = dict(kind='HUMAN_RELEASE_REQUIRED', request_id=str(uuid.uuid4()),
                       run_id=self.identity['run_id'], issued_at=time.time(), deadline=deadline,
                       instruction=instruction)
        path = folder / 'request.json'; publish(path, request)
        print(json.dumps(dict(human_setup=dict(phase=phase, request_path=str(path), **request))), flush=True)
        return path

    @staticmethod
    def released(path, now):
        reply = path.with_name('operator-released.json')
        if not reply.exists():
            return False
        raw = path.read_bytes()
        physical_release.validate_ack(json.loads(raw), raw, read(reply), now)
        return True

    def native_request(self, kind, name):
        value = dict(self.identity, kind=kind, nonce=str(uuid.uuid4()))
        raw = encoded(value)
        atomic(self.folder / name, raw)
        atomic(self.documents / name, raw)
        return raw

    def poll(self, admit):
        if self.start is not None:
            return
        contract.require(time.time() < self.setup_deadline, 'human setup budget expired')
        if self.setup_request is None:
            if not self.released(self.operator_request, time.time()):
                return
            self.setup_request = self.native_request('SETUP_CAPTURE', 'setup-request.json')
        path = self.documents / 'setup-ready.json'
        if not path.exists():
            return
        raw = path.read_bytes(); atomic(self.folder / 'setup-ready.json', raw)
        value, owners = capture(raw, self.setup_request, self.identity, phase='setup-ready')
        contract.require(time.time() < self.setup_deadline, 'late human setup capture')
        self.ready = value; self.owners = owners
        start = dict(self.identity, kind='START_API', ready_sha256=sha(raw), nonce=str(uuid.uuid4()))
        record = dict(start=start, started_at=time.time())
        record['execution_deadline'] = record['started_at'] + self.api_seconds
        publish(self.folder / 'api-admission.json', record)
        # Publish the runner deadline before the native app can consume START_API.
        admit(record)
        self.start = start
        publish(self.documents / 'setup-start.json', start)

    def validate(self, native):
        contract.require(self.start is not None, 'API work before setup admission')
        expected = {k: self.start[k] for k in ['ready_sha256', 'nonce']}
        contract.require(native.get('setup_admission') == expected, 'unbound API setup admission')
        contract.require(contract.topology(native) == self.owners, 'prepared topology changed')

    def cleanup(self, deadline):
        release_limit = min(deadline - 45, time.time() + 180)
        contract.require(time.time() < release_limit, 'no human cleanup reserve')
        request = self.ask('cleanup', release_limit,
            'The API check has stopped. Release all input and confirm Released. '
            'The task app stays open until native idle is verified.')
        while not self.released(request, time.time()):
            contract.require(time.time() < release_limit, 'operator release missing; preserve task app')
            time.sleep(.2)
        raw_request = self.native_request('CLEANUP_CAPTURE', 'cleanup-request.json')
        path = self.documents / 'cleanup-idle.json'
        while not path.exists():
            contract.require(time.time() < deadline, 'native idle missing; preserve task app')
            time.sleep(.2)
        raw = path.read_bytes(); atomic(self.folder / 'cleanup-idle.json', raw)
        value, _ = capture(raw, raw_request, self.identity, phase='cleanup-idle', owners=self.owners)
        if self.start is not None:
            contract.require(value.get('setup_admission') == {k: self.start[k] for k in ['ready_sha256', 'nonce']},
                             'cleanup admission changed')
        contract.require(time.time() < deadline, 'late native idle; preserve task app')
        publish(self.folder / 'cleanup-qualified.json', dict(state='PASS', at=time.time(),
            deadline=deadline, capture_sha256=sha(raw), operator_reply_sha256=sha(request.with_name('operator-released.json').read_bytes())))
