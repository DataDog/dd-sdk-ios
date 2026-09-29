"""Physical H06 media IO. Raw command observations precede every interpretation.

This adapter has no app launch, input, SDK or teardown authority. The recorder is
one owned host process group; decoded anchors, not process liveness, prove capture.
"""
import math
import os
from pathlib import Path
import signal
import struct
import subprocess
import time
import threading
from urllib.parse import unquote, urlparse

import operation_cleanup as cleanup
import operation_display as pixels
import operation_setup as setup
import operation_transport as t


class ExecutionDevice:
    """Reserve cleanup time without changing the native channel's frozen cutoff."""
    def __init__(self, remote, *, execution_until, deadline):
        t.require(setup.finite(execution_until) and setup.finite(deadline)
                  and time.time() < execution_until < deadline, 'missing cleanup reserve')
        self.remote = remote
        self.execution_until, self.deadline = execution_until, deadline
        self.cleanup_started = False
        self.identity = (remote.identifier, Path(remote.output), execution_until, deadline)

    @property
    def identifier(self): return self.remote.identifier
    @property
    def output(self): return self.remote.output
    @property
    def sequence(self): return self.remote.sequence
    @property
    def groups(self): return self.remote.groups

    def limit(self, deadline):
        t.require((self.identifier, Path(self.output), self.execution_until, self.deadline) == self.identity
                  and deadline == self.deadline, 'device identity or frozen cutoff changed')
        cutoff = self.deadline if self.cleanup_started else self.execution_until
        t.require(time.time() < cutoff, 'device phase cutoff expired')
        return cutoff

    def begin_cleanup(self):
        t.require(not self.cleanup_started, 'cleanup device phase already consumed')
        self.cleanup_started = True
        self.limit(self.deadline)

    def command(self, args, label, deadline, **kwargs):
        return self.remote.command(args, label, self.limit(deadline), **kwargs)

    def pull(self, bundle, source, destination, label, deadline, **kwargs):
        return self.remote.pull(bundle, source, destination, label, self.limit(deadline), **kwargs)

    def push(self, bundle, source, destination, label, deadline):
        return self.remote.push(bundle, source, destination, label, self.limit(deadline))

    def quiescent(self, deadline):
        t.require(self.cleanup_started, 'host quiescence belongs to cleanup')
        return self.remote.quiescent(self.limit(deadline))


def group_members(group, deadline):
    t.require(time.time() < deadline, 'host process inventory cutoff expired')
    result = subprocess.run(['/bin/ps', '-axo', 'pid=,pgid='], capture_output=True,
        text=True, check=True, start_new_session=True, timeout=min(5, deadline-time.time()))
    rows = [line.split() for line in result.stdout.splitlines()]
    return sorted(int(pid) for pid, pgid in rows if int(pgid) == group)


def command_identity(value, expected):
    """CoreDevice returns its own argv; permit only its optional command prefix."""
    info = value.get('info', {})
    actual = info.get('arguments')
    t.require(isinstance(actual, list), 'missing actual CoreDevice arguments')
    actual = list(actual)
    if actual and actual[0] == 'devicectl': actual.pop(0)
    t.require(info.get('commandType') == 'devicectl.device.capture.screen-record'
              and info.get('outcome') == 'success' and actual == expected,
              'recording command differs or failed')


