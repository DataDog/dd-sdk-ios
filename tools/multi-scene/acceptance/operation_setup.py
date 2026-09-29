"""H06 host prerequisites; the native one-use guard must still admit SDK work.

The caller supplies the existing physical_io.Device and capture-only Channel.
This helper neither launches apps nor authorizes input, Operations or teardown.
"""
import base64
import ctypes
import importlib.util
import math
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import time
from urllib.parse import unquote, urlparse
import uuid

import installed_code
import operation_transport as t

_release_spec = importlib.util.spec_from_file_location('operation_physical_release',
    Path(__file__).resolve().parents[1] / 'interactive-transitions/physical_release.py')
release = importlib.util.module_from_spec(_release_spec)
_release_spec.loader.exec_module(release)


def read(path, maximum=t.MAX_CONTEXT_BYTES):
    path = Path(path)
    t.require(path.is_file() and not path.is_symlink(), 'missing or symlinked proof input')
    with path.open('rb') as source:
        value = source.read(maximum + 1)
    t.require(len(value) <= maximum, 'oversized proof input')
    return value


def native_response(raw):
    # CoreDevice inventories can exceed the small app-channel message limit.
    # Preserve the existing bounded host-context limit and strict JSON parser.
    return t.load(raw, maximum=t.MAX_CONTEXT_BYTES)


def file_sha(path):
    path = Path(path)
    t.require(path.is_file() and not path.is_symlink(), 'missing or symlinked proof artifact')
    import hashlib
    with path.open('rb') as source:
        digest = hashlib.sha256()
        for chunk in iter(lambda: source.read(65536), b''):
            digest.update(chunk)
    return digest.hexdigest()


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def command(argv, folder, label, deadline):
    """Small read-only host commands, with actual stdout retained before checks."""
    remaining = deadline - time.time()
    t.require(remaining > 0, 'host prerequisite deadline expired')
    started = time.time()
    try:
        result = subprocess.run(argv, capture_output=True, timeout=min(30, remaining), check=False)
        receipt = dict(argv=argv, started_at=started, finished_at=time.time(), returncode=result.returncode,
                       stdout=result.stdout.decode(errors='replace'), stderr=result.stderr.decode(errors='replace'))
    except subprocess.TimeoutExpired as error:
        receipt = dict(argv=argv, started_at=started, finished_at=time.time(), returncode=None,
                       stdout=(error.stdout or b'').decode(errors='replace'),
                       stderr=(error.stderr or b'').decode(errors='replace'))
    t.save(folder / (label + '.json'), t.encode(receipt))
    t.require(receipt['returncode'] == 0 and receipt['finished_at'] < deadline, 'host prerequisite failed or late')
    return receipt


def current_host_executable():
    # libproc.h: proc_pidpath(int, void *, uint32_t), maximum 4 * MAXPATHLEN.
    # This API is deliberately not parameterized with a device PID.
    query = ctypes.CDLL('/usr/lib/libproc.dylib').proc_pidpath
    query.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    query.restype = ctypes.c_int
    buffer = ctypes.create_string_buffer(4096)
    count = query(os.getpid(), buffer, len(buffer))
    t.require(0 < count < len(buffer), 'kernel host executable identity unavailable')
    return buffer.value.decode()


def host_identity(folder, label, deadline):
    pid = os.getpid()  # Never pass a physical device PID to a host process query.
    observed = command(['/bin/ps', '-p', str(pid), '-o', 'pid=,lstart=,comm='], folder, label, deadline)
    match = re.fullmatch(r'\s*' + str(pid) + r'\s+(.+?)\s+(/[^\n]+)\n?', observed['stdout'])
    t.require(match is not None, 'host process launch identity unavailable')
    executable = Path(match[2]).resolve()
    kernel = current_host_executable()
    t.save(folder / (label + '-binary.json'), t.encode(dict(pid=pid, kernelExecutable=kernel,
                                                           pythonLauncher=sys.executable)))
    t.require(executable == Path(kernel).resolve(), 'host executable differs from kernel process identity')
    return dict(pid=pid, start=match[1], executable=str(executable), executableSHA256=file_sha(executable),
                pythonLauncher=str(Path(sys.executable).resolve()))


