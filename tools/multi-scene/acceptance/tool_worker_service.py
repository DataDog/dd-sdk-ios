"""A local file-delivery service; readiness never authorizes a native tool call."""
import argparse
import copy
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import urllib.request
import urllib.parse
import uuid


def require(value, message):
    if not value:
        raise ValueError(message)


def reference(path):
    path = Path(path)
    require(path.is_file() and not path.is_symlink(), 'missing or redirected worker artifact')
    require(path.name != 'Datadog.local.xcconfig', 'configuration is not a worker artifact')
    path = path.resolve()
    return dict(path=str(path), sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def read(path):
    reference(path)
    return json.loads(Path(path).read_bytes())


def save_bytes(path, raw):
    """Publish complete bytes exclusively; a partial write is never a ready file."""
    path = Path(path)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(raw); stream.flush(); os.fsync(stream.fileno())
            os.link(temporary, path)
        finally:
            temporary.unlink()


def save(path, value):
    save_bytes(path, (json.dumps(value, sort_keys=True, indent=2) + '\n').encode())


def value_reference(path, value):
    """Hash issued bytes, never replacement bytes read after publication."""
    raw = (json.dumps(value, sort_keys=True, indent=2) + '\n').encode()
    return dict(path=str(Path(path).resolve()), sha256=hashlib.sha256(raw).hexdigest())


def process_identity(pid):
    require(type(pid) is int and pid > 0, 'invalid service process')
    result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'lstart=,comm='],
                            capture_output=True, text=True, timeout=5)
    require(result.returncode == 0 and result.stdout.strip(), 'worker service process absent')
    return result.stdout.strip()


def sources_current(sources):
    require(isinstance(sources, dict) and sources, 'worker setup sources missing')
    for path, digest in sources.items():
        require(reference(path)['sha256'] == digest, 'worker setup source changed')


def binding_current(binding):
    require(set(binding) == {'owner', 'device', 'bundle', 'run_id', 'plan_sha256', 'product_sha256'},
            'worker binding fields differ')
    require(all(isinstance(v, str) and v for v in binding.values()), 'incomplete worker binding')
    require(str(uuid.UUID(binding['run_id'])) == binding['run_id'], 'invalid worker run')
    require(all(len(binding[k]) == 64 and all(c in '0123456789abcdef' for c in binding[k])
                for k in ('plan_sha256', 'product_sha256')), 'invalid worker byte identity')


def budget_floors(observed, *, steps, passive_snapshot, settle):
    """Prospective resource bounds, never latency or SDK acceptance thresholds."""
    require(type(steps) is int and 1 <= steps <= 64, 'invalid serial step count')
    values = [observed['transport_seconds'], observed['inspection_seconds'], passive_snapshot, settle]
    require(all(type(v) in (int, float) and math.isfinite(v) and v >= 0 for v in values)
            and passive_snapshot > 0, 'invalid observed budget inputs')
    rounded = lambda n: max(30, math.ceil(n / 30) * 30)
    transport = rounded(observed['transport_seconds'] * 1.5)
    inspection = rounded(observed['inspection_seconds'] * 1.5)
    request = transport + inspection
    # Each step has before/action returns and their inspections, plus four
    # passive snapshots. Bootstrap/fold and End/idle/removal have their reserves.
    step = rounded(2 * request + 4 * passive_snapshot + settle)
    return dict(request=request, step=step,
                native=rounded(steps * step + 3 * request + 4 * passive_snapshot + 240),
                cleanup=rounded(request + passive_snapshot + 120))


def validate_budgets(budgets, observed, *, steps):
    require(set(budgets) == {'request', 'step', 'native', 'cleanup', 'passive_snapshot', 'settle'},
            'incomplete prospective phase budgets')
    require(type(budgets['passive_snapshot']) in (int, float)
            and math.isfinite(budgets['passive_snapshot']) and 0 < budgets['passive_snapshot'] <= 120
            and type(budgets['settle']) in (int, float) and math.isfinite(budgets['settle'])
            and 0 <= budgets['settle'] <= 30, 'unbounded passive or settling phase')
    floors = budget_floors(observed, steps=steps, passive_snapshot=budgets['passive_snapshot'],
                          settle=budgets['settle'])
    require(all(type(budgets[k]) in (int, float) and math.isfinite(budgets[k])
                and floors[k] <= budgets[k] <= 14400 for k in floors),
            'prospective bounds omit serial capture or inspection phases')
    return floors


