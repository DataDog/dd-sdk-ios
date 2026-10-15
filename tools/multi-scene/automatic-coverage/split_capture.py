"""Opt-in foreground inventory with a separate release and cleanup boundary."""
import hashlib
import json
from pathlib import Path
import uuid
import human_capture
import split_ownership as ownership
from acceptance_common import require


class Collector(human_capture.Collector):
    home_collection_state = 'LOCAL_SPLIT_FOREGROUND_INVENTORY_COLLECTED'
    home_completion_scope = dict(profile=ownership.PROFILE, home_lifecycle_qualified=False,
                                 cleanup_authorized=False, post_home_native_owner_observed=False)

    def __init__(self, *, identity, reference, **kwargs):
        super().__init__(**kwargs)
        self.identity = identity
        self.reference = reference
        self.expected = None
        self.evaluation = None
        self.sealed = None

    def terminal_rows(self, raw, *, prefix):
        if not raw.endswith(b'\n'):
            return None
        require(raw.startswith(prefix), 'changed split Home checkpoint')
        rows = self.pending_rows(raw)
        # A post-checkpoint appearance and its observer receipt are queued writes.
        # A complete line can therefore still be an incomplete observation.
        human_capture.oracle.rows(prefix, self.run)
        appended = rows[len(prefix.splitlines()):]
        costs = {row['payload'].get('event_sequence') for row in appended if row['kind'] == 'human_observer_cost'}
        if any(row['kind'] == 'human_appearance' and row['sequence'] not in costs for row in appended):
            return None
        folder = self.output/'background.before'
        request = (folder/'request.json').read_bytes()
        idle = self.documents/('home-input-idle-'+json.loads(request)['request_id']+'.json')
        if not idle.is_file():
            return None
        if self.expected is None:
            events = [row['payload'] for row in rows if row['kind'] == 'rum']
            if not events:
                return None
            event_identity = ownership.event_identity(events[0])
            reference = self.reference['expected']['event_identity']
            require(event_identity[:3] == tuple(reference[:3]) and event_identity[4] == reference[4]
                    and event_identity[3] != reference[3], 'foreign or restored split telemetry session')
            uuid.UUID(event_identity[3])
            self.expected = dict(profile=ownership.PROFILE, run_id=self.run, binding=self.binding,
                launch=dict(build_sdk='iphonesimulator27.1', bundle=self.identity['bundle'], framework='UIKit',
                            layout='split', multiple_scenes=False, os='27.1', pid=self.pid), event_identity=event_identity)
        ownership.native = human_capture.oracle
        self.evaluation = ownership.evaluate(raw, prefix=prefix, expected=self.expected,
            home_request=request, home_idle=json.loads(idle.read_bytes()), reference_tail=self.reference['reference_tail'])
        return self.evaluation['rows'] if self.evaluation is not None else None

    def pending_rows(self, raw):
        return human_capture.pending_rows(raw, self.run)

    def local_result(self, run):
        require(self.evaluation is not None, 'split inventory is pending')
        return ownership.comparison_inventory(run, self.evaluation, self.receipts)

    def seal(self, out, run):
        """Freeze observed behavior before asking for release or activating cleanup."""
        raw = (self.documents/'events.jsonl').read_bytes()
        prefix = (self.output/'background.before/background-events.jsonl').read_bytes()
        require(self.terminal_rows(raw, prefix=prefix) is not None, 'split inventory incomplete at cleanup cutoff')
        local = self.local_result(run)
        (out/'split-comparison-events.jsonl').write_bytes(raw)
        human_capture.shared.save(out/'split-comparison-evaluation.json',
                                  {key: value for key, value in self.evaluation.items() if key != 'rows'}, exclusive=True)
        self.sealed = dict(state='SEALED_BEFORE_RELEASE', run_id=self.run, byte_count=len(raw),
                           sha256=hashlib.sha256(raw).hexdigest(), sequence=self.evaluation['rows'][-1]['sequence'],
                           evaluation_sha256=human_capture.shared.sha(out/'split-comparison-evaluation.json'),
                           home_lifecycle_qualified=False, cleanup_authorized=False)
        human_capture.shared.save(out/'split-comparison-cutoff.json', self.sealed, exclusive=True)
        (out/'events.jsonl').write_bytes(raw)
        human_capture.shared.save(out/'local-result.json', local)
        return raw

    def preserved(self, out, raw):
        """Cleanup observations are retained but can never repair the sealed result."""
        require(self.sealed is not None, 'split comparison was not sealed before release')
        prefix = (out/'split-comparison-events.jsonl').read_bytes()
        require(len(prefix) == self.sealed['byte_count'] and hashlib.sha256(prefix).hexdigest() == self.sealed['sha256']
                and raw.startswith(prefix), 'cleanup changed the split comparison prefix')
        require(human_capture.shared.read(out/'split-comparison-cutoff.json') == self.sealed
                and human_capture.shared.sha(out/'split-comparison-evaluation.json') == self.sealed['evaluation_sha256'],
                'sealed split assessment changed')
        rows = human_capture.oracle.rows(raw, self.run)
        tail = rows[self.sealed['sequence']:]
        requests = {json.loads(path.read_bytes())['request_id'] for path in (out/'human-release').glob('idle-*/request.json')}
        require(requests, 'split cleanup has no fresh native idle request')
        screens = {row['payload']['screen'] for row in rows[:self.sealed['sequence']]
                   if row['kind'] in ['human_appearance', 'native_appear']}
        context_requests = requests | {json.loads(path.read_bytes())['request_id'] for path in
            [self.output/'background.before/request.json', self.output/'background.before/home-finish-request.json'] if path.exists()}
        for row in tail:
            kind = row['kind']
            require(kind in ['rum', 'geometry', 'human_snapshot', 'human_appearance', 'native_appear', 'human_observer_cost'],
                    'unexpected native input or record after split cutoff')
            if kind == 'rum':
                event = row['payload']
                require(event['type'] == 'view' and ownership.event_identity(event) == tuple(self.expected['event_identity']),
                        'new or foreign Action after split cutoff')
            elif kind == 'human_snapshot':
                require(row['payload']['phase'] == 'cleanup.idle' and row['payload']['request_id'] in requests,
                        'unknown post-cutoff snapshot')
            elif kind in ['human_appearance', 'native_appear']:
                require(row['payload']['screen'] in screens, 'unknown cleanup appearance')
                if kind == 'human_appearance':
                    require(row['payload']['request_id'] in context_requests, 'foreign cleanup appearance request')
            elif kind == 'geometry':
                scene = human_capture.oracle.one(row['payload']['scenes'], 'cleanup scene')
                require(scene['id'] == self.binding['scene'], 'foreign cleanup geometry')
        proof = human_capture.shared.read(out/'human-release/quiescent.json')
        require(proof['state'] == 'PASS' and proof['native']['state'] == 'NATIVE_INPUT_IDLE'
                and proof['native']['run_id'] == self.run and proof['native']['request_id'] in requests,
                'fresh split cleanup idle missing')
        release = out/'human-release'
        request_raw = (release/'request.json').read_bytes()
        reply_raw = (release/'operator-released.json').read_bytes()
        human_capture.human_release.release_protocol.validate_ack(json.loads(request_raw), request_raw,
            json.loads(reply_raw), proof['at'])
        require(hashlib.sha256(reply_raw).hexdigest() == proof['operator_sha256'] and proof['at'] <= proof['deadline'],
                'split release acknowledgement changed')
        idle_folder = next(path.parent for path in release.glob('idle-*/request.json')
                           if json.loads(path.read_bytes())['request_id'] == proof['native']['request_id'])
        replayed = human_capture.human_release.idle(raw, human_capture.shared.read(idle_folder/'checkpoint.json'),
            (idle_folder/'request.json').read_bytes(), self.run, self.binding, (release/'failed-scenario-prefix.jsonl').read_bytes())
        require(replayed == proof['native'], 'preserved split cleanup idle differs')
        human_capture.shared.save(out/'split-cleanup-observations.json', dict(state='SEPARATE_CLEANUP_ONLY',
            cutoff=self.sealed, rows=tail, cleanup_idle=proof, comparison_unchanged=True), exclusive=True)