def release_request(identity, deadline):
    t.require(finite(deadline) and time.time() < deadline, 'closed setup deadline')
    return dict(kind='HUMAN_RELEASE_REQUIRED', request_id=str(uuid.uuid4()), run_id=identity['runID'],
                channel_identity_sha256=t.sha(t.encode(identity)), phase='operations.setup',
                issued_at=time.time(), deadline=deadline,
                instruction='Arrange both task windows side by side, release all input and confirm Ready. '
                            'The checks will then run automatically; leave both windows visible.')


def display(raw):
    screens = raw.get('result', {}).get('displays', [])
    t.require(isinstance(screens, list) and len(screens) == 1, 'ambiguous physical display inventory')
    screen = screens[0]
    t.require(screen.get('primary') is True and screen.get('type') == {'integrated': {}}
              and screen.get('backlightState') == 'activeOn'
              and ('active' not in screen or screen['active'] is True), 'physical display not active and primary')
    t.require(type(screen.get('displayId')) is int and screen['displayId'] >= 0
              and screen.get('currentOrientation') in ['rot0', 'rot90', 'rot180', 'rot270']
              and finite(screen.get('pointScale')) and screen['pointScale'] > 0
              and isinstance(screen.get('nativeSize'), list) and len(screen['nativeSize']) == 2
              and all(finite(v) and v > 0 for v in screen['nativeSize']),
              'physical display identity or geometry missing')
    bounds = screen.get('bounds')
    t.require(isinstance(bounds, list) and len(bounds) == 2
              and all(isinstance(pair, list) and len(pair) == 2 and all(finite(v) for v in pair) for pair in bounds)
              and all(v > 0 for v in bounds[1]), 'actual physical display pixel bounds missing')
    return {k: screen[k] for k in ['displayId', 'type', 'primary', 'nativeSize', 'pointScale',
                                  'currentOrientation', 'bounds']}


def device_process(raw, identity, product, app_name):
    rows = raw.get('result', {}).get('runningProcesses')
    t.require(isinstance(rows, list), 'missing physical process inventory')
    selected = [r for r in rows if type(r.get('processIdentifier')) is int
                and r['processIdentifier'] == identity['processID']]
    t.require(len(selected) == 1 and isinstance(selected[0].get('executable'), str),
              'physical process absent or aliased')
    executable = selected[0]['executable']
    path = Path(unquote(urlparse(executable).path))
    t.require(path.is_absolute() and path.parts[-2:] == (app_name, product['executable']),
              'physical process executable differs from signed app')
    return dict(processID=identity['processID'], executable=executable)


def visible_owners(capture):
    # Bind the review to the captured native identities. Swift remains the sole
    # semantic idle/owner oracle and rechecks its exact snapshot on consumption.
    t.require('idleFailure' not in capture and capture['before'] == capture['after'], 'native capture is not stable/idle')
    rows = capture['after'].get('input')
    t.require(isinstance(rows, list) and [r.get('logicalSceneID') for r in rows] == ['scene-A', 'scene-B'],
              'missing captured fixture owner inventory')
    fields = ['nativeSceneID', 'generation', 'windowIdentity', 'rootIdentity']
    owners = {row['logicalSceneID']: {k: row[k] for k in fields} for row in rows}
    t.require(all(type(row['generation']) is int and row['generation'] > 0
                  and all(isinstance(row[k], str) and row[k] for k in fields if k != 'generation')
                  for row in owners.values()), 'invalid captured native identities')
    t.require(all(len({row[k] for row in owners.values()}) == 2 for k in fields if k != 'generation'),
              'captured native identities are aliased')
    return owners


STARTUP_ABSENT_PATHS = {
    'Library/Caches/com.datadoghq', 'Library/Application Support/com.datadoghq',
    'Library/Caches/com.datadoghq.logs', 'Library/Caches/com.datadoghq.traces',
    'Library/Caches/com.datadoghq.rum', 'Library/Application Support/ProbeAcceptance',
}


