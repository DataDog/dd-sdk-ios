"""One H06 capture session after separately admitted physical startup.

No build, installation or launch is performed here. This composes the reviewed
components; a complete summary still needs source/physical qualification and review.
"""
import ctypes
from pathlib import Path
import re
import shlex
import time
import urllib.request

import operation_backend as backend
import operation_cleanup as cleanup
import operation_completion as completion
import operation_display as pixels
import operation_display_proof as display
import operation_media as media
import operation_operator as operator_contract
import operation_recorder as recorder_contract
import operation_setup as setup
import operation_transport as t


def operator_health(operator, folder):
    """Bind the actual local page response and its host process, without a new expiry."""
    operator.live(); folder = Path(folder); folder.mkdir()
    server = t.load(operator.server_raw)
    url = server['url']+'/health'
    started = time.time()
    with urllib.request.urlopen(url, timeout=min(2, operator.deadline-started)) as response:
        raw = response.read(t.MAX_BYTES+1)
        observed = dict(url=response.url, status=response.status, startedAt=started, finishedAt=time.time())
    t.save(folder/'response.json', raw); t.save(folder/'http.json', t.encode(observed))
    t.require(observed['url'] == url and observed['status'] == 200 and t.load(raw) == server,
              'live operator response differs from bound page')
    pid = server['pid']
    command = setup.command(['/bin/ps','-p',str(pid),'-o','pid=,lstart=,comm='], folder, 'process', operator.deadline)
    match = re.fullmatch(r'\s*'+str(pid)+r'\s+(.+?)\s+(/[^\n]+)\n?', command['stdout'])
    t.require(match is not None, 'operator process unavailable')
    query = ctypes.CDLL('/usr/lib/libproc.dylib').proc_pidpath
    query.argtypes = [ctypes.c_int,ctypes.c_void_p,ctypes.c_uint32]; query.restype = ctypes.c_int
    buffer = ctypes.create_string_buffer(4096); size = query(pid,buffer,len(buffer))
    t.require(0 < size < len(buffer), 'operator kernel executable missing')
    executable = Path(buffer.value.decode()).resolve()
    t.require(executable == Path(match[2]).resolve(), 'operator process executable differs')
    argv = setup.command(['/bin/ps','-p',str(pid),'-o','command='], folder, 'arguments', operator.deadline)
    arguments = shlex.split(argv['stdout'].strip())
    script = Path(operator_contract.page.__file__).resolve()
    t.require(str(script) in arguments and arguments.count('--directory') == 1
              and arguments[arguments.index('--directory')+1] == str(operator.directory), 'foreign operator process arguments')
    result = dict(pid=pid, start=match[1], executable=pixels.reference(executable), script=pixels.reference(script),
        serverSHA256=t.sha(operator.server_raw), responseSHA256=t.sha(raw))
    t.save(folder/'result.json',t.encode(result)); operator.live(); return result


def cleanup_expectations(host, folder):
    """Capture actual prior results, including absence; never guess after a failure."""
    folder = Path(folder); folder.mkdir()
    observed = cleanup.ObservedDevice(host.remote, folder, host.channel.deadline, time.time())
    channel = t.Channel(observed, host.channel.bundle, folder/'channel', host.identity, deadline=host.channel.deadline)
    prefix = 'Documents/'+host.identity['runID']+'.operations-'
    def pull(source, name):
        target = folder/name
        if channel.transfer(observed.pull, source, target, 'expectation-'+name, optional=True):
            return setup.read(target, recorder_contract.MAX_BYTES)
        return None
    native = pull(prefix+completion.TERMINAL,'native.json')
    if native is not None:
        value = t.load(native,maximum=t.MAX_CONTEXT_BYTES)
        t.require(value['identity'] == host.identity and value['deadline'] == host.channel.deadline,
                  'foreign native terminal before cleanup')
    raw = pull(recorder_contract.SOURCE,'recorder.jsonl'); terminal = None
    if raw is not None:
        lines = raw[:raw.rfind(b'\n')+1].splitlines()
        t.require(lines, 'recorder has no complete manifest before cleanup')
        rows = [t.load(line,maximum=t.MAX_CONTEXT_BYTES) for line in lines]
        t.require(rows[0]['type'] == 'manifest' and rows[0]['manifest']['runID'] == host.identity['runID']
                  and rows[0]['manifest']['scenario']['identifier'] == host.identity['setupProfile']['scenario'],
                  'foreign cleanup recorder')
        terminals = [row for row in rows if row['type'] == 'semantic-result']
        t.require(len(terminals) <= 1, 'ambiguous original semantic terminal')
        if terminals:
            row = terminals[0]; terminal = row['result']
            t.require(row['runID'] == host.identity['runID']
                      and terminal['scenarioID'] == host.identity['setupProfile']['scenario'], 'foreign original terminal')
    t.save(folder/'result.json',t.encode(dict(nativeSHA256=t.sha(native) if native is not None else None,
        terminal=terminal, recorderSHA256=t.sha(raw) if raw is not None else None, teardownAuthorized=False)))
    return native, terminal


