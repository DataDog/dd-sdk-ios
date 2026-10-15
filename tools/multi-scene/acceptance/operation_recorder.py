"""Join H06 native completion to the captured recorder, without new native work.

The semantic terminal closes the scenario prefix, not the file. Mapper/lifecycle
signals may continue afterward; keep those bytes without filling earlier gaps.
"""
import json
from pathlib import Path
import time

import operation_completion as completion
import operation_ownership as ownership
import operation_setup as setup
import operation_transport as t

SOURCE = 'Library/Application Support/ProbeAcceptance/probe.jsonl'
MAX_BYTES = 16 * 1024 * 1024
COMPLETED = 'physical-operations-owners-verified'


class Pending(ValueError):
    """The same recorder may append its terminal line within the original budget."""


def member_bytes(raw, keys):
    """Select original encoded object bytes; never hash a Python re-encoding."""
    text = raw.decode('utf-8'); decoder = json.JSONDecoder()
    for wanted in keys:
        offset = 0
        while text[offset].isspace(): offset += 1
        t.require(text[offset] == '{', 'manifest member is not an object')
        offset += 1; found = False
        while True:
            while text[offset].isspace(): offset += 1
            if text[offset] == '}': break
            key, offset = decoder.raw_decode(text, offset)
            while text[offset].isspace(): offset += 1
            t.require(text[offset] == ':', 'invalid manifest member')
            offset += 1
            while text[offset].isspace(): offset += 1
            start = offset; _, offset = decoder.raw_decode(text, offset)
            if key == wanted:
                text = text[start:offset]; found = True; break
            while text[offset].isspace(): offset += 1
            if text[offset] == '}': break
            t.require(text[offset] == ',', 'invalid manifest separator'); offset += 1
        t.require(found, 'manifest member missing: ' + wanted)
    return text.encode('utf-8')


def backend_inputs(owners):
    contexts = owners['contexts']
    t.require(set(contexts) == {'scene-A', 'scene-B'} and owners['source'] == 'ios'
              and owners['service'] == 'ios-sdk-native-multi-scene-probe', 'native backend family differs')
    application = ownership.identifier(owners['applicationID'], 'native application')
    sessions, views = set(), {}
    for scene, value in contexts.items():
        t.require(value['logicalSceneID'] == scene and value['applicationID'] == application,
                  'native backend owner identity differs')
        sessions.add(ownership.identifier(value['sessionID'], 'native session'))
        views[scene] = ownership.identifier(value['viewID'], 'native view')
    t.require(len(sessions) == 1 and len(set(views.values())) == 2, 'native session differs or views alias')
    return dict(run_id=owners['runID'], session_id=next(iter(sessions)), scene_views=views,
                application_id=application, service=owners['service'])


