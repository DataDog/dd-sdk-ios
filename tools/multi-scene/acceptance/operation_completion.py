"""Collect the immutable H06 local interval; display/backend/cleanup stay separate.

No app launch, input, SDK admission or teardown occurs here. The one directory
transfer remains unqualified on physical hardware until its first bounded use.
"""
import base64
from pathlib import Path
import re
import struct
import time

import operation_setup as setup
import operation_transport as t

TERMINAL = 'native-local-result.json'
FAILURE = 'native-admission-failure.json'
MAX_FILES = 20_000
MAX_TREE_BYTES = 128 * 1024 * 1024
FIELDS = {'schemaVersion', 'identity', 'state', 'profile', 'deadline', 'setupCaptureSHA256',
          'hostPublicationSHA256', 'finalObservation', 'finalObservationSHA256',
          'finalMapperSHA256', 'observationCount', 'artifacts'}
DISPLAY_FILES = {'display-binding-scene-A.json', 'display-binding-scene-B.json',
                 'display-START.json', 'display-RUN.json', 'display-FINAL.json',
                 'display-start-proof-consumed.json', 'display-run-proof-consumed.json',
                 'display-final-proof-consumed.json', 'display-final-context.json', 'display-completion.json'}


def decode_handoff(raw, identity, deadline):
    value = t.load(raw, maximum=t.MAX_CONTEXT_BYTES)
    t.require(set(value) == {'schemaVersion', 'identity', 'proof', 'result'}
              and value['schemaVersion'] == 1 and value['identity'] == identity,
              'foreign host publication')
    proof_raw = base64.b64decode(value['proof'], validate=True)
    result_raw = base64.b64decode(value['result'], validate=True)
    proof, result = t.load(proof_raw), t.load(result_raw)
    t.require(proof['identity'] == identity and proof['deadline'] == result['deadline'] == deadline
              and proof['state'] == result['state'] == 'HOST_PROOF_PREPARED'
              and result['proofSHA256'] == t.sha(proof_raw) and t.digest(proof['captureSHA256'])
              and all(x['sdkAdmitted'] is False and x['teardownAuthorized'] is False for x in [proof, result]),
              'host proof result differs')
    return proof


def terminal(raw, identity, publication, deadline):
    value = t.load(raw, maximum=t.MAX_CONTEXT_BYTES)
    proof = decode_handoff(publication, identity, deadline)
    t.validate_setup(identity['setupProfile'])
    expected_fields = FIELDS | ({'displayArtifacts'} if 'displayProof' in proof else set())
    t.require(set(value) == expected_fields and type(value['schemaVersion']) is int and value['schemaVersion'] == 1
              and value['identity'] == identity and value['state'] == 'LOCAL_OWNERS_VERIFIED'
              and value['profile'] == identity['setupProfile']['scenario'] and value['deadline'] == deadline
              and value['setupCaptureSHA256'] == proof['captureSHA256']
              and value['hostPublicationSHA256'] == t.sha(publication), 'foreign terminal identity or proof')
    if 'displayProof' in proof:
        display = value['displayArtifacts']
        t.require(isinstance(display, dict) and set(display) == DISPLAY_FILES
                  and all(t.digest(v) for v in display.values()), 'incomplete display completion inventory')
    count, artifacts = value['observationCount'], value['artifacts']
    t.require(type(count) is int and 1 <= count < MAX_FILES and isinstance(artifacts, dict),
              'invalid completion inventory')
    t.require(value['finalObservation'] == f'native-observation-{count}.json', 'invalid final observation pointer')
    required = {'native-host-consumed.json', 'native-admission.json', 'native-binding-mapper.json', 'native-final-mapper.json'}
    observations = {f'native-observation-{i}.json' for i in range(1, count + 1)}
    t.require(required | observations <= artifacts.keys(), 'incomplete native manifest')
    for name, digest in artifacts.items():
        t.require(isinstance(name, str) and t.digest(digest)
                  and (name in required | observations or re.fullmatch(r'native-mapper-(binding|collection)-[1-9][0-9]*\.json', name)),
                  'unexpected native artifact')
    t.require(value['finalObservationSHA256'] == artifacts[value['finalObservation']]
              and value['finalMapperSHA256'] == artifacts['native-final-mapper.json']
              and value['hostPublicationSHA256'] == artifacts['native-host-consumed.json'],
              'terminal artifact hashes differ')
    return value