def display_join(recorder, bridge):
    """The native consumer must have consumed the exact host display messages."""
    local = recorder.local; prefix = local.identity['runID']+'.operations-'
    documents = local.folder/'documents'
    joined = completion.validate_snapshot(documents, setup.read(documents/(prefix+completion.TERMINAL)),
        identity=local.identity, publication=local.publication, deadline=local.channel.deadline)
    for phase in pixels.PHASES:
        t.require(setup.read(documents/(prefix+'display-'+phase+'.json')) == bridge.receipts[phase]
                  and setup.read(documents/(prefix+'display-'+phase.lower()+'-proof-consumed.json')) == bridge.proofs[phase],
                  'native display consumer differs from host observation')
    t.require(setup.read(documents/(prefix+'native-final-observation.json'))
              == setup.read(bridge.folder/'collection-seal.json'), 'native collection seal differs from FINAL proof')
    t.require(bridge.state == 'FINAL_PUBLISHED', 'FINAL proof not published')
    pixels.assess(bridge.movie, bridge.anchors, bridge.binding, bridge.folder/'joined-assessment.json')
    return dict(state='DISPLAY_NATIVE_JOINED', terminalSHA256=setup.file_sha(documents/(prefix+completion.TERMINAL)),
        assessment=pixels.reference(bridge.folder/'joined-assessment.json'), nativeAcceptance=False)