def startup_freshness(raw, identity, bundle, nonce):
    """Validate the pre-SDK observation, never recheck emptiness after startup."""
    value = t.load(raw)
    t.require(set(value) == {'schemaVersion', 'runID', 'scenarioID', 'sourceRevision', 'processID',
                            'bundleIdentifier', 'nonce', 'boundary', 'paths', 'releaseAcceptance'},
              'startup freshness receipt shape differs')
    t.require(isinstance(nonce, str) and str(uuid.UUID(nonce)) == nonce, 'invalid frozen startup nonce')
    t.require(type(value['schemaVersion']) is int and value['schemaVersion'] == 1
              and value['runID'] == identity['runID']
              and value['scenarioID'] == identity['setupProfile']['scenario']
              and value['sourceRevision'] == identity['profile']['sourceRevision']
              and type(value['processID']) is int and value['processID'] == identity['processID']
              and value['bundleIdentifier'] == bundle and value['nonce'] == nonce
              and value['boundary'] == 'before-sdk-and-probe-writer'
              and value['releaseAcceptance'] is False, 'stale or invalid startup identity')
    paths = value['paths']
    t.require(isinstance(paths, dict) and set(paths) == STARTUP_ABSENT_PATHS | {'Documents'}
              and paths['Documents'] in ['ABSENT', 'EMPTY']
              and all(paths[p] == 'ABSENT' for p in STARTUP_ABSENT_PATHS),
              'startup freshness path inventory differs')
    return value