def tree_inventory(directory):
    directory = Path(directory)
    t.require(directory.is_dir() and not directory.is_symlink(), 'native directory missing or symlinked')
    inventory, total = {}, 0
    for path in sorted(directory.rglob('*')):
        t.require(not path.is_symlink(), 'native directory contains symlink')
        if path.is_dir():
            continue
        t.require(path.is_file(), 'nonregular native artifact')
        total += path.stat().st_size
        t.require(len(inventory) < MAX_FILES and total <= MAX_TREE_BYTES, 'native directory exceeds evidence bounds')
        inventory[str(path.relative_to(directory))] = setup.file_sha(path)
    return inventory


def sample_owners(sample, owners):
    t.require(sample.get('failure') is None and sample['before'] == sample['after'] == owners['input'],
              'input or continuity differs within sealed interval')
    projected = {}
    for item in sample['reads']:
        scene = item['logicalSceneID']; context = item['value']
        t.require(scene not in projected and isinstance(context, dict), 'duplicate or missing SDK owner')
        projected[scene] = dict(logicalSceneID=scene, nativeSceneID=item['targetNativeSceneID'],
            **{key: context[key] for key in ['applicationID', 'sessionID', 'viewID', 'viewName', 'viewURL']})
    t.require(projected == owners['contexts'], 'SDK ownership differs within sealed interval')


def display_snapshot(value, owners, inventory, read_raw, proof):
    """Join native-consumed display bytes; pixels still require independent assessment."""
    artifacts = value['displayArtifacts']; prefix = value['identity']['runID'] + '.operations-'
    for name, digest in artifacts.items():
        t.require(inventory.get(prefix + name) == digest, 'display artifact missing or changed: ' + name)
    read = lambda name: t.load(read_raw(name), maximum=t.MAX_CONTEXT_BYTES)
    bindings = {scene: read('display-binding-' + scene + '.json') for scene in ['scene-A', 'scene-B']}
    owner_hashes = {scene: artifacts['display-binding-' + scene + '.json'] for scene in bindings}
    native = {row['logicalSceneID']: row for row in owners['input']['input']}
    for scene, binding in bindings.items():
        t.require(binding == {key: native[scene][key] for key in
                  ['logicalSceneID', 'nativeSceneID', 'generation', 'windowIdentity', 'rootIdentity']},
                  'display binding differs from admitted native owner')
    nonce = None; previous = None; request_ids = set()
    bits = format(struct.unpack('>Q', struct.pack('>d', value['deadline']))[0], 'x')
    for sequence, phase in enumerate(['START', 'RUN', 'FINAL']):
        receipt_name = 'display-' + phase + '.json'
        receipt = read(receipt_name); consumed = read('display-' + phase.lower() + '-proof-consumed.json')
        nonce = receipt['nonce'] if nonce is None else nonce
        cause = None if phase == 'START' else (artifacts['display-start-proof-consumed.json']
                                              if phase == 'RUN' else value['finalObservationSHA256'])
        t.require(receipt['schemaVersion'] == 1 and receipt['identity'] == value['identity']
                  and receipt['phase'] == phase and receipt['sequence'] == sequence
                  and receipt['nonce'] == nonce and receipt['deadlineBits'] == bits
                  and receipt['bindings'] == bindings and receipt['bindingSHA256'] == owner_hashes
                  and receipt.get('previousReceiptSHA256') == previous and receipt.get('causeSHA256') == cause
                  and receipt['nativeAcceptance'] is False, 'native display receipt chain differs')
        t.require(consumed['identity'] == value['identity'] and consumed['phase'] == phase
                  and consumed['nonce'] == nonce and consumed['deadlineBits'] == bits
                  and consumed['owners'] == owner_hashes and consumed['nativeReceiptSHA256'] == artifacts[receipt_name]
                  and consumed['requestID'] not in request_ids, 'consumed display proof chain differs')
        request_ids.add(consumed['requestID']); previous = artifacts[receipt_name]
    t.require(base64.b64decode(proof['displayProof'], validate=True) == read_raw('display-run-proof-consumed.json'),
              'display RUN proof differs from host admission')
    completion = read('display-completion.json')
    t.require(completion == dict(state='DISPLAY_PROOFS_CONSUMED', nonce=nonce,
                  runProofSHA256=artifacts['display-run-proof-consumed.json'],
                  finalProofSHA256=artifacts['display-final-proof-consumed.json'],
                  finalObservationSHA256=value['finalObservationSHA256'], contextSHA256=artifacts['display-final-context.json']),
              'display completion is not bound to the collection seal and final context')
    sample_owners(read('display-final-context.json'), owners)


