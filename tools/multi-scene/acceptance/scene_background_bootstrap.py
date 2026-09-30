"""H10 bootstrap and release-gated cleanup; no launch, display or gate authority.

Reuse H04's actual IO, product, process and idle checks without changing H04.
The caller still owns installation, native input, phase validation and backend.
"""
import ast
from pathlib import Path
import sys
import time
import uuid

import focus_activation_host as base
import focus_activation_transport as control
import operation_setup as setup
import operation_transport as t
import scene_background_capture as capture
import scene_background_cycle as cycle
import scene_background_protocol as phases

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'interactive-transitions'))
import physical_release as release


def sources():
    root = Path(__file__).resolve().parents[1]
    modules = {name: Path(module.__file__).resolve() for name, module in tuple(sys.modules.items())
               if getattr(module, '__file__', None) and not name.startswith('test_')
               and Path(module.__file__).suffix == '.py'
               and Path(module.__file__).resolve().is_relative_to(root)}
    pending = [Path(__file__).resolve()]; result = {}
    while pending:
        path = pending.pop()
        if str(path) in result: continue
        raw = setup.read(path, maximum=capture.MAXIMUM_BYTES); result[str(path)] = t.sha(raw)
        for node in ast.walk(ast.parse(raw)):
            names = [a.name for a in node.names] if isinstance(node, ast.Import) else \
                [node.module] if isinstance(node, ast.ImportFrom) and node.level == 0 else []
            pending.extend(modules[name] for name in names if name in modules)
    return result


def challenge(raw, installed, expected):
    value = t.load(raw); phases.identity(value)
    t.require(t.encode(value) == raw and all(value[k] == expected[v] for k, v in [
        ('runID','run_id'), ('processID','process_id'), ('sourceRevision','revision'),
        ('executionDeadlineMilliseconds','execution_ms'), ('cleanupDeadlineMilliseconds','cleanup_ms')])
        and value['installedCodeSHA256'] == t.sha(installed), 'H10 bootstrap challenge differs')
    code = t.load(installed, maximum=t.MAX_CONTEXT_BYTES)
    t.require(code.get('runID') == expected['run_id'] and type(code.get('processID')) is int
              and code['processID'] == expected['process_id'] and code.get('sourceRevision') == expected['revision']
              and code.get('boundary') == 'before-sdk-initialization', 'H10 installed receipt differs')
    return value


def freshness(raw, expected):
    value = t.load(raw)
    fields = {'schemaVersion','runID','scenarioID','sourceRevision','processID','bundleIdentifier','nonce',
              'boundary','paths','releaseAcceptance'}
    t.require(isinstance(value, dict) and set(value) == fields and type(value['schemaVersion']) is int
              and value['schemaVersion'] == 1 and value['scenarioID'] == cycle.SCENARIO
              and type(value['processID']) is int and all(value[k] == expected[v] for k,v in [
                  ('runID','run_id'),('sourceRevision','revision'),('processID','process_id'),
                  ('bundleIdentifier','bundle'),('nonce','startup_nonce')])
              and str(uuid.UUID(value['nonce'])) == value['nonce']
              and value['boundary'] == 'before-sdk-and-probe-writer' and value['releaseAcceptance'] is False,
              'H10 startup identity or boundary differs')
    paths = value['paths']
    t.require(isinstance(paths, dict) and set(paths) == setup.STARTUP_ABSENT_PATHS|{'Documents'}
              and paths['Documents'] in ['ABSENT','EMPTY']
              and all(paths[p] == 'ABSENT' for p in setup.STARTUP_ABSENT_PATHS), 'stale H10 startup storage')
    return value


def input_owners(snapshot):
    keys = ['logicalSceneID','nativeSceneID','generation','windowIdentity','rootIdentity','observerIdentity']
    return {row['logicalSceneID']: {key: row[key] for key in keys} for row in snapshot['input']}