def budget_ledger(observations, *, passive_snapshot, settle, budgets=None):
    """Bind the thirteen-step composition to preserved operational costs."""
    require(set(observations) == {'assessment', 'request', 'response'}, 'missing observed cost sources')
    for ref in observations.values():
        require(reference(ref['path']) == ref, 'observed cost source changed')
    assessment = read(observations['assessment']['path'])
    request = read(observations['request']['path']); response = read(observations['response']['path'])
    require(assessment['state'] == 'STOPPED_BEFORE_INPUT_ASSESSED'
            and request['operation'] == 'action' and response['kind'] == 'AUTOMATIC_PREFIX_NO_CALL'
            and response['input_calls'] == 0 and response['request'] == observations['request']
            and response['binding'] == request['binding'] and response['owner'] == request['binding']['owner'],
            'operational observations differ from stopped pre-call failure')
    rows = [v for k, v in assessment['timings'].items() if k != 'start']
    require(rows, 'capture transport observations missing')
    require(all(type(v[k]) in (int, float) and math.isfinite(v[k]) and v[k] >= 0
                for v in rows for k in ('issued_to_claim_seconds', 'native_call_seconds',
                                        'return_to_publication_seconds')),
            'invalid observed transport costs')
    observed = dict(transport_seconds=max(sum(v[k] for k in ('issued_to_claim_seconds',
        'native_call_seconds', 'return_to_publication_seconds')) for v in rows),
        inspection_seconds=response['published_at'] - request['issued_at'])
    floors = budget_floors(observed, steps=13, passive_snapshot=passive_snapshot, settle=settle)
    chosen = dict(floors, passive_snapshot=passive_snapshot, settle=settle) if budgets is None else budgets
    validate_budgets(chosen, observed, steps=13)
    return dict(kind='PROSPECTIVE_PREFIX_BUDGET', observations=copy.deepcopy(observations), observed=observed,
        steps=13, margin=1.5, round_up_seconds=30,
        per_step=dict(returned_captures=2, image_inspections=2, passive_snapshots=4, settle=1),
        native_overhead=dict(requests=3, passive_snapshots=4, install_launch_seconds=120,
                             fold_observation_seconds=120),
        cleanup_overhead=dict(end_requests=1, passive_snapshots=1, stop_restore_seconds=120),
        floors=floors, budgets=copy.deepcopy(chosen), timing_acceptance=False)


def validate_ledger(ledger, budgets):
    expected = budget_ledger(ledger['observations'], passive_snapshot=budgets['passive_snapshot'],
                             settle=budgets['settle'], budgets=budgets)
    require(ledger == expected, 'prospective composition or observed ledger changed')
    return ledger


def window(budgets):
    require(all(type(budgets[k]) in (int, float) and math.isfinite(budgets[k])
                and 0 < budgets[k] <= 14400 for k in ('native', 'cleanup')), 'invalid prospective worker window')
    return budgets['native'] + budgets['cleanup'] + 30


def pump_current(answer, record):
    pump = answer['pump_process']
    require(pump['pid'] != record['pid'] and process_identity(pump['pid']) == pump['identity'],
            'exclusive pump absent or replaced; service health is insufficient')


def setup_current(answer, record, folder):
    """Rejoin actual pump startup and tool-discovery bytes, not a health echo."""
    require(answer['setup'] == reference(folder / 'pump-setup.json'), 'pump setup receipt changed')
    setup = read(answer['setup']['path'])
    require(setup == dict(kind='TOOL_PUMP_SETUP', service=reference(folder / 'service.json'),
        binding=record['binding'], sources=record['sources'], pump_source=record['pump_source'],
        pump_process=answer['pump_process'], contract=setup.get('contract'), loaded_at=answer['loaded_at'],
        native_calls=0, pending_calls=0), 'pump startup differs from its actual answer')
    require(setup['contract'] == reference(folder / 'pump-contract.json'), 'pump contract bytes changed')
    contract = read(setup['contract']['path'])
    require(contract['kind'] == 'TOOL_PUMP_CONTRACT'
            and contract['discovery_source'] in ('LIVE_TOOL_DISCOVERY', 'SYNTHETIC_CONTROL')
            and set(contract['tools']) == {'DeviceInteractionStartSession',
                'DeviceInteractionSynthesize', 'DeviceInteractionEndSession'}
            and all(isinstance(v, str) and v.strip() for v in contract['tools'].values())
            and record['started_at'] <= contract['discovered_at'] <= answer['loaded_at'],
            'pump tool discovery missing, stale or incomplete')
    return contract


