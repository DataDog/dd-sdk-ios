"""Typed H06 display handoff. No capture, launch, input or teardown authority.

The caller supplies original native observations and finalized decoder manifests.
This bridge joins them to the collected setup and publishes only its one-use
proof messages. Device capture and native completion remain separate obligations.
"""
import base64
from pathlib import Path
import struct
import time
import uuid

import operation_display as pixels
import operation_setup as setup
import operation_transport as t

PHASES = ('START', 'RUN', 'FINAL')
SCENES = ('scene-A', 'scene-B')
GEOMETRY_SCOPE = 'Phase publication only; START arrangement may change. Host must join fresh native capture and actual pixels.'


def blob(raw):
    t.require(isinstance(raw, bytes) and len(raw) <= 65536, 'oversized display blob')
    return dict(bytes=base64.b64encode(raw).decode(), sha256=t.sha(raw))


def media(reference, kind, source_sha256, binary_sha256):
    frames = pixels.checked(reference, kind)
    manifest_raw = pixels.verified_ref(reference, 65536)
    manifest = t.load(manifest_raw)
    t.require(manifest['decoder_source']['sha256'] == source_sha256
              and manifest['executable']['sha256'] == binary_sha256,
              'display codec differs from frozen native contract')
    raw = {name: pixels.verified_ref(manifest[name], 65536)
           for name in ['decoder', 'invocation', 'process']}
    t.require(t.load(raw['invocation'])['native_acceptance'] is False,
              'decoder invocation cannot grant native acceptance')
    return dict(reference=dict(reference), manifest=blob(manifest_raw),
                **{name: blob(value) for name, value in raw.items()}), frames