class BoundObservedDevice(base.ObservedDevice):
    """Retain each returned IO receipt and rejoin its bytes before later effects."""
    def __init__(self, *args):
        super().__init__(*args)
        self.cutoff = self.deadline; self.lower = self.released_at; self.records = {}

    def rejoin(self):
        t.require(self.deadline == self.cutoff and self.released_at == self.lower,
                  'H10 IO cutoff or release boundary changed')
        t.require(all(setup.file_sha(Path(path)) == digest for path,digest in self.records.items()),
                  'H10 actual IO evidence changed')

    def after_release(self, at):
        t.require(not self.records and self.lower <= at < self.cutoff, 'H10 cleanup IO preceded release')
        self.lower = self.released_at = at

    def verify(self, result, receipt, label):
        self.rejoin(); name = f'{self.remote.sequence:05d}-'+label
        source = self.remote.output/name
        raw = setup.read(source/'response.json'); proof = setup.read(source/'receipt.json')
        actual = super().verify(result,receipt,label)
        for kind,data in [('response',raw),('receipt',proof)]:
            original = source/(kind+'.json'); saved = self.folder/(name+'-'+kind+'.json')
            t.require(setup.read(original) == setup.read(saved) == data, 'H10 IO publication changed')
            self.records[str(original)] = self.records[str(saved)] = t.sha(data)
        self.rejoin(); return actual