def invalidate(folder, name, error):
    path = folder / name
    if path.exists():
        path.rename(folder / ('invalidated-' + name))
    save(folder / (name + '.failure.json'), dict(state='INVALID', reason=str(error), native_authority=False))


class Service:
    def __init__(self, folder, binding, sources, pump_source, requests, *, seconds):
        binding_current(binding); sources_current(sources)
        require(reference(pump_source['path']) == pump_source
                and sources.get(pump_source['path']) == pump_source['sha256'], 'unbound pump source')
        require(type(seconds) in (int, float) and math.isfinite(seconds) and 0 < seconds <= 14400,
                'invalid original service budget')
        self.folder = Path(folder).resolve(); require(not self.folder.exists(), 'worker service output consumed')
        self.folder.mkdir()
        self.binding, self.sources, self.pump_source = copy.deepcopy((binding, sources, pump_source))
        self.requests = Path(requests).resolve()
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), self.handler())
        self.server.daemon_threads = True
        now = time.time()
        self.record = dict(kind='TOOL_WORKER_SERVICE', binding=self.binding, sources=self.sources,
            pump_source=self.pump_source, requests=str(self.requests), folder=str(self.folder),
            url='http://127.0.0.1:' + str(self.server.server_port), instance=str(uuid.uuid4()),
            pid=os.getpid(), process_identity=process_identity(os.getpid()), started_at=now,
            deadline=now + seconds, native_authority=False)
        save(self.folder / 'service.json', self.record)

    def live(self):
        require(time.time() < self.record['deadline'], 'original worker service cutoff expired')
        require(read(self.folder / 'service.json') == self.record, 'worker service registration changed')
        sources_current(self.sources)
        require(process_identity(self.record['pid']) == self.record['process_identity'], 'worker service replaced')

    def handler(self):
        service = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_GET(self):
                self.reply(False)

            def do_POST(self):
                self.reply(True)

            def reply(self, post):
                try:
                    service.live()
                    if self.path == '/health' and not post:
                        value = service.record
                    elif self.path == '/probe' and post:
                        length = int(self.headers.get('Content-Length', '0'))
                        require(0 < length <= 65536, 'invalid probe size')
                        raw = self.rfile.read(length); request = json.loads(raw)
                        require(request['kind'] == 'TOOL_PUMP_PROBE' and request['binding'] == service.binding
                                and request['service'] == reference(service.folder / 'service.json')
                                and str(uuid.UUID(request['nonce'])) == request['nonce']
                                and request['issued_at'] <= time.time() < request['deadline'] <= service.record['deadline'],
                                'foreign or expired pump probe')
                        save_bytes(service.folder / 'probe.json', raw)
                        service.live()
                        require(time.time() < request['deadline'], 'probe publication late')
                        value = dict(request=reference(service.folder / 'probe.json'))
                    elif self.path == '/pending' and not post:
                        probe = service.folder / 'probe.json'
                        if probe.exists() and not (service.folder / 'answer.json').exists():
                            value = dict(kind='PROBE', request=reference(probe))
                        else:
                            # Delivery only. Existing dispatchers still check every
                            # exact native request and its original cutoff.
                            pending = []
                            if (service.folder / 'consumed.json').is_file():
                                for path in service.requests.glob('*/request.json'):
                                    if not path.with_name('response.json').exists():
                                        row = read(path)
                                        require(all(row['binding'].get(k) == v for k, v in service.binding.items()),
                                                'foreign queued native request')
                                        pending.append(reference(path))
                            require(len(pending) <= 1, 'overlapping queued native requests')
                            value = dict(kind='FILES', requests=pending)
                    elif self.path == '/answer' and post:
                        length = int(self.headers.get('Content-Length', '0'))
                        require(0 < length <= 65536, 'invalid answer size')
                        raw = self.rfile.read(length)
                        save_bytes(service.folder / 'answer.json', raw)
                        answer = json.loads(raw); request = read(service.folder / 'probe.json')
                        require(answer == dict(kind='TOOL_PUMP_PREPARED',
                            request=reference(service.folder / 'probe.json'), binding=service.binding,
                            sources=service.sources, pump_source=service.pump_source,
                            pump_process=answer.get('pump_process'), loaded_at=answer.get('loaded_at'),
                            setup=answer.get('setup'),
                            native_calls=0, pending_calls=0, native_authority=False)
                            and service.record['started_at'] <= answer['loaded_at'] <= time.time() < request['deadline'],
                            'pump answer lacks current setup or arrived late')
                        pump_current(answer, service.record)
                        setup_current(answer, service.record, service.folder)
                        save(service.folder / 'publication.json', dict(answer=reference(service.folder / 'answer.json'),
                            request=reference(service.folder / 'probe.json'), at=time.time()))
                        try:
                            service.live(); pump_current(answer, service.record)
                            require(time.time() < request['deadline'], 'pump publication late')
                        except Exception as error:
                            invalidate(service.folder, 'publication.json', error)
                            raise
                        value = dict(state='PUMP_ANSWER_PUBLISHED', publication=reference(service.folder / 'publication.json'))
                    else:
                        raise ValueError('unknown worker service operation')
                    code = 200
                except Exception as error:
                    code, value = 409, dict(state='REJECTED', reason=str(error))
                raw = json.dumps(value).encode()
                self.send_response(code); self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(raw))); self.end_headers(); self.wfile.write(raw)

        return Handler