class Movie:
    """One recording, one stop; failed capture may still have successful reaping."""
    def __init__(self, remote, folder, *, record_until, stop_until, environment):
        self.remote, self.folder = remote, Path(folder)
        self.record_until, self.stop_until = record_until, stop_until
        t.require(setup.finite(record_until) and setup.finite(stop_until)
                  and time.time()+3 < record_until < stop_until <= remote.execution_until,
                  'recording lacks reserved finalization time')
        self.folder.mkdir()
        self.destination = self.folder/'screen.mp4'
        self.response = self.folder/'response.json'
        self.process = None; self.used = False; self.reaped = False; self.expired = False
        self.watchdog = None
        self.environment = dict(environment)
        self.definition = dict(device=remote.identifier, recordUntil=record_until, stopUntil=stop_until,
            executionUntil=remote.execution_until, channelDeadline=remote.deadline,
            destination=str(self.destination), nativeAcceptance=False)
        self.definition_raw = t.encode(self.definition)
        t.save(self.folder/'definition.json', self.definition_raw)

    def start(self):
        t.require(self.process is None and not self.used, 'recording already started or consumed')
        self.used = True
        t.require(time.time()+2 < self.record_until and not self.remote.cleanup_started,
                  'recording cutoff expired or cleanup started')
        self.args = ['device', 'capture', 'screen-record', '--device', self.remote.identifier,
            '--destination', str(self.destination), '--codec', 'h264',
            '--duration', str(math.floor(self.record_until-time.time())),
            '--timeout', str(math.floor(self.stop_until-time.time())), '--json-output', str(self.response)]
        self.argv = ['xcrun', 'devicectl', *self.args]
        t.save(self.folder/'admission.json', t.encode(dict(argv=self.argv, at=time.time(),
            definitionSHA256=t.sha(self.definition_raw), nativeAcceptance=False)))
        with (self.folder/'console.log').open('xb') as stream:
            self.process = subprocess.Popen(self.argv, stdout=stream, stderr=subprocess.STDOUT,
                env=self.environment, start_new_session=True)
        # Register even if the next publication fails: cleanup owns this child.
        self.remote.groups.append(self.process.pid)
        self.watchdog = threading.Timer(max(0, self.stop_until-time.time()), self.expire)
        self.watchdog.daemon = True; self.watchdog.start()
        t.save(self.folder/'process-started.json', t.encode(dict(pid=self.process.pid, group=self.process.pid,
            argv=self.argv, startedAt=time.time(), recorderReady=False)))
        self.running()

    def expire(self):
        self.expired = True
        if self.process is not None and self.process.poll() is None:
            try: os.killpg(self.process.pid, signal.SIGKILL)
            except ProcessLookupError: pass

    def running(self):
        t.require(self.process is not None and not self.reaped and self.process.poll() is None,
                  'recorder stopped before FINAL capture')
        t.require(time.time() < self.record_until and not self.remote.cleanup_started
                  and not self.expired and setup.read(self.folder/'definition.json') == self.definition_raw
                  and self.remote.identifier == self.definition['device'], 'recording binding changed or expired')

    def finish(self, *, accept):
        t.require(self.process is not None and not self.reaped
                  and not (self.folder/'process-finished.json').exists(), 'recorder stop already consumed')
        started = time.time(); original_returncode = self.process.poll()
        signals = []; failure = None; forced = False; remaining = None
        try:
            t.require(started < self.stop_until, 'original recorder stop cutoff expired')
            if original_returncode is None:
                try: os.killpg(self.process.pid, signal.SIGINT); signals.append('SIGINT')
                except ProcessLookupError: pass
                # Preserve two seconds of the original cutoff for a failed stop.
                try: self.process.wait(timeout=max(.001, self.stop_until-time.time()-2))
                except subprocess.TimeoutExpired: forced = True
            if self.process.poll() is None:
                os.killpg(self.process.pid, signal.SIGKILL); signals.append('SIGKILL')
                self.process.wait(timeout=max(.001, self.stop_until-time.time()))
            remaining = group_members(self.process.pid, self.stop_until)
            if remaining:
                forced = True
                os.killpg(self.process.pid, signal.SIGKILL); signals.append('SIGKILL')
                remaining = group_members(self.process.pid, self.stop_until)
            self.reaped = self.process.poll() is not None and remaining == []
            if self.reaped and self.watchdog is not None: self.watchdog.cancel()
        except BaseException as error:
            failure = dict(errorType=type(error).__name__, reason=str(error))
        observed = dict(pid=self.process.pid, group=self.process.pid, argv=self.argv,
            startedAt=started, finishedAt=time.time(), deadline=self.stop_until,
            originalReturncode=original_returncode, returncode=self.process.poll(), signals=signals,
            forced=forced, expired=self.expired, remaining=remaining, reaped=self.reaped, failure=failure,
            responseSHA256=setup.file_sha(self.response) if self.response.is_file() else None,
            mediaSHA256=setup.file_sha(self.destination) if self.destination.is_file() else None,
            captureAccepted=False)
        t.save(self.folder/'process-finished.json', t.encode(observed))
        t.require(self.reaped and time.time() < self.stop_until, 'recorder quiescence unproved')
        if not accept: return observed
        t.require(failure is None and not forced and not self.expired and original_returncode is None
                  and self.process.returncode == 0, 'recording failed or stopped before FINAL')
        raw = setup.read(self.response); command_identity(t.load(raw), self.args)
        t.require(self.destination.is_file() and not self.destination.is_symlink()
                  and 0 < self.destination.stat().st_size <= pixels.MAX_BYTES, 'recording output absent or oversized')
        t.save(self.folder/'result.json', t.encode(dict(state='RECORDING_FINALIZED',
            process=pixels.reference(self.folder/'process-finished.json'), response=pixels.reference(self.response),
            media=pixels.reference(self.destination), nativeAcceptance=False)))
        return self.destination


