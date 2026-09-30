"""H10 phase transfers after caller-owned bootstrap; no launch or cleanup authority.

The native/display boundary validator is deliberately supplied by the composed
runner. Its source and actual artifact bytes are retained; a digest cannot stand
in for that qualification. No production boundary validator is provided here.
"""
import functools
import inspect
from pathlib import Path
import time

from operation_cleanup import ObservedDevice
import operation_setup as setup
import operation_transport as t
import scene_background_capture as capture
import scene_background_cycle as cycle
import scene_background_protocol as protocol


def guarded(method):
    @functools.wraps(method)
    def call(self, *args, **kwargs):
        try:
            self.live()
            return method(self, *args, **kwargs)
        except Exception as error:
            if not self.failed:
                self.failed = True
                t.save(self.output/'failure.json', t.encode(dict(state='INVALID', operation=method.__name__,
                    error_type=type(error).__name__, reason=str(error), original_deadline=self.deadline,
                    at=time.time(), native_acceptance=False, teardown_authorized=False)))
            raise
    return call


class Channel:
    """One ordered phase chain. Any error stops it; STOP belongs to the caller."""
    maximum_polls = 128

    def __init__(self, remote, bundle, output, identity, *, boundary_validator=None, wait=lambda:time.sleep(.25)):
        protocol.identity(identity)
        self.identity = t.load(t.encode(identity)); self.remote = remote; self.bundle = bundle
        self.device = remote.identifier; self.output = Path(output); self.wait = wait
        self.deadline = identity['executionDeadlineMilliseconds']/1000
        self.created = time.time(); self.failed = False; self.validator = boundary_validator
        t.require(self.output.is_absolute() and not self.output.exists()
                  and not any(p.is_symlink() for p in [self.output, *self.output.parents]),
                  'H10 output is reused or redirected')
        t.require(isinstance(bundle, str) and bundle and isinstance(self.device, str) and self.device
                  and self.created < self.deadline, 'H10 bound transfer context is invalid')
        self.sources = {str(Path(module.__file__).resolve()): t.sha(Path(module.__file__).read_bytes())
                        for module in [protocol, capture, cycle, t, setup]}
        self.sources[str(Path(__file__).resolve())] = t.sha(Path(__file__).read_bytes())
        self.sources[str(Path(inspect.getfile(ObservedDevice)).resolve())] = t.sha(Path(inspect.getfile(ObservedDevice)).read_bytes())
        if boundary_validator is not None:
            source = Path(inspect.getfile(boundary_validator)).resolve()
            self.sources[str(source)] = t.sha(source.read_bytes())
        self.frozen = t.encode(dict(identity=self.identity, device=self.device, bundle=bundle,
                                   deadline=self.deadline, sources=self.sources, native_acceptance=False))
        self.output.mkdir(); t.save(self.output/'definition.json', self.frozen)
        io = self.output/'io'; io.mkdir()
        self.observed = ObservedDevice(remote, io, self.deadline, self.created)
        self.evidence = self.output/'evidence'; self.evidence.mkdir()
        self.index = -1; self.active = False; self.sealed = False; self.consumed = []
        self.phase = None; self.seen_challenges = set(); self.inspections = 0
        self.capture_rows = []; self.capture_sequence = 0; self.latest = None
        self.sequence = 1; self.previous = None; self.inspected_reply = None
        self.records = {'definition.json': t.sha(self.frozen)}

    def live(self):
        t.require(not self.failed and time.time() < self.deadline, 'H10 failed or original cutoff expired')
        t.require(self.output.is_dir() and not any(p.is_symlink() for p in [self.output, *self.output.parents]),
                  'H10 output was redirected')
        t.require(self.remote.identifier == self.device and t.encode(dict(identity=self.identity, device=self.device,
            bundle=self.bundle, deadline=self.deadline, sources=self.sources, native_acceptance=False)) == self.frozen,
            'H10 bound identity or device changed')
        t.require(all(t.sha(Path(path).read_bytes()) == sha for path, sha in self.sources.items()),
                  'H10 selected verifier source changed')
        t.require(all(t.sha(setup.read(self.output/path, maximum=capture.MAXIMUM_BYTES)) == sha
                      for path, sha in self.records.items()), 'H10 persisted evidence changed')

    def save(self, path, raw):
        t.save(path, raw); self.records[str(path.relative_to(self.output))] = t.sha(raw)

    @property
    def prefix(self):
        return 'Documents/'+self.identity['runID']+'.background-channel/'

    @property
    def phase_path(self):
        return 'collection/' if self.index == 3 else f'phase-{self.index}/'

    def transfer(self, source, destination, label, *, download):
        self.live()
        method = self.observed.pull if download else self.observed.push
        result, receipt = method(self.bundle, source, destination, label, self.deadline,
                                 **({'check':False} if download else {}))
        for kind in ['response', 'receipt']:
            path = self.observed.folder/f'{self.remote.sequence:05d}-{label}-{kind}.json'
            raw = setup.read(path)
            self.records[str(path.relative_to(self.output))] = t.sha(raw)
        self.live()
        return t.transferred(result, receipt, device=self.device, bundle=self.bundle,
                             source=source, destination=destination, deadline=self.deadline, optional=download)

    def download(self, source, folder, label, *, maximum=t.MAX_BYTES):
        for index in range(self.maximum_polls):
            destination = folder/f'{label}-{index:04d}.raw'
            if self.transfer(source, destination, label, download=True):
                raw = setup.read(destination, maximum=maximum)
                self.records[str(destination.relative_to(self.output))] = t.sha(raw)
                self.live(); return raw
            self.wait()
        raise ValueError('H10 publication poll bound exhausted')

    def artifact(self, reference):
        protocol.artifact_reference(reference)
        path = self.evidence/reference['name']
        if not path.exists():
            folder = self.output/f'artifact-{reference["name"][:-5]}'
            folder.mkdir()
            raw = self.download(self.prefix+'evidence/'+reference['name'], folder, 'artifact',
                                maximum=capture.MAXIMUM_BYTES)
            t.require(len(raw) == reference['bytes'] and t.sha(raw) == reference['sha256'],
                      'H10 transferred artifact bytes differ')
            self.save(path, raw)
        return capture.read_reference(self.evidence, reference)

    @guarded
    def begin(self):
        t.require(not self.active and not self.sealed and self.index < 3, 'H10 phase is already active or complete')
        self.index += 1
        self.folder = self.output/('collection' if self.index == 3 else f'phase-{self.index}')
        self.folder.mkdir()
        raw = self.download(self.prefix+self.phase_path+'challenge.json', self.folder, 'challenge')
        phase = protocol.challenge(raw, self.identity, self.index, self.consumed)
        t.require(phase['challengeID'] not in self.seen_challenges, 'H10 reused phase challenge')
        self.seen_challenges.add(phase['challengeID']); self.save(self.folder/'challenge.json', raw)
        self.phase = phase; self.previous = t.sha(raw); self.sequence = 1
        self.inspections = 0; self.inspected_reply = None; self.latest = None; self.active = True
        return phase

    def exchange(self, operation, *, display=None, proof=None):
        t.require(self.active, 'H10 phase is not active')
        sent = protocol.request(self.phase, self.sequence, operation, self.previous,
            inspected=self.inspected_reply if operation != 'inspect' else None, display=display, proof=proof)
        folder = self.folder/f'{self.sequence:03d}-{operation}'; folder.mkdir()
        self.save(folder/'request.json', sent); self.save(folder/'marker', t.sha(sent).encode())
        prefix = self.prefix+self.phase_path
        self.transfer(folder/'request.json', prefix+t.sha(sent)+'.json', 'payload', download=False)
        self.transfer(folder/'marker', prefix+'command.request', 'publish', download=False)
        raw = self.download(prefix+t.sha(sent)+'.reply.json', folder, 'reply')
        self.save(folder/'reply.json', raw)
        result, reference = protocol.reply(raw, sent, received_ms=int(time.time()*1000))
        self.previous = t.sha(raw); self.sequence += 1
        self.live()
        return sent, raw, result, reference, folder

    @guarded
    def inspect(self):
        t.require(self.inspections < 24, 'H10 inspection budget exhausted')
        _, raw, _, reference, _ = self.exchange('inspect')
        self.artifact(reference)
        actual = capture.read_capture(self.evidence, reference, self.identity)
        t.require(actual['capture']['boundary'] == self.phase['name']
                  and actual['capture']['sequence'] > self.capture_sequence and actual['terminal'] is None
                  and actual['raw_signals'][:len(self.capture_rows)] == self.capture_rows,
                  'H10 capture was reused, truncated or changed')
        self.inspections += 1; self.inspected_reply = t.sha(raw); self.latest = reference
        self.capture_sequence = actual['capture']['sequence']; self.capture_rows = actual['raw_signals']
        return actual

    def boundary(self):
        t.require(self.validator is not None and self.latest is not None and self.inspected_reply == self.previous,
                  'H10 actual native/display boundary validator is unavailable')
        actual = capture.read_capture(self.evidence, self.latest, self.identity)
        context = dict(identity=self.identity, challenge=self.phase,
                       inspectionReplySHA256=self.inspected_reply, captureSHA256=self.latest['sha256'])
        folder = self.folder/f'boundary-{self.sequence:03d}'; folder.mkdir()
        # The validator receives actual captured bytes, not an older matching observation.
        raw = self.validator(t.load(t.encode(context)), actual, folder)
        t.require(isinstance(raw, bytes), 'H10 boundary validator omitted raw evidence')
        self.save(folder/'result.json', raw)
        value = t.load(raw)
        t.require(isinstance(value, dict) and set(value) == set(context)|{'state','display','native'}
                  and value['state'] == 'PASS_SOURCE_BOUND_H10_BOUNDARY'
                  and all(t.encode(value[key]) == t.encode(expected) for key, expected in context.items()),
                  'H10 boundary does not qualify this inspection')
        for kind in ['display', 'native']:
            ref = value[kind]
            t.require(isinstance(ref, dict) and set(ref) == {'name','sha256','bytes'}
                      and isinstance(ref['name'], str) and Path(ref['name']).name == ref['name']
                      and ref['name'] not in ['', '.', '..', 'result.json'] and t.digest(ref['sha256'])
                      and type(ref['bytes']) is int and 0 < ref['bytes'] <= capture.MAXIMUM_BYTES,
                      'H10 boundary lacks actual display/native artifacts')
            path = folder/ref['name']; data = setup.read(path, maximum=capture.MAXIMUM_BYTES)
            t.require(len(data) == ref['bytes'] and t.sha(data) == ref['sha256'], 'H10 boundary artifact changed')
            self.records[str(path.relative_to(self.output))] = t.sha(data)
        self.live(); return t.sha(raw)

    def manifest(self):
        self.live()
        path = self.folder/'transfer-manifest.json'
        self.save(path, t.encode(dict(identity=self.identity, phase=self.phase, records=dict(self.records),
                                     original_deadline=self.deadline, native_acceptance=False)))
        self.live()
        return dict(path=str(path), sha256=self.records[str(path.relative_to(self.output))])

    @guarded
    def permit(self):
        t.require(self.index < 3, 'H10 collection cannot grant work')
        display = self.boundary()
        sent, returned, _, _, folder = self.exchange('permit', display=display)
        raw = self.download(self.prefix+self.phase_path+'consumed.json', folder, 'consumed')
        self.save(folder/'consumed.json', raw); protocol.consumed(raw, sent, returned)
        self.consumed.append(t.sha(returned)); self.active = False
        manifest = self.manifest()
        return dict(state='PERMIT_CONSUMPTION_BOUND_ONLY', reply_sha256=t.sha(returned),
                    manifest=manifest, native_acceptance=False)

    @guarded
    def seal(self):
        t.require(self.index == 3, 'H10 seal is out of phase')
        display = self.boundary()
        proof = protocol.semantic_proof(self.evidence, self.latest, self.phase, display)
        self.save(self.folder/'semantic-proof.json', proof)
        _, _, _, reference, _ = self.exchange('seal', display=display, proof=proof)
        value = t.load(self.artifact(reference), maximum=capture.MAXIMUM_BYTES)
        t.require(value.get('inspected') == self.latest
                  and capture.decode(value.get('semanticProof')) == proof
                  and value.get('displayReceiptSHA256') == display, 'H10 seal replaced the inspected proof')
        for key in ['inspected', 'fresh', 'extensionRows']: self.artifact(value[key])
        result = capture.validate_seal(self.evidence, reference, identity=self.identity,
            challenge=self.phase, oracle_source_sha256=t.sha(Path(cycle.__file__).read_bytes()))
        self.save(self.folder/'result.json', t.encode(result)); self.live()
        self.manifest()
        self.sealed = True; self.active = False
        return result