def validate_snapshot(directory, raw, *, identity, publication, deadline):
    """Structural evidence joins only; Swift owns native semantics."""
    directory = Path(directory); prefix = identity['runID'] + '.operations-'
    t.require(not (directory / (prefix + FAILURE)).exists(), 'native admission failed')
    value = terminal(raw, identity, publication, deadline)
    inventory = tree_inventory(directory)
    expected = {prefix + name for name in value['artifacts']} | {prefix + TERMINAL}
    actual = {name for name in inventory if name.startswith(prefix + 'native-')}
    t.require(actual == expected, 'native completion files missing or unexpected')
    t.require(setup.read(directory / (prefix + TERMINAL)) == raw, 'terminal changed during directory transfer')
    for name, digest in value['artifacts'].items():
        t.require(inventory[prefix + name] == digest, 'native artifact changed: ' + name)
    read = lambda name: t.load(setup.read(directory / (prefix + name)), maximum=t.MAX_CONTEXT_BYTES)
    t.require(setup.read(directory / (prefix + 'native-host-consumed.json')) == publication,
              'native consumed a different host publication')
    owners = read('native-admission.json')
    t.require(owners['runID'] == identity['runID'] and owners['processID'] == identity['processID']
              and owners['profile'] == identity['setupProfile']
              and owners['setupCaptureSHA256'] == value['setupCaptureSHA256'], 'foreign admitted owners')
    observations = [read(f'native-observation-{i}.json') for i in range(1, value['observationCount'] + 1)]
    order = [(row['index'], row['boundary']) for row in observations]
    offset = 0
    while order[offset:offset + 2] == [(4, 'binding-before'), (4, 'binding-after')]:
        offset += 2
    t.require(offset >= 2, 'binding observations missing')
    steps = [(i, boundary) for i in range(4, 22) for boundary in ['before', 'call', 'after']]
    t.require(order[offset:offset + len(steps)] == steps, 'critical observation interval differs')
    tail = order[offset + len(steps):]
    t.require(len(tail) >= 2 and tail[-1] == (21, 'collection-seal')
              and all(x == (21, 'collection') for x in tail[:-1]), 'final collection boundary differs')
    # Digests preserve raw encoding. Equality compares decoded observations and
    # never reserializes geometry into a new native proof.
    for row in observations:
        sample_owners(row['sample'], owners)
    if 'displayArtifacts' in value:
        display_snapshot(value, owners, inventory, lambda name: setup.read(directory / (prefix + name)),
                         decode_handoff(publication, identity, deadline))
    return dict(manifest=value, owners=owners, inventory=inventory)