def health(folder):
    folder = Path(folder).resolve(); record = read(folder / 'service.json')
    require(record['kind'] == 'TOOL_WORKER_SERVICE' and record['native_authority'] is False
            and record['folder'] == str(folder), 'foreign worker service')
    url = urllib.parse.urlsplit(record['url'])
    require(url.scheme == 'http' and url.hostname == '127.0.0.1' and url.port is not None
            and 0 < url.port < 65536 and not url.path and not url.query and not url.fragment
            and url.username is None and url.password is None, 'nonlocal worker route')
    require(time.time() < record['deadline']
            and process_identity(record['pid']) == record['process_identity'], 'worker unavailable or expired')
    sources_current(record['sources'])
    with urllib.request.urlopen(record['url'] + '/health', timeout=3) as response:
        require(json.load(response) == record, 'actual worker service differs from registration')
    return record


def probe(folder, binding, *, seconds=120):
    folder = Path(folder); record = health(folder); binding_current(binding)
    require(record['binding'] == binding and not (folder / 'probe.json').exists(), 'foreign or consumed worker probe')
    require(type(seconds) in (int, float) and math.isfinite(seconds) and 0 < seconds <= 120, 'invalid probe budget')
    now = time.time()
    value = dict(kind='TOOL_PUMP_PROBE', binding=binding, nonce=str(uuid.uuid4()),
                 service=reference(folder / 'service.json'), issued_at=now,
                 deadline=min(record['deadline'], now + seconds))
    request = urllib.request.Request(record['url'] + '/probe', data=json.dumps(value).encode(),
                                    headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=3) as response:
        require(json.load(response) == dict(request=reference(folder / 'probe.json')), 'probe publication differs')
    return value


def qualify(folder, binding, budgets):
    folder = Path(folder); record = health(folder)
    require(record['binding'] == binding, 'worker readiness belongs to another plan')
    request = read(folder / 'probe.json'); answer = read(folder / 'answer.json')
    publication = read(folder / 'publication.json'); now = time.time()
    require(request['binding'] == binding and request['service'] == reference(folder / 'service.json')
            and request['issued_at'] <= publication['at'] <= now < request['deadline'], 'expired or foreign worker proof')
    require(answer == dict(kind='TOOL_PUMP_PREPARED', request=reference(folder / 'probe.json'),
        binding=binding, sources=record['sources'], pump_source=record['pump_source'],
        pump_process=answer.get('pump_process'), loaded_at=answer.get('loaded_at'),
        setup=answer.get('setup'),
        native_calls=0, pending_calls=0, native_authority=False)
        and record['started_at'] <= answer['loaded_at'] <= publication['at'], 'worker pump not prepared')
    require(publication['answer'] == reference(folder / 'answer.json')
            and publication['request'] == reference(folder / 'probe.json'), 'worker publication bytes changed')
    pump_current(answer, record)
    setup_current(answer, record, folder)
    require(now + window(budgets) < record['deadline'], 'service cannot cover execution and cleanup')
    result = dict(state='WORKER_PREREQUISITE_QUALIFIED', service=reference(folder / 'service.json'),
        probe=reference(folder / 'probe.json'), answer=reference(folder / 'answer.json'),
        publication=reference(folder / 'publication.json'), binding=binding, budgets=copy.deepcopy(budgets),
        at=now, native_authority=False, gates_closed=[])
    issued_reference = value_reference(folder / 'qualified.json', result)
    save(folder / 'qualified.json', result)
    try:
        require(reference(folder / 'qualified.json') == issued_reference, 'issued qualification bytes changed')
        current = health(folder); pump_current(answer, current)
        setup_current(answer, current, folder)
        require(time.time() < request['deadline'] and time.time() + window(budgets) < current['deadline'],
                'worker qualification publication was late')
        for key, filename in (('service', 'service.json'), ('probe', 'probe.json'),
                              ('answer', 'answer.json'), ('publication', 'publication.json')):
            require(result[key] == reference(folder / filename), 'worker changed after qualification publication')
    except Exception as error:
        invalidate(folder, 'qualified.json', error)
        raise
    return result