def validate_stream(raw, *, identity, joined, documents):
    t.require(isinstance(raw, bytes) and len(raw) <= MAX_BYTES, 'recorder exceeds evidence bound')
    end = raw.rfind(b'\n') + 1
    lines = raw[:end].splitlines(keepends=True)
    if not lines: raise Pending('recorder has no complete line')
    rows = [t.load(line, maximum=t.MAX_CONTEXT_BYTES) for line in lines]
    t.require(all(isinstance(r, dict) and r.get('type') in {'manifest', 'signal', 'semantic-result'} for r in rows),
              'unknown recorder row')
    t.require(rows[0]['type'] == 'manifest' and sum(r['type'] == 'manifest' for r in rows) == 1,
              'missing, repeated or late manifest')
    manifest = rows[0]['manifest']; profile = identity['setupProfile']
    t.require(type(manifest['schemaVersion']) is int and manifest['schemaVersion'] == 3
              and manifest['runID'] == identity['runID'] and manifest['runMode'] == 'clean'
              and manifest['validationErrors'] == [] and manifest['scenario']['identifier'] == profile['scenario'],
              'foreign recorder manifest')
    t.require(t.sha(member_bytes(lines[0], ['manifest', 'scenario'])) == profile['fullScenarioSHA256'],
              'recorder scenario differs from native setup')
    conditions = manifest['scenario']['completionConditions']
    t.require(conditions == [dict(kind='assertion', name=COMPLETED)]
              and manifest['scenario']['expectedSemanticTimeline'] == [], 'physical setup oracle differs')
    signals, terminal_index, cutoff_signals = [], None, None
    for index, row in enumerate(rows[1:], 1):
        if row['type'] == 'semantic-result':
            t.require(terminal_index is None and row['runID'] == identity['runID'], 'repeated or foreign terminal')
            result = row['result']
            t.require(type(result['schemaVersion']) is int and result['schemaVersion'] == 1
                      and result['scenarioID'] == profile['scenario'] and result['state'] == 'PASS'
                      and type(result['matchedExpectationCount']) is int and result['matchedExpectationCount'] == len(conditions)
                      and result['issues'] == [], 'generic scenario terminal did not pass')
            terminal_index, cutoff_signals = index, len(signals)
            continue
        t.require(row['type'] == 'signal', 'late recorder manifest')
        signal = row['signal']
        t.require(type(signal['schemaVersion']) is int and signal['schemaVersion'] == 5
                  and signal['runID'] == identity['runID'] and signal['scenarioID'] == profile['scenario']
                  and type(signal['sequence']) is int and signal['sequence'] == len(signals) + 1,
                  'foreign, missing or reordered recorder signal')
        t.require(not (signal['kind'] == 'assertion' and signal.get('result') in {'FAIL', 'INCONCLUSIVE', 'SKIPPED'}),
                  'recorder assertion failed')
        if terminal_index is not None:
            t.require(signal['kind'] not in {'assertion', 'rum-operation', 'step-started', 'step-acknowledged'},
                      'critical work or assertion follows semantic cutoff')
        signals.append(signal)
    if terminal_index is None: raise Pending('recorder terminal is not persisted yet')
    prefix = signals[:cutoff_signals]
    completed = [r for r in prefix if r['kind'] == 'assertion' and r.get('name') == COMPLETED]
    t.require(len(completed) == 1 and completed[0].get('result') == 'PASS', 'native completion assertion missing or repeated')
    documents = Path(documents); name_prefix = identity['runID'] + '.operations-'
    matched = {}
    for name, digest in joined['manifest']['artifacts'].items():
        if name not in {'native-binding-mapper.json', 'native-final-mapper.json'} and not name.startswith('native-mapper-'):
            continue
        observed = setup.read(documents / (name_prefix + name))
        t.require(t.sha(observed) == digest, 'native recorder snapshot changed')
        snapshot = t.load(observed, maximum=t.MAX_CONTEXT_BYTES)
        t.require(isinstance(snapshot, list) and snapshot and len(snapshot) <= len(prefix)
                  and t.encode(snapshot) == t.encode(prefix[:len(snapshot)]), 'native snapshot is not a recorder prefix')
        matched[name] = len(snapshot)
    t.require({'native-binding-mapper.json', 'native-final-mapper.json'} <= matched.keys()
              and matched['native-binding-mapper.json'] <= matched['native-final-mapper.json']
              < completed[0]['sequence'], 'recorder terminal precedes native completion')
    cutoff = sum(map(len, lines[:terminal_index + 1]))
    return dict(state='RECORDER_PREFIX_JOINED', runID=identity['runID'], scenarioID=profile['scenario'],
                recorderSHA256=t.sha(raw), bytes=len(raw), cutoffBytes=cutoff,
                cutoffSHA256=t.sha(raw[:cutoff]), preterminalSignals=cutoff_signals,
                postterminalSignals=len(signals) - cutoff_signals, untrustedTailBytes=len(raw) - end,
                untrustedTailSHA256=t.sha(raw[end:]), nativeSnapshots=matched,
                backendInputs=backend_inputs(joined['owners']), backend='PENDING', display='PENDING',
                cleanup='PENDING', overall='UNQUALIFIED', teardownAuthorized=False)


class Recorder:
    """One setup/completion instance, one directory pull, bounded recorder reads."""
    def __init__(self, local):
        self.local = local; self.folder = local.folder / 'recorder'; self.folder.mkdir()
        self.used = False
        t.save(self.folder / 'definition.json', t.encode(dict(identity=local.identity, source=SOURCE,
            deadline=local.channel.deadline, directoryTransfers=1, teardownAuthorized=False)))

    def collect(self):
        t.require(not self.used, 'recorder completion already consumed'); self.used = True
        previous = b''
        try:
            joined = self.local.collect()
            for attempt in range(1, 100_001):
                self.local.host.live()
                destination = self.folder / f'probe-{attempt:06d}.jsonl'
                present = self.local.download(SOURCE, destination, f'recorder-{attempt:06d}')
                if present:
                    raw = setup.read(destination, maximum=MAX_BYTES)
                    t.require(raw.startswith(previous), 'recorder was replaced or truncated'); previous = raw
                    try:
                        result = validate_stream(raw, identity=self.local.identity, joined=joined,
                                                 documents=self.local.folder / 'documents')
                    except Pending as error:
                        t.save(self.folder / f'pending-{attempt:06d}.json', t.encode(dict(reason=str(error),
                            observedSHA256=t.sha(raw), bytes=len(raw), deadline=self.local.channel.deadline)))
                    else:
                        failure = self.folder / 'native-failure-final.json'
                        source = 'Documents/' + self.local.identity['runID'] + '.operations-' + completion.FAILURE
                        t.require(not self.local.download(source, failure, 'recorder-native-failure-final'), 'native admission failed after collection')
                        rejoined = completion.validate_snapshot(self.local.folder / 'documents',
                            setup.read(self.local.folder / 'documents' / (self.local.identity['runID'] + '.operations-' + completion.TERMINAL)),
                            identity=self.local.identity, publication=self.local.publication, deadline=self.local.channel.deadline)
                        t.require(rejoined == joined, 'sealed native evidence changed during recorder collection')
                        self.local.host.live()
                        result.update(artifact=destination.name, attempts=attempt, finishedAt=time.time(), deadline=self.local.channel.deadline)
                        t.save(self.folder / 'result.json', t.encode(result)); self.local.host.live()
                        return result
                self.local.wait()
            raise ValueError('recorder attempt bound exhausted')
        except Exception as error:
            t.save(self.folder / 'failure.json', t.encode(dict(state='INVALID', errorType=type(error).__name__,
                reason=str(error), deadline=self.local.channel.deadline, finishedAt=time.time(), teardownAuthorized=False)))
            raise