class HostSetup:
    """One frozen challenge, one real release, one unarmed capture and one proof.

    A failed proof consumes this host attempt. Cleanup requires a separate fresh
    release/native-idle path; this class never terminates or uninstalls anything.
    """
    def __init__(self, channel, app, installed_raw, expected, *, startup_raw):
        self.channel, self.remote = channel, channel.remote
        self.app = Path(app); self.installed_raw = installed_raw
        self.startup_raw = bytes(startup_raw)
        self.expected = t.load(t.encode(expected))
        self.folder = channel.output / 'host-setup'
        self.folder.mkdir()
        self.used = False
        try:
            t.save(self.folder / 'expected.json', t.encode(self.expected))
            t.save(self.folder / 'challenge.json', t.encode(channel.identity))
            self.identity = t.challenge(t.encode(channel.identity), run_id=expected['run_id'],
                process_id=expected['process_id'], profile=expected['profile'], installed_code=installed_raw,
                setup_profile=expected['setup_profile'])
            t.require(self.remote.identifier == expected['device'] and channel.bundle == expected['product']['bundleIdentifier'],
                      'host channel device or container differs')
            t.save(self.folder / 'startup-freshness.json', startup_raw)
            startup_freshness(startup_raw, self.identity, channel.bundle, self.expected['startup_nonce'])
            self.request_raw = t.encode(release_request(self.identity, channel.deadline))
            t.save(self.folder / 'release-request.json', self.request_raw)
        except Exception as error:
            self.record_failure(error)
            raise

    def record_failure(self, error):
        t.save(self.folder / 'failure.json', t.encode(dict(state='INVALID', errorType=type(error).__name__,
            nativeEvidence=str(self.remote.output), deadline=self.channel.deadline, finishedAt=time.time(),
            sdkAdmitted=False, teardownAuthorized=False)))

    def live(self):
        self.channel.live()
        t.require(not self.channel.stopped, 'capture channel already failed')
        t.require(t.encode(self.channel.identity) == t.encode(self.identity)
                  and self.remote.identifier == self.expected['device']
                  and self.channel.bundle == self.expected['product']['bundleIdentifier'], 'channel identity changed')

    def native(self, args, label):
        self.live()
        result, receipt = self.remote.command(args, 'operation-setup-' + label, self.channel.deadline)
        source = self.remote.output / (f'{self.remote.sequence:05d}-operation-setup-' + label)
        # Retain the bytes from this command, not an equivalent earlier response.
        raw = read(source / 'response.json')
        t.save(self.folder / (label + '-response.json'), raw)
        observed_receipt = read(source / 'receipt.json')
        t.save(self.folder / (label + '-receipt.json'), observed_receipt)
        t.require(native_response(raw) == result and t.load(observed_receipt) == receipt
                  and receipt['response_sha256'] == t.sha(raw), 'native return differs from saved observation')
        t.require(type(receipt.get('returncode')) is int and receipt['returncode'] == 0
                  and receipt['before'] == receipt['remaining'] == [] and receipt.get('quiescence_error') is None
                  and all(finite(receipt.get(k)) for k in ['started_at', 'finished_at', 'deadline'])
                  and self.released_at <= receipt['started_at'] <= receipt['finished_at']
                  < min(receipt['deadline'], self.channel.deadline), 'native command failed, late or unreaped')
        info = result.get('info', {}); actual = info.get('arguments', [])
        t.require(info.get('outcome') == 'success' and info.get('commandType') == 'devicectl.' + '.'.join(args[:3])
                  and isinstance(actual, list) and actual.count('--device') == 1
                  and actual[actual.index('--device') + 1] == self.remote.identifier, 'foreign native command')
        for flag, value in zip(args[3::2], args[4::2]):
            t.require(actual.count(flag) == 1 and actual[actual.index(flag) + 1] == value, 'native argument differs')
        self.live()
        return result

    def collect(self, acknowledgement_raw, review):
        t.require(not self.used, 'host setup already consumed')
        self.used = True
        try:
            self.live()
            t.require(read(self.folder / 'startup-freshness.json') == self.startup_raw,
                      'startup freshness observation changed before setup')
            t.save(self.folder / 'release-ack.json', acknowledgement_raw)
            request = t.load(self.request_raw); acknowledgement = t.load(acknowledgement_raw)
            t.require(request['phase'] == 'operations.setup' and request['run_id'] == self.identity['runID']
                      and request['channel_identity_sha256'] == t.sha(t.encode(self.identity))
                      and request['deadline'] == self.channel.deadline and t.identifier(request['request_id'])
                      and all(finite(v) for v in [request['issued_at'], request['deadline'], acknowledgement.get('at')]),
                      'release identity or original deadline differs')
            release.validate_ack(request, self.request_raw, acknowledgement, time.time())
            self.released_at = acknowledgement['at']
            t.save(self.folder / 'release-consumed.json', t.encode(dict(requestSHA256=t.sha(self.request_raw), at=time.time())))
            t.save(self.folder / 'installed-code.json', self.installed_raw)
            product = installed_code.validate(t.load(self.installed_raw), self.app, self.identity['runID'],
                                              self.identity['profile']['sourceRevision'], self.identity['processID'])
            t.require(all(product[k] == self.expected['product'][k] for k in ['bundleIdentifier', 'executable', 'binaries']),
                      'signed product differs from frozen manifest')
            command(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(self.app)],
                    self.folder, 'signature', self.channel.deadline)
            host = host_identity(self.folder, 'host-before', self.channel.deadline)
            details = self.native(['device', 'info', 'details'], 'device')['result']
            hardware, properties = details['hardwareProperties'], details['deviceProperties']
            t.require(hardware['reality'] == 'physical' and hardware['deviceType'] == 'iPad'
                      and hardware['udid'] == self.expected['udid'] and properties['developerModeStatus'] == 'enabled'
                      and properties['ddiServicesAvailable'] is True, 'physical iPad prerequisites differ')
            lock = self.native(['device', 'info', 'lockState'], 'lock')['result']
            t.require(lock['passcodeRequired'] is False and lock['unlockedSinceBoot'] is True, 'physical device locked')
            process = device_process(self.native(['device', 'info', 'processes'], 'process-before'), self.identity,
                                     self.expected['product'], self.app.name)
            self.live()
            start = time.time()
            t.save(self.folder / 'capture-started.json', t.encode(dict(at=start, releaseSHA256=t.sha(acknowledgement_raw))))
            capture = self.channel.capture('setup', with_context=True)
            captured = self.channel.output / f'{self.channel.sequence:04d}-setup'
            originals = {name: read(captured / name) for name in
                         ['request.json', 'input-request.json', 'capture.json', 'context.json', 'context-result.json', 'transport-result.json']}
            transport = t.load(originals['transport-result.json'])
            replies = [read(path) for path in captured.glob('response-*.json')]
            replies = [raw for raw in replies if t.sha(raw) == transport['response_sha256']]
            t.require(len(replies) == 1, 'successful channel reply missing or ambiguous')
            originals['reply.json'] = replies[0]
            for name, raw in originals.items():
                t.save(self.folder / ('native-' + name), raw)
            context = t.load(originals['context.json'], maximum=t.MAX_CONTEXT_BYTES)
            t.require(context['captureSHA256'] == t.sha(originals['capture.json'])
                      and t.load(originals['capture.json']) == capture, 'returned setup capture was substituted')
            owners = visible_owners(capture)
            screen_raw = self.native(['device', 'info', 'displays'], 'display')
            screen = display(screen_raw)
            image = self.folder / 'screen.png'
            shot = self.native(['device', 'capture', 'screenshot', '--destination', str(image)], 'screenshot')['result']
            image_bytes = read(image, maximum=32 * 1024 * 1024)
            t.require(len(image_bytes) >= 33 and image_bytes[:8] == b'\x89PNG\r\n\x1a\n'
                      and image_bytes[12:16] == b'IHDR', 'missing screenshot image')
            width, height = struct.unpack('>II', image_bytes[16:24])
            t.require(width > 0 and height > 0 and type(shot.get('width')) is int and type(shot.get('height')) is int
                      and [width, height] == [shot['width'], shot['height']] == screen['bounds'][1]
                      and shot.get('deviceIdentifier') == self.remote.identifier and shot.get('imageFormat') == 'png'
                      and isinstance(shot.get('destination'), str)
                      and Path(unquote(urlparse(shot['destination']).path)) == image,
                      'screenshot pixels, destination or physical display bounds differ')
            review_request = dict(kind='OPERATIONS_DISPLAY_REVIEW', identitySHA256=t.sha(t.encode(self.identity)),
                device=self.remote.identifier, processID=self.identity['processID'], captureSHA256=t.sha(originals['capture.json']),
                contextSHA256=t.sha(originals['context.json']), displaySHA256=t.sha(read(self.folder / 'display-response.json')),
                screenshotSHA256=t.sha(image_bytes), screenshot=str(image), imageSize=[width, height],
                owners=owners, issuedAt=time.time(), deadline=self.channel.deadline)
            review_request_raw = t.encode(review_request)
            t.save(self.folder / 'display-review-request.json', review_request_raw)
            frozen = {p.name: file_sha(p) for p in self.folder.iterdir()}
            review_raw = review(t.load(review_request_raw), self.channel.deadline)
            t.save(self.folder / 'display-review.json', review_raw)
            reviewed = t.load(review_raw)
            t.require(set(reviewed) == {'requestSHA256', 'decision', 'reviewer', 'reviewedAt', 'visibleOwners'}
                      and reviewed['requestSHA256'] == t.sha(review_request_raw)
                      and reviewed['decision'] == 'both-fixture-window-contents-visible'
                      and isinstance(reviewed['reviewer'], str) and reviewed['reviewer'].strip()
                      and finite(reviewed['reviewedAt']) and review_request['issuedAt'] <= reviewed['reviewedAt'] <= time.time()
                      and isinstance(reviewed['visibleOwners'], dict) and set(reviewed['visibleOwners']) == set(owners),
                      'missing, stale or foreign display review')
            for name, owner in owners.items():
                visible = reviewed['visibleOwners'][name]
                t.require(set(visible) == {*owner, 'visibleRegion'} and all(visible[k] == v for k, v in owner.items()),
                          'display review maps different native owners')
                rect = visible['visibleRegion']
                t.require(isinstance(rect, list) and len(rect) == 4 and all(finite(v) for v in rect)
                          and rect[0] >= 0 and rect[1] >= 0 and rect[2] > 0 and rect[3] > 0
                          and rect[0] + rect[2] <= width and rect[1] + rect[3] <= height, 'visible content region outside actual image')
            a, b = [reviewed['visibleOwners'][name]['visibleRegion'] for name in ['scene-A', 'scene-B']]
            overlap = max(0, min(a[0]+a[2], b[0]+b[2]) - max(a[0], b[0])) * max(
                0, min(a[1]+a[3], b[1]+b[3]) - max(a[1], b[1]))
            t.require(overlap < a[2]*a[3] and overlap < b[2]*b[3], 'visible fixture regions lack distinct content')
            t.require(display(self.native(['device', 'info', 'displays'], 'display-after')) == screen,
                      'display changed after capture')
            t.require(device_process(self.native(['device', 'info', 'processes'], 'process-after'), self.identity,
                      self.expected['product'], self.app.name) == process, 'physical process changed after capture')
            t.require(host_identity(self.folder, 'host-after', self.channel.deadline) == host, 'host process identity changed')
            t.require(all(file_sha(self.folder / name) == digest for name, digest in frozen.items()),
                      'prerequisite evidence changed during review')
            self.live()
            proof = dict(schemaVersion=1, kind='OPERATIONS_HOST_PREREQUISITES', state='HOST_PROOF_PREPARED',
                         identity=self.identity, device=self.remote.identifier, udid=self.expected['udid'],
                         bundleIdentifier=self.channel.bundle, hostProcess=host, deviceProcess=process,
                         consumptionID=str(uuid.uuid4()), captureSHA256=t.sha(originals['capture.json']),
                         contextSHA256=t.sha(originals['context.json']), installedCodeSHA256=t.sha(self.installed_raw),
                         requestSHA256=t.sha(originals['request.json']), replySHA256=t.sha(originals['reply.json']),
                         completionSHA256=t.sha(originals['context-result.json']), screenshotSHA256=t.sha(image_bytes),
                         reviewSHA256=t.sha(review_raw),
                         releaseRequestSHA256=t.sha(self.request_raw), releaseSHA256=t.sha(acknowledgement_raw),
                         display=screen, displayPixelConvention='coredevice-display-bounds-pixels',
                         visibleOwners=reviewed['visibleOwners'], deadline=self.channel.deadline,
                         artifacts={p.name: file_sha(p) for p in sorted(self.folder.iterdir())},
                         finishedAt=time.time(), sdkAdmitted=False, teardownAuthorized=False)
            proof_raw = t.encode(proof)
            t.save(self.folder / ('proof-' + t.sha(proof_raw) + '.json'), proof_raw)
            self.live()
            t.save(self.folder / 'result.json', t.encode(dict(state='HOST_PROOF_PREPARED', proofSHA256=t.sha(proof_raw),
                deadline=self.channel.deadline, finishedAt=time.time(), sdkAdmitted=False, teardownAuthorized=False)))
            self.live()
            return proof
        except Exception as error:
            self.record_failure(error)
            raise


    def publish(self):
        """Publish this completed proof once; only the native guard can admit it.

        Payload precedes the immutable marker. A failed or partial publication
        consumes this host attempt and leaves its original proof unchanged.
        """
        folder = self.folder / 'publication'
        folder.mkdir()
        try:
            self.live()
            t.require(self.used and not (self.folder / 'failure.json').exists(), 'host prerequisites incomplete')
            result_raw = read(self.folder / 'result.json')
            result = t.load(result_raw)
            t.require(result['state'] == 'HOST_PROOF_PREPARED' and t.digest(result['proofSHA256'])
                      and result['deadline'] == self.channel.deadline and result['finishedAt'] < self.channel.deadline
                      and result['sdkAdmitted'] is False and result['teardownAuthorized'] is False, 'invalid host result')
            proof_raw = read(self.folder / ('proof-' + result['proofSHA256'] + '.json'))
            proof = t.load(proof_raw)
            t.require(t.sha(proof_raw) == result['proofSHA256'] and proof['identity'] == self.identity
                      and proof['deadline'] == self.channel.deadline and proof['state'] == result['state']
                      and proof['sdkAdmitted'] is False and proof['teardownAuthorized'] is False,
                      'host proof changed before publication')
            t.require(all(file_sha(self.folder / name) == digest for name, digest in proof['artifacts'].items()),
                      'host prerequisite changed before publication')
            bridge = getattr(self, 'display_bridge', None)
            if bridge is not None:
                proof_raw, result_raw = bridge.extend_host(proof_raw, result_raw)
                result = t.load(result_raw)
            payload = t.encode(dict(schemaVersion=1, identity=self.identity,
                proof=base64.b64encode(proof_raw).decode(), result=base64.b64encode(result_raw).decode()))
            t.require(len(payload) <= t.MAX_CONTEXT_BYTES, 'host handoff too large')
            digest = t.sha(payload)
            source = folder / ('host-publication-' + digest + '.json'); t.save(source, payload)
            marker = folder / 'host-publication'; t.save(marker, digest.encode())
            prefix = 'Documents/' + self.identity['runID'] + '.operations-'
            self.channel.transfer(self.remote.push, source, prefix + source.name, 'operation-host-payload')
            self.channel.transfer(self.remote.push, marker, prefix + marker.name, 'operation-host-marker')
            self.live()
            t.save(folder / 'result.json', t.encode(dict(state='HOST_PROOF_PUBLISHED', payloadSHA256=digest,
                proofSHA256=result['proofSHA256'], deadline=self.channel.deadline, finishedAt=time.time(),
                sdkAdmitted=False, teardownAuthorized=False)))
            if bridge is not None:
                bridge.host_published(digest)
            return digest
        except Exception as error:
            if getattr(self, 'display_bridge', None) is not None:
                self.display_bridge.invalidate(error)
            t.save(folder / 'failure.json', t.encode(dict(state='INVALID', errorType=type(error).__name__,
                deadline=self.channel.deadline, finishedAt=time.time(), sdkAdmitted=False, teardownAuthorized=False)))
            raise