def consume(folder, binding, budgets):
    folder = Path(folder); record = health(folder); proof = read(folder / 'qualified.json'); now = time.time()
    require(proof['state'] == 'WORKER_PREREQUISITE_QUALIFIED' and proof['binding'] == binding
            and record['binding'] == binding and proof['budgets'] == budgets
            and proof['native_authority'] is False and proof['gates_closed'] == [], 'foreign worker qualification')
    for key, filename in (('service', 'service.json'), ('probe', 'probe.json'),
                          ('answer', 'answer.json'), ('publication', 'publication.json')):
        require(proof[key] == reference(folder / filename), 'qualified worker evidence changed')
    require(proof['at'] <= now < read(folder / 'probe.json')['deadline']
            and now + window(budgets) < record['deadline'], 'worker proof or service reserve expired')
    pump_current(read(folder / 'answer.json'), record)
    setup_current(read(folder / 'answer.json'), record, folder)
    value = dict(state='WORKER_PREREQUISITE_CONSUMED', proof=reference(folder / 'qualified.json'),
        binding=copy.deepcopy(binding), issued_at=now, execution_deadline=now + budgets['native'],
        cleanup_deadline=now + budgets['native'] + budgets['cleanup'],
        controller=dict(pid=os.getpid(), identity=process_identity(os.getpid())), native_authority=False)
    issued_reference = value_reference(folder / 'consumed.json', value)
    save(folder / 'consumed.json', value)
    try:
        require(reference(folder / 'consumed.json') == issued_reference, 'issued consumption bytes changed')
        current = health(folder); pump_current(read(folder / 'answer.json'), current)
        setup_current(read(folder / 'answer.json'), current, folder)
        require(reference(folder / 'qualified.json') == value['proof']
                and time.time() < read(folder / 'probe.json')['deadline']
                and value['cleanup_deadline'] + 30 < current['deadline'], 'worker changed after consumption')
        for key, filename in (('service', 'service.json'), ('probe', 'probe.json'),
                              ('answer', 'answer.json'), ('publication', 'publication.json')):
            require(proof[key] == reference(folder / filename), 'worker bytes changed after consumption')
    except Exception as error:
        invalidate(folder, 'consumed.json', error)
        raise
    return value


def active(folder, consumed):
    """Keep this delivery route available through actual End and completion."""
    folder = Path(folder); require(reference(folder / 'consumed.json') == consumed, 'worker consumption changed')
    record = health(folder); pump_current(read(folder / 'answer.json'), record)
    setup_current(read(folder / 'answer.json'), record, folder)
    value = read(folder / 'consumed.json')
    require(reference(folder / 'qualified.json') == value['proof']
            and value['controller'] == dict(pid=os.getpid(),identity=process_identity(os.getpid())),
            'admitting controller or readiness bytes changed')
    proof = read(folder / 'qualified.json')
    require(value['binding'] == proof['binding'] == record['binding'], 'active delivery owner changed')
    clocks = [value['issued_at'], value['execution_deadline'], value['cleanup_deadline']]
    require(all(type(v) in (int,float) and math.isfinite(v) for v in clocks)
            and proof['at'] <= clocks[0] < clocks[1] < clocks[2]
            and clocks[0] < read(folder / 'probe.json')['deadline'], 'invalid consumed clocks')
    expected = dict(state='WORKER_PREREQUISITE_CONSUMED',proof=reference(folder / 'qualified.json'),
        binding=proof['binding'],issued_at=clocks[0],execution_deadline=clocks[0]+proof['budgets']['native'],
        cleanup_deadline=clocks[0]+proof['budgets']['native']+proof['budgets']['cleanup'],
        controller=value['controller'],native_authority=False)
    require(value == expected and consumed == value_reference(folder / 'consumed.json',expected),
            'consumed clocks or complete receipt differ from issued budgets')
    for key, filename in (('service', 'service.json'), ('probe', 'probe.json'),
                          ('answer', 'answer.json'), ('publication', 'publication.json')):
        require(proof[key] == reference(folder / filename), 'active delivery evidence changed')
    require(time.time() < value['cleanup_deadline'] and value['cleanup_deadline'] + 30 < record['deadline'],
            'worker delivery route lacks the original cleanup reserve')
    return value