class Media:
    """Original native observations plus exact START/RUN/FINAL image decodes."""
    def __init__(self, host, folder, *, binary, source_sha256, binary_sha256, nonce, movie, wait=lambda:time.sleep(.25)):
        self.host, self.channel = host, host.channel
        self.remote, self.folder = host.remote, Path(folder)
        t.require(isinstance(self.remote, ExecutionDevice), 'execution cutoff adapter required')
        self.folder.mkdir()
        self.observed = cleanup.ObservedDevice(self.remote, self.folder, self.channel.deadline, time.time())
        self.binary, self.source_sha256, self.binary_sha256 = Path(binary), source_sha256, binary_sha256
        self.nonce, self.movie, self.wait = nonce, movie, wait
        self.sequence = 0; self.bindings = {}; self.start_raw = None; self.start_image = None
        self.deadline = self.remote.execution_until
        self.prefix = 'Documents/'+host.identity['runID']+'.operations-'

    def live(self):
        t.require(not self.remote.cleanup_started and time.time() < self.deadline, 'capture phase ended')
        self.host.live()

    def pull(self, name, *, required=True):
        self.live(); self.sequence += 1
        label = f'display-pull-{self.sequence:05d}'
        target = self.folder/(label+'.json')
        if self.channel.transfer(self.observed.pull, self.prefix+name, target, label, optional=True):
            return setup.read(target)
        t.require(not required, 'required native artifact missing: '+name)
        return None

    def poll(self, name):
        for _ in range(100_000):
            self.live()
            if self.pull('native-admission-failure.json', required=False) is not None:
                raise ValueError('native admission failed while waiting for display')
            raw = self.pull(name, required=False)
            if raw is not None: return raw
            self.wait()
        raise ValueError('native display poll bound exhausted')

    def start_barrier(self):
        t.require(self.start_raw is None, 'START barrier already consumed')
        self.start_raw = self.poll('display-START.json')
        self.bindings = {scene:self.pull('display-binding-'+scene+'.json') for scene in pixels.SCENES}
        self.binding = pixels.identity(self.host.identity['runID'], self.nonce,
            {scene:t.sha(raw) for scene,raw in self.bindings.items()})
        value = t.load(self.start_raw)
        t.require(value['identity'] == self.host.identity and value['phase'] == 'START'
                  and value['nonce'] == self.nonce and value['bindingSHA256'] == self.binding['owners']
                  and value['bindings'] == {s:t.load(raw) for s,raw in self.bindings.items()},
                  'START belongs to different native owners')

    def decode(self, source, phase, kind='IMAGE'):
        self.live()
        result = pixels.decode(self.binary, self.binary_sha256, kind, source,
            self.folder/('decoded-'+phase), min(1800, self.deadline-time.time()), source_sha256=self.source_sha256)
        self.live(); return result

    def review_start(self, request, deadline):
        self.live(); self.movie.running()
        t.require(self.start_raw is not None and self.start_image is None and deadline == self.channel.deadline
                  and request['screenshot'] == str(self.host.folder/'screen.png')
                  and request['screenshotSHA256'] == setup.file_sha(self.host.folder/'screen.png'),
                  'START review does not refer to collected screenshot')
        for scene, owner in request['owners'].items():
            t.require(t.load(self.bindings[scene]) == dict(logicalSceneID=scene, **owner), 'START native owner changed')
        self.start_image = self.decode(self.host.folder/'screen.png', 'START')
        frames = pixels.checked(self.start_image, 'IMAGE'); frame = frames[0]
        t.require(pixels.inventory(frame, self.binding) == ('START', 'START'), 'START pixels absent')
        visible = {}
        for scene, owner in request['owners'].items():
            rows = [r for r in frame['observations'] if r['payload'] == pixels.marker(self.binding, scene)]
            t.require(len(rows) == 1, 'owned START marker absent')
            rect = rows[0].get('enclosingPixels')
            t.require(isinstance(rect, list) and len(rect) == 4 and all(setup.finite(v) and v == math.floor(v) for v in rect),
                      'decoder integer owner bounds missing')
            visible[scene] = dict(owner, visibleRegion=[int(v) for v in rect])
        self.live(); self.movie.running()
        return t.encode(dict(requestSHA256=t.sha(t.encode(request)), decision='both-fixture-window-contents-visible',
            reviewer='source-bound-display-decoder', reviewedAt=time.time(), visibleOwners=visible))

    def screenshot(self, phase):
        self.live(); self.movie.running()
        path = self.folder/(phase+'.png')
        raw, _ = self.observed.command(['device','capture','screenshot','--destination',str(path)], 'display-'+phase)
        data = setup.read(path, 32*1024*1024); result = raw['result']
        t.require(len(data) >= 33 and data[:8] == b'\x89PNG\r\n\x1a\n' and data[12:16] == b'IHDR', 'invalid captured PNG')
        size = list(struct.unpack('>II', data[16:24]))
        t.require(size == [result['width'],result['height']] and result['imageFormat'] == 'png'
                  and result['deviceIdentifier'] == self.remote.identifier
                  and Path(unquote(urlparse(result['destination']).path)) == path,
                  'screenshot result differs from actual file')
        self.movie.running(); return self.decode(path, phase)
