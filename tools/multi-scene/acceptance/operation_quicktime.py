"""QuickTime receipt preparation, not UI automation or H06 native admission.

The caller uses supported computer control and supplies its actual full AX return.
Source checkmarks require inspection of the image returned by that same tool call;
they are not exposed by AX. That interpretation remains explicit, not pixel proof.
"""
import contextlib
import math
import os
from pathlib import Path
import re
import subprocess
import time
from urllib.parse import unquote, urlsplit
import uuid

import operation_display as display
import operation_transport as t

APP = 'com.apple.QuickTimePlayerX'
PHASES = ('SOURCE', 'START', 'CHECK', 'STOP', 'SAVE', 'RESTORE')
REPLY_KEYS = {'request_sha256', 'observation_id', 'tool_call_id', 'observed_at', 'app', 'inspection'}


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def clean(path):
    path = Path(path)
    t.require(path.is_absolute() and path == path.resolve()
              and not any(p.is_symlink() for p in [path, *path.parents]), 'noncanonical or symlinked path')
    return path


def publish(path, raw):
    """Complete bytes become visible atomically and never replace an old receipt."""
    path = clean(path)
    temporary = path.with_name('.' + path.name + '-' + str(uuid.uuid4()))
    try:
        t.save(temporary, raw)
        os.link(temporary, path)
        descriptor = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    finally:
        temporary.unlink(missing_ok=True)


def inspect_process(pid, timeout):
    result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'pid=,lstart=,comm='],
                            capture_output=True, timeout=timeout, env={**os.environ, 'LC_ALL': 'C'})
    return t.encode(dict(returncode=result.returncode, stdout=result.stdout.decode(), stderr=result.stderr.decode()))


def process(raw, pid):
    value = t.load(raw)
    t.require(set(value) == {'returncode', 'stdout', 'stderr'} and type(value['returncode']) is int
              and value['returncode'] == 0 and value['stderr'] == '', 'QuickTime process unavailable')
    match = re.fullmatch(r'\s*(\d+)\s+(.{24})\s+([^\n]+)\n?', value['stdout'])
    t.require(match is not None and int(match[1]) == pid
              and match[3].endswith('/QuickTime Player.app/Contents/MacOS/QuickTime Player'),
              'foreign QuickTime process')
    return dict(pid=pid, started=match[2], executable=match[3])


def inspect_devices(folder, developer, deadline):
    """Read current connection state; no launch, input or capture command."""
    destination = clean(folder / 'devices.json')
    budget = min(30, deadline - time.time())
    t.require(budget > 0 and not destination.exists(), 'device read late or output reused')
    argv = ['/usr/bin/xcrun', 'devicectl', 'list', 'devices', '--timeout', str(max(1, int(budget))),
            '--json-output', str(destination)]
    publish(folder / 'device-request.json', t.encode(dict(argv=argv, developer=developer, deadline=deadline)))
    try:
        result = subprocess.run(argv, capture_output=True, timeout=budget,
                                env={**os.environ, 'DEVELOPER_DIR': developer})
        receipt = dict(returncode=result.returncode, stdout=result.stdout.decode(errors='replace'),
                       stderr=result.stderr.decode(errors='replace'), at=time.time())
    except (OSError, subprocess.TimeoutExpired) as error:
        receipt = dict(returncode=None, error=str(error), at=time.time())
    publish(folder / 'device-process.json', t.encode(receipt))
    t.require(receipt['returncode'] == 0 and time.time() < deadline, 'device inventory failed or late')
    raw = display.read(destination, t.MAX_CONTEXT_BYTES)
    info = t.load(raw, maximum=t.MAX_CONTEXT_BYTES)['info']
    t.require(info.get('commandType') == 'devicectl.list.devices' and info.get('outcome') == 'success'
              and info.get('arguments') == argv[1:], 'foreign device inventory command')
    return raw