class Session:
    """One setup/capture, one cleanup, then saved-source backend collection."""
    def __init__(self, host, operator, capture, *, backend_deadline, maximum_attempts,
                 poll_seconds, notify=backend.notify_request, wait=lambda:time.sleep(.25)):
        self.host, self.operator, self.capture = host, operator, capture
        self.remote, self.movie = host.remote, capture.movie
        t.require(isinstance(self.remote, media.ExecutionDevice) and host.channel.remote is self.remote
                  and operator.channel is host.channel and capture.host is host and self.movie.remote is self.remote,
                  'session components do not share the original channel')
        t.require(setup.finite(backend_deadline) and self.remote.execution_until < backend_deadline <= host.channel.deadline
                  and host.channel.deadline == self.remote.deadline, 'backend or native deadline differs')
        self.backend_deadline, self.maximum_attempts, self.poll_seconds = backend_deadline, maximum_attempts, poll_seconds
        t.require(type(maximum_attempts) is int and 1 <= maximum_attempts <= 24
                  and setup.finite(poll_seconds) and 0 < poll_seconds <= 60, 'unbounded backend policy')
        self.folder = host.channel.output/'session'; self.folder.mkdir()
        self.wait, self.notify, self.used = wait, notify, False
        self.bridge = self.recorder = None
        self.verdicts = dict(scenario='UNRUN', display='UNQUALIFIED', backend='UNRUN', cleanup='UNRUN')
        self.definition = dict(identity=host.identity, device=self.remote.identifier, bundle=host.channel.bundle,
            executionUntil=self.remote.execution_until, deadline=host.channel.deadline,
            backendDeadline=backend_deadline, maximumAttempts=maximum_attempts, pollSeconds=poll_seconds,
            sources={str(p):setup.file_sha(p) for p in sorted(Path(__file__).parent.glob('operation_*.py'))},
            nativeQualification='SEPARATE', releaseAcceptance=False)
        self.definition_raw = t.encode(self.definition); t.save(self.folder/'definition.json', self.definition_raw)
        # Exercise output publication before any SDK admission, not after a gesture.
        preflight = self.folder/'backend-preflight'; preflight.mkdir(); backend.transport.preflight(preflight)

    def execution_live(self):
        self.capture.live()
        t.require(time.time() < self.remote.execution_until and not self.remote.cleanup_started
                  and setup.read(self.folder/'definition.json') == self.definition_raw
                  and all(setup.file_sha(path) == digest for path,digest in self.definition['sources'].items()),
                  'session source, definition or execution phase changed')

    def acknowledgement(self, path, *, cutoff):
        self.operator.present(path)
        while time.time() < cutoff:
            raw = self.operator.acknowledgement()
            if raw is not None: return raw
            self.wait()
        raise ValueError('original acknowledgement phase cutoff expired')

    def failure(self, phase, error):
        path = self.folder/(phase+'-failure.json')
        t.save(path,t.encode(dict(state='INVALID', phase=phase, errorType=type(error).__name__, reason=str(error),
            at=time.time(), verdicts=dict(self.verdicts), sdkRegression=False, releaseAcceptance=False)))

    def run(self):
        t.require(not self.used, 'session already consumed'); self.used = True
        try:
            self.execution_live()
            self.page = operator_health(self.operator, self.folder/'page-before')
            # Native begin() installs the START markers while the driver waits at
            # step4. A later replacement screenshot cannot repair this barrier.
            self.capture.start_barrier()
            ack = self.acknowledgement(self.host.folder/'release-request.json', cutoff=self.remote.execution_until)
            self.movie.start()
            self.host.collect(ack, self.capture.review_start)
            self.execution_live()
            self.bridge = display.DisplayProofBridge(self.host, nonce=self.capture.nonce,
                source_sha256=self.capture.source_sha256, binary_sha256=self.capture.binary_sha256)
            self.bridge.start(self.capture.start_raw,self.capture.bindings,self.capture.start_image)
            run = self.capture.poll('display-RUN.json')
            self.bridge.run(run,self.capture.screenshot('RUN'))
            self.movie.running(); self.execution_live()
            self.host.publish(); self.verdicts['scenario'] = 'PENDING'
            final = self.capture.poll('display-FINAL.json')
            seal = self.capture.pull('native-final-observation.json')
            image = self.capture.screenshot('FINAL')
            movie = self.movie.finish(accept=True)
            decoded = self.capture.decode(movie,'MOVIE','MOVIE')
            self.bridge.final(final,seal,image,decoded)
            self.recorder = recorder_contract.Recorder(completion.Completion(self.host,wait=self.wait))
            self.recorder.collect()  # This is the sole Completion.collect call.
            self.execution_live()
            result = display_join(self.recorder,self.bridge)
            t.save(self.folder/'display-result.json',t.encode(result))
            self.verdicts.update(scenario='PASS',display='PASS')
        except BaseException as error:
            self.verdicts['scenario'] = 'INVALID'
            self.failure('capture',error)
        finally:
            if self.movie.process is not None and not self.movie.reaped:
                try: self.movie.finish(accept=False)
                except BaseException as error: self.failure('recorder-stop',error)
        # Capture failure never becomes a successful scenario after restoration.
        try:
            self.remote.begin_cleanup()
            t.require(self.movie.process is None or self.movie.reaped, 'recorder is not quiescent')
            t.require((self.host.folder/'process-before-response.json').is_file(),
                      'setup never established the original process; app left untouched')
            native, terminal = cleanup_expectations(self.host,self.folder/'cleanup-expectations')
            cleaner = cleanup.Cleanup(self.host,original_native_raw=native,original_terminal=terminal,wait=self.wait)
            page = operator_health(self.operator,self.folder/'page-cleanup')
            t.require(page == self.page, 'operator process changed before cleanup')
            ack = self.acknowledgement(cleaner.folder/'release-request.json',cutoff=self.host.channel.deadline)
            result = cleaner.run(ack)
            t.require(result['state'] == 'TASK_APP_REMOVED', 'task removal incomplete')
            t.save(self.folder/'cleanup-result.json',t.encode(result)); self.verdicts['cleanup'] = 'PASS'
        except BaseException as error:
            self.verdicts['cleanup'] = 'BLOCKED'
            self.failure('cleanup',error)
        # Backend reads no native state and never delays the release/idle request.
        if self.verdicts['scenario'] == self.verdicts['display'] == 'PASS':
            try:
                collected = backend.Backend(self.recorder,deadline=self.backend_deadline,
                    maximum_attempts=self.maximum_attempts,poll_seconds=self.poll_seconds,notify=self.notify)
                result = collected.collect()
                t.save(self.folder/'backend-result.json',t.encode(result)); self.verdicts['backend'] = 'PASS'
            except BaseException as error:
                self.verdicts['backend'] = 'INVALID'; self.failure('backend',error)
        result = dict(state='EVIDENCE_COMPLETE' if all(v == 'PASS' for v in self.verdicts.values()) else 'INVALID',
            verdicts=self.verdicts, identity=self.host.identity, finishedAt=time.time(),
            deadline=self.host.channel.deadline, definitionSHA256=t.sha(self.definition_raw),
            releaseAcceptance=False, gatesClosed=[], sdkRegression=False)
        t.save(self.folder/'result.json',t.encode(result))
        return result