def stop_owned(folder, *, deadline, consumed=None, expected_service=None):
    """Stop this service only before consumption or after the existing End proof."""
    folder = Path(folder); record = read(folder / 'service.json')
    completion = None
    if consumed is None:
        require(not (folder / 'consumed.json').exists(), 'admitted service must survive End and completion')
        require(expected_service == reference(folder / 'service.json'), 'owned service bytes changed before shutdown')
    else:
        active(folder, consumed)
        expected_service = read(read(folder / 'consumed.json')['proof']['path'])['service']
        root = Path(record['requests']); ended = read(root / 'ended.json')
        complete = read(root / 'worker-completed.json')
        response = read(root / 'end/response.json'); request = read(root / 'end/request.json')
        require(ended['state'] == 'PASS' and ended['completion'] == reference(root / 'worker-completed.json')
                and complete['pending_calls'] == 0 and complete['owner'] == record['binding']['owner']
                and complete['final_response'] == reference(root / 'end/response.json')
                and response['kind'] == 'AUTOMATIC_PREFIX_TOOL_RESPONSE'
                and response['request'] == reference(root / 'end/request.json')
                and request['operation'] == 'end' and request['session_root'] == str(root)
                and all(request['binding'][k] == v for k, v in record['binding'].items()),
                'service shutdown lacks the existing worker End and completion')
        claims = list(root.glob('*/dispatch.json'))
        require(claims and all(p.with_name('response.json').is_file() for p in claims)
                and complete['input_commands'] == ended['input_commands'] ==
                    sum(read(p.with_name('request.json'))['operation'] == 'action' for p in claims),
                'service shutdown has an unresolved dispatched call')
        require(response['result'] == reference(root / 'end/tool-result.json'), 'actual End return changed')
        raw = read(root / 'end/tool-result.json')
        actual = raw.get('structuredContent')
        if actual is None:
            texts = [r['text'] for r in raw.get('content', []) if r.get('type') == 'text']
            require(len(texts) == 1, 'ambiguous actual End return')
            actual = json.loads(texts[0])
        require(not raw.get('isError') and actual.get('userMessage') == 'Session stopped',
                'actual End did not stop this session')
        completion = reference(root / 'ended.json')
    require(type(deadline) in (int,float) and math.isfinite(deadline)
            and time.time() < deadline <= min(record['deadline'],time.time()+30)
            and expected_service == reference(folder / 'service.json') and record['pid'] != os.getpid()
            and record['folder'] == str(folder.resolve())
            and process_identity(record['pid']) == record['process_identity'], 'service cleanup ownership absent')
    save(folder / 'stop-request.json', dict(service=reference(folder / 'service.json'),
        consumed=consumed, completion=completion, issued_at=time.time(), deadline=deadline, native_cleanup=False))
    os.kill(record['pid'], signal.SIGTERM)
    while time.time() < deadline:
        result = subprocess.run(['/bin/ps', '-p', str(record['pid']), '-o', 'stat='],
                                capture_output=True, text=True, timeout=3)
        if result.returncode != 0:
            save(folder / 'stop-result.json', dict(state='OWNED_SERVICE_STOPPED', pid=record['pid'],
                at=time.time(), native_cleanup=False))
            return
        if result.stdout.strip().startswith('Z'):
            try: os.waitpid(record['pid'], os.WNOHANG)
            except ChildProcessError: pass
        time.sleep(.1)
    raise ValueError('owned service absence unavailable before original stop cutoff')


def stop_before_admission(folder, *, deadline, expected_service):
    stop_owned(folder, deadline=deadline, expected_service=expected_service)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--setup', type=Path, required=True); args = parser.parse_args()
    setup = read(args.setup)
    service = Service(setup['folder'], setup['binding'], setup['sources'], setup['pump_source'],
                      setup['requests'], seconds=setup['seconds'])
    print(json.dumps(dict(state='SERVICE_STARTED_ONLY', service=reference(service.folder / 'service.json'))), flush=True)
    try:
        while time.time() < service.record['deadline']:
            service.server.timeout = min(1, max(.001, service.record['deadline'] - time.time()))
            service.server.handle_request()
    finally:
        service.server.server_close()