class DisplayProofBridge:
    """START request -> RUN host handoff -> FINAL proof; failure is permanent."""
    def __init__(self, host, *, nonce, source_sha256, binary_sha256):
        self.host, self.channel = host, host.channel
        self.folder = self.channel.output / 'display-proofs'
        self.folder.mkdir()
        self.state = 'NEW'; self.failed = False
        self.files = {}; self.receipts = {}; self.anchors = {}; self.proofs = {}
        self.request_ids = set(); self.movie = None
        try:
            t.require(getattr(host, 'display_bridge', None) is None
                      and not (host.folder / 'publication').exists(), 'host already bound or published')
            host.display_bridge = self
            self.identity = t.load(t.encode(host.identity))
            self.deadline = self.channel.deadline
            self.bits = format(struct.unpack('>Q', struct.pack('>d', self.deadline))[0], 'x')
            self.nonce = nonce; self.source_sha256 = source_sha256; self.binary_sha256 = binary_sha256
            t.require(self.identity['schemaVersion'] == 2 and self.identity['executionArmed'] is False
                      and all(isinstance(v, str) and str(uuid.UUID(v)) == v
                              for v in [nonce, self.identity['runID']])
                      and t.digest(source_sha256) and t.digest(binary_sha256), 'invalid display identity')
            self.parent_result = setup.read(host.folder / 'result.json')
            result = t.load(self.parent_result)
            self.parent_name = 'proof-' + result['proofSHA256'] + '.json'
            self.parent_proof = setup.read(host.folder / self.parent_name)
            self.base = t.load(self.parent_proof, maximum=t.MAX_CONTEXT_BYTES)
            t.require(host.used and not (host.folder / 'failure.json').exists()
                      and result['state'] == self.base['state'] == 'HOST_PROOF_PREPARED'
                      and result['proofSHA256'] == t.sha(self.parent_proof)
                      and self.base['identity'] == self.identity
                      and result['deadline'] == self.base['deadline'] == self.deadline
                      and 'displayProof' not in self.base, 'original host collection is unavailable')
            captured = t.load(setup.read(host.folder / 'native-capture.json'))
            self.owners = setup.visible_owners(captured)
            t.require(self.base['captureSHA256'] == t.sha(setup.read(host.folder / 'native-capture.json')),
                      'setup capture differs from original host proof')
            self.bindings = {scene: dict(logicalSceneID=scene, **owner) for scene, owner in self.owners.items()}
            self.persist('configuration.json', t.encode(dict(identity=self.identity, nonce=nonce,
                deadlineBits=self.bits, sourceSHA256=source_sha256, binarySHA256=binary_sha256,
                parentProofSHA256=t.sha(self.parent_proof), parentResultSHA256=t.sha(self.parent_result))))
            self.live()
        except Exception as error:
            self.invalidate(error); raise

    def invalidate(self, error):
        self.failed = True; self.channel.stopped = True
        if not (self.folder / 'failure.json').exists():
            t.save(self.folder / 'failure.json', t.encode(dict(state='INVALID', errorType=type(error).__name__,
                phase=self.state, deadline=self.channel.deadline, finishedAt=time.time(),
                nativeAcceptance=False, teardownAuthorized=False)))

    def persist(self, name, raw):
        path = self.folder / name
        t.save(path, raw); self.files[path] = t.sha(raw)
        return path

    def live(self):
        t.require(not self.failed and not self.channel.stopped, 'display attempt consumed')
        self.host.live()
        t.require(self.channel.deadline == self.deadline and self.host.identity == self.identity
                  and getattr(self.host, 'display_bridge', None) is self, 'display channel changed')
        t.require(setup.read(self.host.folder / 'result.json') == self.parent_result
                  and setup.read(self.host.folder / self.parent_name) == self.parent_proof,
                  'original host collection changed')
        for name, digest in self.base['artifacts'].items():
            t.require(setup.file_sha(self.host.folder / name) == digest, 'collected host artifact changed')
        for path, digest in self.files.items():
            t.require(setup.file_sha(path) == digest, 'display observation changed')
        if self.movie is not None:
            media(self.movie, 'MOVIE', self.source_sha256, self.binary_sha256)
        for phase, reference in self.anchors.items():
            _, frames = media(reference, 'IMAGE', self.source_sha256, self.binary_sha256)
            t.require(pixels.inventory(frames[0], self.binding) == (phase, phase), 'saved anchor differs')

    def receipt(self, phase, raw, *, cause=None):
        self.persist('native-' + phase + '.json', raw)  # Preserve exact returned bytes before parsing.
        value = t.load(raw)
        sequence = PHASES.index(phase)
        required = {'schemaVersion', 'identity', 'nonce', 'phase', 'sequence', 'deadlineBits',
                    'bindings', 'bindingSHA256', 'surfaces', 'geometryScope', 'nativeAcceptance'}
        if sequence: required |= {'previousReceiptSHA256', 'causeSHA256'}
        t.require(set(value) == required and type(value['schemaVersion']) is int and value['schemaVersion'] == 1
                  and value['identity'] == self.identity and value['nonce'] == self.nonce
                  and value['phase'] == phase and type(value['sequence']) is int and value['sequence'] == sequence
                  and value['deadlineBits'] == self.bits and value['bindings'] == self.bindings
                  and value['bindingSHA256'] == self.binding['owners']
                  and value['nativeAcceptance'] is False and value['geometryScope'] == GEOMETRY_SCOPE,
                  'foreign native phase or owner binding')
        if sequence:
            t.require(value['previousReceiptSHA256'] == t.sha(self.receipts[PHASES[sequence - 1]])
                      and value['causeSHA256'] == cause, 'native phase causality differs')
        t.require(set(value['surfaces']) == set(SCENES), 'native publication geometry absent')
        self.receipts[phase] = raw

    def anchor(self, phase, reference):
        typed, frames = media(reference, 'IMAGE', self.source_sha256, self.binary_sha256)
        t.require(pixels.inventory(frames[0], self.binding) == (phase, phase), 'wrong display anchor')
        t.require(not any(reference['path'] == r['path'] or reference['sha256'] == r['sha256']
                          for r in self.anchors.values()), 'reused display anchor')
        t.require([frames[0]['width'], frames[0]['height']] == self.base['display']['bounds'][1],
                  'anchor is not the collected display size')
        self.anchors[phase] = dict(reference)
        return typed

    def proof(self, phase, **extra):
        request = str(uuid.uuid4())
        t.require(request not in self.request_ids, 'display request ID reused')
        self.request_ids.add(request)
        value = dict(schemaVersion=1, identity=self.identity, nonce=self.nonce, phase=phase, requestID=request,
            nativeReceiptSHA256=t.sha(self.receipts[phase]), deadlineBits=self.bits, owners=self.binding['owners'],
            anchors={name: media(ref, 'IMAGE', self.source_sha256, self.binary_sha256)[0]
                     for name, ref in self.anchors.items()}, **extra)
        raw = t.encode(value); t.require(len(raw) <= t.MAX_CONTEXT_BYTES, 'display proof too large')
        self.persist('proof-' + phase + '.json', raw); self.proofs[phase] = raw
        return raw

    def publish(self, marker, raw):
        self.live()
        digest = t.sha(raw)
        source = self.persist(marker + '-' + digest + '.json', raw)
        selection = self.persist(marker, digest.encode())
        prefix = 'Documents/' + self.identity['runID'] + '.operations-'
        self.channel.transfer(self.channel.remote.push, source, prefix + source.name, marker + '-payload')
        self.channel.transfer(self.channel.remote.push, selection, prefix + marker, marker + '-marker')
        self.live()
        return digest

    def start(self, receipt_raw, binding_bytes, screenshot):
        try:
            self.live(); t.require(self.state == 'NEW', 'START already consumed')
            t.require(set(binding_bytes) == set(SCENES), 'missing native window bindings')
            owners = {}
            for scene, raw in binding_bytes.items():
                self.persist('binding-' + scene + '.json', raw)
                t.require(t.load(raw) == self.bindings[scene], 'display differs from captured setup owner')
                owners[scene] = t.sha(raw)
            self.binding = pixels.identity(self.identity['runID'], self.nonce, owners)
            self.receipt('START', receipt_raw)
            typed = self.anchor('START', screenshot)
            manifest = t.load(base64.b64decode(typed['manifest']['bytes'], validate=True))
            invocation = t.load(base64.b64decode(typed['invocation']['bytes'], validate=True))
            t.require(manifest['raw']['sha256'] == self.base['screenshotSHA256']
                      and invocation['source'] == pixels.reference(self.host.folder / 'screen.png'),
                      'START screenshot was not the collected host observation')
            raw = self.proof('START'); digest = self.publish('display-run-request', raw)
            self.state = 'START_PUBLISHED'
            return digest
        except Exception as error:
            self.invalidate(error); raise

    def run(self, receipt_raw, screenshot):
        try:
            self.live(); t.require(self.state == 'START_PUBLISHED', 'RUN before START or reused')
            self.receipt('RUN', receipt_raw, cause=t.sha(self.proofs['START']))
            self.anchor('RUN', screenshot)
            raw = self.proof('RUN'); self.live(); self.state = 'RUN_PREPARED'
            return raw
        except Exception as error:
            self.invalidate(error); raise

    def extend_host(self, parent_proof, parent_result):
        """Append a selected handoff while retaining the original collection."""
        try:
            self.live(); t.require(self.state == 'RUN_PREPARED', 'host publication before RUN or reused')
            t.require(parent_proof == self.parent_proof and parent_result == self.parent_result,
                      'host publication selected different parents')
            extension = dict(schemaVersion=1, identity=self.identity, deadlineBits=self.bits,
                parentProofSHA256=t.sha(parent_proof), parentResultSHA256=t.sha(parent_result),
                displayProofSHA256=t.sha(self.proofs['RUN']),
                artifacts={str(p): digest for p, digest in self.files.items()}, anchors=self.anchors,
                nativeAcceptance=False)
            extension_raw = t.encode(extension)
            t.save(self.host.folder / 'display-extension.json', extension_raw)
            proof = t.load(parent_proof, maximum=t.MAX_CONTEXT_BYTES)
            proof['displayProof'] = base64.b64encode(self.proofs['RUN']).decode()
            proof['artifacts'].update({'display-extension.json':t.sha(extension_raw),
                'result.json':t.sha(parent_result), self.parent_name:t.sha(parent_proof)})
            proof['finishedAt'] = time.time()
            raw = t.encode(proof)
            result = t.load(parent_result); result.update(proofSHA256=t.sha(raw), finishedAt=time.time())
            result_raw = t.encode(result)
            t.save(self.host.folder / ('proof-' + t.sha(raw) + '.json'), raw)
            t.save(self.host.folder / 'display-result.json', result_raw)
            proof_path = self.host.folder / ('proof-' + t.sha(raw) + '.json')
            result_path = self.host.folder / 'display-result.json'
            for path in [proof_path, result_path, self.host.folder / 'display-extension.json']:
                self.files[path] = setup.file_sha(path)
            self.persist('extended-host.json', t.encode(dict(proof=pixels.reference(proof_path),
                result=pixels.reference(result_path), extensionSHA256=t.sha(extension_raw))))
            self.live(); self.state = 'HOST_READY'
            return raw, result_raw
        except Exception as error:
            self.invalidate(error); raise

    def host_published(self, digest):
        try:
            self.live(); t.require(self.state == 'HOST_READY', 'host publication out of order')
            publication = self.host.folder / 'publication'
            result = t.load(setup.read(publication / 'result.json'))
            raw = setup.read(publication / ('host-publication-' + digest + '.json'))
            expected = t.load(setup.read(self.folder / 'extended-host.json'))
            envelope = t.load(raw, maximum=t.MAX_CONTEXT_BYTES)
            t.require(result['payloadSHA256'] == t.sha(raw) == digest
                      and base64.b64decode(envelope['proof'], validate=True) == pixels.verified_ref(expected['proof'], t.MAX_CONTEXT_BYTES)
                      and base64.b64decode(envelope['result'], validate=True) == pixels.verified_ref(expected['result'], t.MAX_CONTEXT_BYTES),
                      'published host envelope differs from selected extension')
            self.persist('host-publication.json', raw); self.state = 'HOST_PUBLISHED'
        except Exception as error:
            self.invalidate(error); raise

    def final(self, receipt_raw, observation_raw, screenshot, movie):
        try:
            self.live(); t.require(self.state == 'HOST_PUBLISHED', 'FINAL before host publication or reused')
            self.persist('collection-seal.json', observation_raw)
            seal = t.load(observation_raw, maximum=t.MAX_CONTEXT_BYTES)
            t.require(type(seal['index']) is int and seal['index'] == 21
                      and seal['boundary'] == 'collection-seal'
                      and setup.visible_owners(seal['sample']) == self.owners,
                      'FINAL does not follow the captured owners collection seal')
            self.receipt('FINAL', receipt_raw, cause=t.sha(observation_raw))
            self.anchor('FINAL', screenshot)
            typed, _ = media(movie, 'MOVIE', self.source_sha256, self.binary_sha256)
            self.movie = dict(movie)
            pixels.assess(movie, self.anchors, self.binding, self.folder / 'assessment.json')
            self.files[self.folder / 'assessment.json'] = setup.file_sha(self.folder / 'assessment.json')
            raw = self.proof('FINAL', movie=typed, assessment=blob(setup.read(self.folder / 'assessment.json')))
            digest = self.publish('display-final-proof', raw); self.state = 'FINAL_PUBLISHED'
            self.persist('result.json', t.encode(dict(state=self.state, identity=self.identity,
                finalProofSHA256=digest, deadline=self.deadline, nativeAcceptance=False, gatesClosed=[])))
            return digest
        except Exception as error:
            self.invalidate(error); raise