class Session(base.Session):
    """One bootstrap/ARM and one acknowledged STOP/removal, under original clocks."""
    def __init__(self, *args, expected_sources, **kwargs):
        t.require(expected_sources == LOADED_SOURCES == sources(), 'H10 reviewed helper closure differs')
        self.sources = dict(expected_sources); self.source_raw = t.encode(self.sources)
        self.release_raw = None; self.ack_raw = None; self.critical = None; self.controls = {}
        self.prefix_raw = None; self.termination_attempted = False
        super().__init__(*args, **kwargs)
        for name,observed in self.observed.items():
            self.observed[name] = BoundObservedDevice(self.remote,observed.folder,observed.deadline,self.created)
        t.save(self.output/'sources.json', self.source_raw); self.live('execution')

    def live(self, phase):
        deadline = super().live(phase)
        t.require(t.encode(self.sources) == self.source_raw and sources() == self.sources
                  and setup.read(self.output/'sources.json', maximum=capture.MAXIMUM_BYTES) == self.source_raw,
                  'H10 helper or persisted source closure changed')
        for name,observed in self.observed.items():
            t.require(observed.cutoff == self.expected[name+'_ms']/1000, 'H10 IO original cutoff differs')
            observed.rejoin()
        for operation,(sent,returned,result) in self.controls.items():
            folder = self.output/operation
            t.require(setup.read(folder/'request.json') == sent
                      and setup.read(folder/'marker') == t.sha(sent).encode()
                      and setup.read(folder/'reply.json') == returned and setup.read(folder/'result.json') == result
                      and self.replies.get(operation) == (sent,returned), 'H10 original control bytes changed')
            if operation == 'arm': t.require(self.arm_reply == returned, 'H10 original ARM replaced')
        if self.prefix_raw is not None:
            t.require(self.previous == self.prefix_raw and setup.read(self.output/'recorder-prefix/raw.jsonl',
                      maximum=capture.MAXIMUM_BYTES) == self.prefix_raw, 'H10 retained recorder prefix changed')
        if self.critical is not None:
            issued = t.load(self.critical['raw'])
            t.require(setup.read(self.output/'critical-owners.json') == self.critical['raw']
                      and issued['owners'] == self.critical['owners']
                      and issued['reference'] == self.critical['reference']
                      and issued['directory'] == str(self.critical['directory'])
                      and capture.read_reference(self.critical['directory'], self.critical['reference']) ==
                          self.critical['capture_raw'], 'H10 captured owner binding changed')
            actual = capture.read_capture(self.critical['directory'],self.critical['reference'],self.identity)
            t.require(all(input_owners(actual[key]['snapshot']) == issued['owners'] for key in ['before','after']),
                      'H10 original capture no longer owns its issued input identities')
        return deadline

    def failure(self, folder, error):
        self.failed = True
        if (folder/'result.json').exists(): (folder/'result.json').rename(folder/'invalidated-result.json')
        t.save(folder/'failure.json', t.encode(dict(state='INVALID', reason=str(error),
            error_type=type(error).__name__, at=time.time(), task_termination_attempted=self.termination_attempted,
            scenario='UNCHANGED', evidence='UNCHANGED', releaseAcceptance=False)))

    def bootstrap(self):
        folder = self.folder('bootstrap')
        try:
            self.live('execution'); prefix = 'Documents/'+self.expected['run_id']
            installed = self.download('execution',folder,prefix+'.installed-code.json','installed')
            startup = self.download('execution',folder,prefix+'.startup-freshness.json','startup')
            raw = self.download('execution',folder,prefix+'.background-channel/challenge.json','challenge')
            self.product = base.installed_code.validate(t.load(installed, maximum=t.MAX_CONTEXT_BYTES),self.app,
                self.expected['run_id'],self.expected['revision'],self.expected['process_id'])
            t.require(self.product['bundleIdentifier'] == self.expected['bundle'], 'H10 installed bundle changed')
            freshness(startup,self.expected); self.identity = challenge(raw,installed,self.expected)
            self.process = self.current_process('execution','bootstrap-process')
            for name, data in [('installed.json',installed),('startup.json',startup),('challenge.json',raw)]:
                t.save(folder/name,data)
            value = dict(state='BOUND_PHYSICAL_PROCESS_AND_STORAGE',identity=self.identity,process=self.process,
                product=self.product,artifacts={n:t.sha(data) for n,data in
                    [('installed.json',installed),('startup.json',startup),('challenge.json',raw)]},
                at=time.time(),overall='UNQUALIFIED',
                teardown_authorized=False)
            self.bootstrap_raw = t.encode(value); t.save(folder/'result.json',self.bootstrap_raw)
            self.live('execution'); self.bound('execution')
            return value
        except Exception as error: self.failure(folder,error); raise

    def exchange(self, operation):
        t.require(operation in ['arm','stop'], 'unsupported H10 control operation')
        phase = 'execution' if operation == 'arm' else 'cleanup'; folder = self.folder(operation)
        try:
            self.bound(phase); phases.identity(self.identity)
            if operation == 'arm': t.require(not self.failed and 'stop' not in self.used, 'H10 stopped or failed')
            else: self.released()
            self.current_process(phase,operation+'-process-before')
            sent = control.request(self.identity,operation); digest = t.sha(sent)
            t.save(folder/'request.json',sent); t.save(folder/'marker',digest.encode())
            prefix = 'Documents/'+self.identity['runID']+'.background-channel/'
            self.transfer(phase,folder,folder/'request.json',prefix+digest+'.json',operation+'-payload',download=False)
            self.transfer(phase,folder,folder/'marker',prefix+operation+'.request',operation+'-publish',download=False)
            raw = self.download(phase,folder,prefix+digest+'.reply.json',operation+'-reply')
            t.save(folder/'reply.json',raw); result = control.reply(raw,sent,received_at_ms=int(time.time()*1000))
            self.current_process(phase,operation+'-process-after')
            if operation == 'stop': self.stopped_owners(raw)
            self.live(phase); encoded = t.encode(result); t.save(folder/'result.json',encoded)
            t.require(setup.read(folder/'result.json') == encoded, 'H10 issued control result changed')
            t.require(setup.read(folder/'request.json') == sent and setup.read(folder/'reply.json') == raw
                      and setup.read(folder/'marker') == digest.encode(), 'H10 issued control bytes changed')
            self.replies[operation] = sent,raw
            if operation == 'arm': self.arm_reply = raw
            self.controls[operation] = sent,raw,encoded
            self.bound(phase); self.live(phase)
            return result
        except Exception as error: self.failure(folder,error); raise

    def remember_owners(self, channel):
        """Bind the first actual two-scene inspection; this grants no phase permit."""
        folder = self.folder('critical-owner-binding')
        try: return self._remember_owners(channel)
        except Exception as error: self.failure(folder,error); raise

    def _remember_owners(self, channel):
        self.bound('execution'); channel.live()
        t.require(self.critical is None and self.arm_reply is not None and channel.index == 0
                  and channel.remote is self.remote and channel.bundle == self.expected['bundle']
                  and channel.identity == self.identity and channel.latest is not None,
                  'H10 original inspection context differs')
        directory = Path(channel.evidence); reference = t.load(t.encode(channel.latest))
        capture_raw = capture.read_reference(directory,reference)
        value = capture.read_capture(directory,reference,self.identity)
        t.require(value['terminal'] is None and value['capture']['boundary'] == phases.PHASES[0],
                  'H10 original inspection is terminal or out of phase')
        for witness in [value['before'],value['after']]:
            cycle.capture(dict(kind='assertion',evidenceSource='probe',result='PASS',reason=t.encode(witness).decode()),
                          self.identity['runID'],'before')
            control.idle(witness['snapshot'],'stop')
        owners = input_owners(value['before']['snapshot'])
        t.require(set(owners) == set(cycle.SCENES) and owners == input_owners(value['after']['snapshot']),
                  'H10 initial inspection input owners changed')
        _, arm = control.opaque(t.load(self.arm_reply)['observation']['after'])
        t.require(owners['scene-A'] == input_owners(arm)['scene-A'], 'H10 original A changed during setup')
        raw = t.encode(dict(owners=owners,identity=self.identity,reference=reference,
            directory=str(directory),native_acceptance=False))
        self.critical = dict(raw=raw,owners=owners,directory=directory,reference=reference,capture_raw=capture_raw)
        t.save(self.output/'critical-owners.json',raw)
        channel.live()
        t.require(channel.index == 0 and channel.remote is self.remote and channel.bundle == self.expected['bundle']
                  and channel.identity == self.identity and channel.evidence == directory and channel.latest == reference,
                  'H10 initial inspection descriptor changed during publication')
        self.live('execution')
        return dict(state='BOUND_INITIAL_INPUT_OWNERS_ONLY',native_acceptance=False)

    def stopped_owners(self, raw):
        t.require(self.arm_reply is not None, 'H10 original ARM observation absent')
        _, arm = control.opaque(t.load(self.arm_reply)['observation']['after'])
        _, after = control.opaque(t.load(raw)['observation']['after']); owners = input_owners(after)
        expected = self.critical['owners'] if self.critical is not None else input_owners(arm)
        t.require(all(owners.get(scene) == owner for scene,owner in expected.items()), 'H10 original idle owner changed')

    def collect(self):
        raise ValueError('H10 collection belongs to the reviewed phase channel, not the H04 recorder oracle')

    def retain_recorder(self):
        """Freeze one complete raw prefix; parsing and acceptance remain separate."""
        folder = self.folder('recorder-prefix')
        try:
            self.bound('execution'); t.require(self.arm_reply is not None, 'H10 ARM is required before capture')
            raw = self.download('execution',folder,base.recorder.SOURCE,'recorder',maximum=capture.MAXIMUM_BYTES)
            t.save(folder/'raw.jsonl',raw); self.prefix_raw = self.previous = raw
            self.bound('execution'); return raw
        except Exception as error: self.failure(folder,error); raise

    def request_release(self):
        self.bound('cleanup'); folder = self.folder('release')
        request = dict(kind='HUMAN_RELEASE_REQUIRED',request_id=str(uuid.uuid4()),run_id=self.identity['runID'],
            channel_identity_sha256=t.sha(t.encode(self.identity)),device=self.expected['device'],
            bundle=self.expected['bundle'],issued_at=time.time(),deadline=self.expected['cleanup_ms']/1000,
            instruction='Release all fingers and stop interacting with the iPad. Confirm Released; leave the app open.')
        self.release_raw = t.encode(request); t.save(folder/'request.json',self.release_raw)
        self.live('cleanup'); return folder/'request.json'

    def released(self):
        t.require(self.release_raw is not None, 'H10 actual operator release is required')
        folder = self.output/'release'; raw = setup.read(folder/'request.json')
        t.require(raw == self.release_raw, 'H10 release request changed')
        reply_raw = setup.read(folder/'operator-released.json'); reply = t.load(reply_raw); request = t.load(raw)
        t.require(setup.finite(reply.get('at')) and type(reply.get('at')) in (int,float), 'invalid H10 release time')
        release.validate_ack(request,raw,reply,time.time())
        if self.ack_raw is None:
            self.observed['cleanup'].after_release(reply['at']); self.ack_raw = reply_raw
        t.require(reply_raw == self.ack_raw, 'H10 accepted release acknowledgement changed')
        self.live('cleanup')
        return reply_raw

    def teardown_binding(self,folder,admission,ack,sent,returned,raw,quiet_raw):
        """Rejoin issued evidence before each effect; a terminated PID need not be live."""
        self.bound('cleanup'); t.require(self.released() == ack, 'H10 release evidence changed before teardown')
        t.require(setup.read(folder/'teardown-admission.json') == admission
                  and setup.read(self.output/'stop/request.json') == sent
                  and setup.read(self.output/'stop/reply.json') == returned
                  and setup.read(folder/'final-recorder.jsonl',maximum=capture.MAXIMUM_BYTES) == raw
                  and setup.read(folder/'host-quiescence.json') == quiet_raw, 'H10 teardown evidence changed')
        control.reply(returned,sent,received_at_ms=int(time.time()*1000)); self.stopped_owners(returned)
        self.live('cleanup')

    def cleanup(self):
        folder = self.folder('cleanup')
        try:
            self.bound('cleanup'); ack = self.released()
            self.exchange('stop')
            raw = self.download('cleanup',folder,base.recorder.SOURCE,'final-recorder',maximum=capture.MAXIMUM_BYTES)
            t.save(folder/'final-recorder.jsonl',raw)
            # Complete raw bytes remain available even when the scenario is invalid.
            t.require(raw.startswith(self.previous), 'H10 final recorder was replaced or truncated')
            observed = self.observed['cleanup']; device,_ = observed.command(['device','info','details'],'cleanup-device')
            details = device['result']; hardware = details['hardwareProperties']; properties = details['deviceProperties']
            t.require(hardware.get('reality') == 'physical' and hardware.get('deviceType') == 'iPad'
                      and hardware.get('udid') == self.expected['device_udid']
                      and int(properties['osVersionNumber'].split('.')[0]) >= 27 and properties.get('osBuildUpdate'),
                      'H10 cleanup physical device differs')
            deadline = self.live('cleanup'); self.remote.quiescent(deadline)
            quiet_raw = setup.read(self.remote.output/'before-cleanup-quiescence.json')
            t.save(folder/'host-quiescence.json',quiet_raw); quiet = t.load(quiet_raw)
            t.require(quiet['state'] == 'PASS' and quiet['remaining'] == [] and quiet['groups'] == self.remote.groups
                      and quiet['deadline'] == deadline and self.created <= quiet['at'] < deadline,
                      'H10 host workers are not quiescent')
            self.current_process('cleanup','cleanup-process-final')
            sent,returned = self.replies['stop']
            admission = t.encode(dict(process=self.process,bundle=self.expected['bundle'],at=time.time(),deadline=deadline,
                release_sha256=t.sha(ack),stop_request_sha256=t.sha(sent),stop_reply_sha256=t.sha(returned),
                final_recorder_sha256=t.sha(raw),scenario='UNCHANGED',evidence='UNCHANGED'))
            t.save(folder/'teardown-admission.json',admission)
            binding = folder,admission,ack,sent,returned,raw,quiet_raw
            self.teardown_binding(*binding); self.termination_attempted = True
            removed,_ = observed.command(['device','process','terminate','--pid',str(self.process['processID'])],'cleanup-terminate')
            t.require(removed['result'].get('deviceIdentifier') == self.expected['device'] and
                      removed['result'].get('process') == dict(processIdentifier=self.process['processID'],
                      executable=self.process['executable']), 'H10 termination identity differs')
            self.process_absence('cleanup-process-absence')
            self.teardown_binding(*binding)
            removed,_ = observed.command(['device','uninstall','app',self.expected['bundle']],'cleanup-uninstall')
            t.require(removed['result'].get('deviceIdentifier') == self.expected['device'] and
                      removed['result'].get('uninstalledApplications') == [dict(bundleID=self.expected['bundle'])],
                      'H10 uninstall identity differs')
            apps,_ = observed.command(['device','info','apps','--bundle-id',self.expected['bundle']],'cleanup-app-absence')
            value = apps['result']
            t.require(value.get('deviceIdentifier') == self.expected['device']
                      and value.get('matchingBundleIdentifier') == self.expected['bundle'] and value.get('apps') == [],
                      'H10 task app absence unproved')
            self.process_absence('cleanup-process-final-absence'); self.teardown_binding(*binding)
            result = dict(state='TASK_APP_REMOVED',appAbsence='PASS',processAbsence='PASS',containerAbsence='UNVERIFIED',
                dataDisposition='OS_APP_UNINSTALL_CONTRACT',directlyObservedFilesystemAbsence=False,
                preSDKFreshness='PASS',deviceOS=properties['osVersionNumber'],deviceBuild=properties['osBuildUpdate'],
                scenario='UNCHANGED',evidence='UNCHANGED',releaseAcceptance=False,at=time.time(),deadline=deadline)
            encoded = t.encode(result); t.save(folder/'result.json',encoded)
            self.teardown_binding(*binding)
            t.require(setup.read(folder/'result.json') == encoded, 'H10 cleanup result changed')
            return result
        except Exception as error:
            if not self.termination_attempted and (folder/'teardown-admission.json').exists():
                (folder/'teardown-admission.json').rename(folder/'invalidated-teardown-admission.json')
            self.failure(folder,error); raise


LOADED_SOURCES = sources()