def full_ax(raw):
    t.require(isinstance(raw, bytes) and len(raw) <= t.MAX_CONTEXT_BYTES, 'invalid AX bytes')
    ax = raw.decode('utf-8')
    t.require(re.match(r'^Window: "[^\n]+", App: QuickTime Player\.\n', ax),
              'full actual QuickTime AX required; diffs are not receipts')
    windows = re.findall(r'^\s*\d+ standard window ([^\n]+)$', ax, re.M)
    t.require(len(windows) == 1, 'ambiguous focused recorder window')
    return ax, windows[0]


def device_from_inventory(raw, identifier):
    value = t.load(raw, maximum=t.MAX_CONTEXT_BYTES)
    rows = value['result']['devices']
    selected = [row for row in rows if row.get('identifier') == identifier]
    t.require(len(selected) == 1, 'device absent or ambiguous')
    row = selected[0]; props = row['properties']
    name = props['state']['name']
    t.require(props['hardware']['reality'] == 'physical' and props['hardware']['deviceType'] == 'iPad'
              and props['state']['bootState'] == 'booted' and props['connection']['state'] == 'connected'
              and props['connection']['transportType'] == 'wired'
              and sum(r.get('properties', {}).get('state', {}).get('name') == name for r in rows) == 1,
              'iPad connection or unique source name unqualified')
    return dict(identifier=identifier, udid=props['hardware']['udid'], name=name)