class Completion:
    """One-use collector using the already published HostSetup instance."""
    def __init__(self, host, *, wait=lambda: time.sleep(.25)):
        self.host, self.channel, self.remote = host, host.channel, host.remote
        self.identity = host.identity
        self.folder = host.channel.output / 'native-completion'; self.folder.mkdir()
        self.wait, self.used = wait, False
        self.host.live()
        published = t.load(setup.read(host.folder / 'publication/result.json'))
        t.require(published['state'] == 'HOST_PROOF_PUBLISHED' and published['deadline'] == self.channel.deadline
                  and published['sdkAdmitted'] is False and published['teardownAuthorized'] is False
                  and t.digest(published['payloadSHA256']), 'host proof not published')
        self.publication = setup.read(host.folder / ('publication/host-publication-' + published['payloadSHA256'] + '.json'))
        t.require(t.sha(self.publication) == published['payloadSHA256'], 'host publication changed')
        decode_handoff(self.publication, self.identity, self.channel.deadline)
        t.save(self.folder / 'definition.json', t.encode(dict(identity=self.identity,
            publicationSHA256=published['payloadSHA256'], deadline=self.channel.deadline,
            directoryTransfers=1, sdkAdmitted=False, teardownAuthorized=False)))

    def download(self, source, destination, label):
        def pull(*args, **kwargs):
            observed, receipt = self.remote.pull(*args, **kwargs)
            folder = self.remote.output / (f'{self.remote.sequence:05d}-' + label)
            response_raw = setup.read(folder / 'response.json')
            receipt_raw = setup.read(folder / 'receipt.json')
            t.save(self.folder / (label + '-response.json'), response_raw)
            t.save(self.folder / (label + '-receipt.json'), receipt_raw)
            t.require(t.load(response_raw) == observed and t.load(receipt_raw) == receipt
                      and receipt['response_sha256'] == t.sha(response_raw), 'returned transfer differs from actual saved observation')
            return observed, receipt
        return self.channel.transfer(pull, source, destination, label, optional=True)

    def collect(self):
        t.require(not self.used, 'native completion already consumed'); self.used = True
        prefix = 'Documents/' + self.identity['runID'] + '.operations-'
        try:
            for attempt in range(1, 100_001):
                self.host.live()
                failure = self.folder / f'failure-{attempt:06d}.json'
                if self.download(prefix + FAILURE, failure, f'completion-failure-{attempt:06d}'):
                    raise ValueError('native admission failed')
                destination = self.folder / f'terminal-{attempt:06d}.json'
                if self.download(prefix + TERMINAL, destination, f'completion-terminal-{attempt:06d}'):
                    raw = setup.read(destination)
                    terminal(raw, self.identity, self.publication, self.channel.deadline)
                    documents = self.folder / 'documents'
                    t.require(self.download('Documents', documents, 'completion-directory'), 'completed directory missing')
                    joined = validate_snapshot(documents, raw, identity=self.identity,
                        publication=self.publication, deadline=self.channel.deadline)
                    self.host.live()
                    t.save(self.folder / 'sealed-inventory.json', t.encode(joined['inventory']))
                    result = dict(state='LOCAL_EVIDENCE_COLLECTED', localOwnership='NATIVE_VERIFIED',
                        display='PENDING', backend='PENDING', cleanup='PENDING', overall='UNQUALIFIED',
                        identity=self.identity, terminalSHA256=t.sha(raw),
                        inventorySHA256=setup.file_sha(self.folder / 'sealed-inventory.json'),
                        deadline=self.channel.deadline, finishedAt=time.time(), teardownAuthorized=False)
                    t.save(self.folder / 'result.json', t.encode(result)); self.host.live()
                    return joined
                self.wait()
            raise ValueError('native completion receipt attempt bound exhausted')
        except Exception as error:
            t.save(self.folder / 'failure.json', t.encode(dict(state='INVALID', errorType=type(error).__name__,
                reason=str(error), deadline=self.channel.deadline, finishedAt=time.time(), teardownAuthorized=False)))
            raise