class Recorder:
    """One non-resumable receipt chain. No app launch, process ownership or teardown.

    Original absolute cutoffs bound transport/decoding, not gesture performance.
    Failures are sticky; restoration has its own receipt and cannot repair capture.
    Focused AX titles/URLs are not stable native window IDs or continuous source
    proof. CUA does not expose those IDs on macOS. Device rereads catch observed
    disconnections; source-bound START/RUN/FINAL joins remain required separately.
    """
    def __init__(self, output, *, run_id, device, inventory, pid, decoder, decoder_source_sha256,
                 record_deadline, evidence_deadline, restore_deadline, original_audio,
                 developer_directory, initial_ax, initial_tool_call_id):
        self.output = clean(output)
        t.require(t.identifier(run_id) and type(pid) is int and pid > 0, 'invalid run/process identity')
        limits = [record_deadline, evidence_deadline, restore_deadline]
        t.require(all(finite(v) for v in limits) and time.time() < limits[0] < limits[1] < limits[2],
                  'invalid or expired original cutoffs')
        t.require(set(original_audio) == {'kind', 'name'} and original_audio['kind'] in ('Microphone', 'Speaker')
                  and isinstance(original_audio['name'], str) and original_audio['name'], 'original audio absent')
        clean(inventory['path']); clean(decoder['path'])
        native = device_from_inventory(display.verified_ref(inventory, t.MAX_CONTEXT_BYTES), device)
        display.verified_ref(decoder)
        t.require(display.sha(Path(display.__file__).with_suffix('.swift')) == decoder_source_sha256,
                  'decoder source differs')
        developer = clean(developer_directory)
        t.require(developer.is_dir(), 'developer directory absent')
        ax, window = full_ax(initial_ax)
        t.require(window.startswith('Movie Recording,') and 'button stop recording' not in ax
                  and isinstance(initial_tool_call_id, str) and initial_tool_call_id.strip(),
                  'initial observation is not an idle QuickTime preview')
        self.output.mkdir()  # Reusing or resuming a directory cannot authorize UI work.
        self.refs = []; self.pending = None; self.phase = None; self.checks = 0
        self.seen_calls = {initial_tool_call_id}; self.seen_observations = set()
        self.failure = None; self.restoration_failure = None
        self.decoded = None; self.restored = None; self.previous = None
        raw = inspect_process(pid, min(10, record_deadline - time.time()))
        self._save(self.output / 'initial-process.json', raw)
        self._save(self.output / 'initial.ax', initial_ax)
        binding = dict(schema_version=1, run_id=run_id, app=APP, device=native,
                       developer_directory=str(developer), initial_tool_call_id=initial_tool_call_id,
                       inventory=inventory, process=process(raw, pid), decoder=decoder,
                       decoder_source_sha256=decoder_source_sha256, original_audio=original_audio,
                       movie=str(self.output / 'capture.mov'), record_deadline=record_deadline,
                       evidence_deadline=evidence_deadline, restore_deadline=restore_deadline,
                       created_at=time.time(), native_acceptance=False)
        self.binding_raw = t.encode(binding)
        self._save(self.output / 'binding.json', self.binding_raw)
        # Exercise no-clobber publication before allowing the first UI request.
        try:
            publish(self.output / 'binding.json', b'preflight must not replace binding')
        except FileExistsError:
            pass
        else:
            raise ValueError('receipt publication permits replacement')
        self._verify()
        t.require(time.time() < record_deadline, 'recorder preparation exceeded original cutoff')

    @property
    def binding(self):
        return t.load(self.binding_raw)  # Callers cannot mutate a shared binding dictionary.

    def _save(self, path, raw):
        publish(path, raw)
        ref = display.reference(path)
        self.refs.append(ref)
        return ref

    def _verify(self, restoration=False):
        clean(self.output)
        if restoration:
            t.require(display.read(self.output / 'binding.json', t.MAX_BYTES) == self.binding_raw,
                      'restoration binding changed')
            return
        for ref in self.refs:
            clean(ref['path']); display.verified_ref(ref)
        binding = self.binding
        clean(binding['decoder']['path']); display.verified_ref(binding['decoder'])
        t.require(display.sha(Path(display.__file__).with_suffix('.swift')) == binding['decoder_source_sha256'],
                  'decoder source changed')

    @contextlib.contextmanager
    def _guard(self, phase):
        try:
            yield
        except Exception as error:
            field = 'restoration_failure' if phase == 'RESTORE' else 'failure'
            if getattr(self, field) is None:
                value = dict(state='INVALID', phase=phase, at=time.time(), error=str(error), native_acceptance=False)
                setattr(self, field, value)
                try:
                    self._save(self.output / (field + '.json'), t.encode(value))
                except Exception:
                    pass  # In-memory failure remains terminal even if storage failed.
            raise

    def _process(self, folder, label, deadline):
        timeout = min(10, deadline - time.time())
        t.require(timeout > 0, 'process inspection cutoff expired')
        raw = inspect_process(self.binding['process']['pid'], timeout)
        self._save(folder / (label + '-process.json'), raw)
        t.require(process(raw, self.binding['process']['pid']) == self.binding['process'],
                  'QuickTime restarted or process identity changed')

    def _device(self, folder, deadline):
        folder.mkdir()
        raw = inspect_devices(folder, self.binding['developer_directory'], deadline)
        self._save(folder / 'observed.json', raw)
        t.require(device_from_inventory(raw, self.binding['device']['identifier']) == self.binding['device'],
                  'iPad identity or connection changed')

    def request(self, phase):
        with self._guard(phase):
            t.require(phase in PHASES, 'unknown recorder phase')
            restoring = phase == 'RESTORE'
            t.require(self.restored is None and self.restoration_failure is None, 'restoration already consumed')
            t.require(restoring or (self.failure is None and self.pending is None and self.decoded is None),
                      'failed, pending or completed capture')
            if not restoring:
                allowed = {None: ('SOURCE',), 'SOURCE': ('START',), 'START': ('CHECK', 'STOP'),
                           'CHECK': ('CHECK', 'STOP'), 'STOP': ('SAVE',), 'SAVE': ()}
                t.require(phase in allowed[self.phase] and (phase != 'CHECK' or self.checks < 16),
                          'reordered or repeated capture phase')
            binding = self.binding
            key = 'restore_deadline' if restoring else 'evidence_deadline' if phase == 'SAVE' else 'record_deadline'
            deadline = binding[key]
            t.require(time.time() < deadline, 'original recorder cutoff expired')
            self._verify(restoration=restoring)
            movie = clean(binding['movie'])
            if phase != 'RESTORE':
                t.require(not movie.exists(), 'reserved movie already exists before save')
            folder = self.output / ('%02d-' % (len(self.seen_observations) + 1) + phase)
            folder.mkdir()
            self._process(folder, 'request', deadline)
            if not restoring:
                self._device(folder / 'request-device', deadline)
            request = dict(schema_version=1, phase=phase, request_id=str(uuid.uuid4()),
                           binding_sha256=t.sha(self.binding_raw), previous_sha256=self.previous,
                           issued_at=time.time(), deadline=deadline)
            raw = t.encode(request)
            ref = self._save(folder / 'request.json', raw)
            self._save(folder / 'publication-preflight.json', t.encode(dict(request_sha256=t.sha(raw))))
            t.require(time.time() < deadline, 'request publication exceeded cutoff')
            if restoring and self.pending is not None:
                t.require(self.failure is not None, 'pending capture must fail before restoration')
            self.pending = (folder, raw)
            return ref

    def fail_pending(self, tool_error_raw):
        """Retain an actual failed UI call when it produced no AX observation."""
        t.require(self.pending is not None, 'no pending recorder request')
        folder, raw = self.pending
        phase = t.load(raw)['phase']
        with self._guard(phase):
            self._save(folder / 'tool-error.raw', tool_error_raw)
            raise ValueError('UI call failed; actual error retained in tool-error.raw')

    def observe(self, ax_raw, reply_raw):
        t.require(self.pending is not None, 'no pending recorder request')
        folder, request_raw = self.pending
        request = t.load(request_raw); phase = request['phase']
        with self._guard(phase):
            # Retain exactly what returned, including malformed/late evidence, before parsing it.
            self._save(folder / 'observation.ax', ax_raw)
            self._save(folder / 'observation.json', reply_raw)
            reply = t.load(reply_raw)
            received = time.time()
            t.require(set(reply) == REPLY_KEYS and reply['request_sha256'] == t.sha(request_raw)
                      and reply['app'] == APP and t.identifier(reply['observation_id'])
                      and isinstance(reply['tool_call_id'], str) and reply['tool_call_id'].strip(),
                      'foreign or malformed recorder observation')
            t.require(reply['tool_call_id'] not in self.seen_calls
                      and reply['observation_id'] not in self.seen_observations, 'replayed recorder observation')
            t.require(finite(reply['observed_at']) and request['issued_at'] <= reply['observed_at'] <= received
                      and received < request['deadline'], 'stale or late recorder observation')
            self._verify(restoration=phase == 'RESTORE'); self._process(folder, 'response', request['deadline'])
            if phase != 'RESTORE':
                self._device(folder / 'response-device', request['deadline'])
            ax, window = full_ax(ax_raw)
            starts = re.findall(r'^\s*\d+ button start recording$', ax, re.M)
            stops = re.findall(r'^\s*\d+ button stop recording$', ax, re.M)
            if phase in ('SOURCE', 'RESTORE'):
                inspection = reply['inspection']; binding = self.binding
                expected_audio = (dict(kind='Speaker', name=binding['device']['name']) if phase == 'SOURCE'
                                  else binding['original_audio'])
                t.require(isinstance(inspection, dict) and set(inspection) ==
                          {'screenshot_call_id', 'screen', 'audio', 'quality', 'inspected_by'}
                          and inspection['screenshot_call_id'] == reply['tool_call_id']
                          and inspection['screen'] == binding['device']['name']
                          and inspection['audio'] == expected_audio and inspection['quality'] == 'High'
                          and isinstance(inspection['inspected_by'], str) and inspection['inspected_by'].strip(),
                          'source requires same-call image inspection of selected screen and audio')
                t.require(binding['device']['name'] in ax and expected_audio['name'] in ax
                          and 'button show capture device selection menu' in ax
                          and 'menu Secondary Actions: Cancel' in ax and not stops
                          and window.startswith('Movie Recording,'), 'source menu or idle preview absent')
                if phase == 'SOURCE':
                    t.require(len(starts) == 1, 'recording source is not ready')
            else:
                t.require(reply['inspection'] is None, 'unexpected source interpretation')
                if phase in ('START', 'CHECK'):
                    t.require(len(stops) == 1 and not starts and window.startswith('Movie Recording,'),
                              'recording did not start or is no longer running')
                else:
                    t.require(not starts and not stops and ', URL: ' in window, 'recording did not stop/save')
                    url = urlsplit(window.rsplit(', URL: ', 1)[1])
                    t.require(url.scheme == 'file' and not url.netloc and not url.query and not url.fragment,
                              'foreign movie URL')
                    path = clean(unquote(url.path))
                    t.require(path.suffix == '.mov', 'stopped document is not a movie')
                    if phase == 'SAVE':
                        t.require(path == Path(self.binding['movie']) and path.is_file()
                                  and 0 < path.stat().st_size <= display.MAX_BYTES, 'saved movie destination differs')
                        self.movie_ref = display.reference(path)
            t.require(time.time() < request['deadline'], 'observation validation exceeded cutoff')
            result = dict(state='OBSERVED', phase=phase, request_sha256=t.sha(request_raw),
                          ax_sha256=t.sha(ax_raw), reply_sha256=t.sha(reply_raw), at=time.time(),
                          native_acceptance=False)
            ref = self._save(folder / 'result.json', t.encode(result))
            t.require(time.time() < request['deadline'], 'observation publication exceeded cutoff')
            self.seen_calls.add(reply['tool_call_id']); self.seen_observations.add(reply['observation_id'])
            self.pending = None
            if phase == 'RESTORE':
                self.restored = ref
            else:
                self.phase = phase; self.previous = ref['sha256']
                self.checks += int(phase == 'CHECK')
            return ref

    def finish(self):
        with self._guard('DECODE'):
            t.require(self.failure is None and self.pending is None and self.phase == 'SAVE'
                      and self.decoded is None, 'capture chain incomplete or already decoded')
            self._verify(); binding = self.binding
            display.verified_ref(self.movie_ref); clean(self.movie_ref['path'])
            timeout = min(1800, binding['evidence_deadline'] - time.time())
            proof = display.decode(binding['decoder']['path'], binding['decoder']['sha256'], 'MOVIE',
                                   self.movie_ref['path'], self.output / 'decode', timeout,
                                   source_sha256=binding['decoder_source_sha256'])
            frames = display.checked(proof, 'MOVIE')
            manifest = t.load(display.verified_ref(proof, t.MAX_BYTES))
            invocation = t.load(display.verified_ref(manifest['invocation'], t.MAX_BYTES))
            t.require(invocation['source'] == self.movie_ref, 'decoder used a different saved movie')
            display.verified_ref(self.movie_ref); self._verify()
            t.require(time.time() < binding['evidence_deadline'], 'decode exceeded original cutoff')
            result = dict(state='CAPTURE_RECEIPTS_CHECKED', movie=self.movie_ref, decoder=proof,
                          frames=len(frames), native_acceptance=False, gates_closed=[], at=time.time())
            ref = self._save(self.output / 'capture.json', t.encode(result))
            t.require(time.time() < binding['evidence_deadline'], 'capture publication exceeded cutoff')
            self.decoded = ref
            return ref

    def summary(self):
        if self.decoded is not None and self.failure is None:
            try:
                with self._guard('VERIFY'):
                    self._verify(); clean(self.movie_ref['path']); display.verified_ref(self.movie_ref)
                    display.checked(t.load(display.verified_ref(self.decoded, t.MAX_BYTES))['decoder'], 'MOVIE')
            except Exception:
                pass
        return dict(capture='INVALID' if self.failure else 'PASS' if self.decoded else 'INCOMPLETE',
                    recorder_restoration='INVALID' if self.restoration_failure else 'PASS' if self.restored else 'INCOMPLETE',
                    capture_receipt=self.decoded, restoration_receipt=self.restored,
                    capture_failure=self.failure, restoration_failure=self.restoration_failure,
                    native_acceptance=False, gates_closed=[])
