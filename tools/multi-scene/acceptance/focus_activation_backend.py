"""Collect existing H04 telemetry with no native input or teardown authority."""
from pathlib import Path
import time
import uuid

from acceptance_common import Rejected, require
import focus_activation_contract as contract
import focus_activation_recorder as recorder
import operation_backend as shared
import operation_setup as setup
import operation_transport as t

transport = shared.transport


def partial_inventory(local, run_id, rows, identity):
    """Wrong observed values fail; absent expected identities remain pending."""
    require(set(identity) == {'application_id', 'service', 'source'} and
            all(isinstance(v, str) and v for v in identity.values()), 'missing backend identity')
    require(len({r['id'] for r in rows}) == len(rows), 'duplicated raw backend event')
    views = {v['view_id']: v for v in local['views']}
    work = {(w['kind'], w['event_id']): w for w in local['work']}
    seen_views, seen_work = set(), set()
    for row in rows:
        value = row.get('attributes', {}).get('custom', {})
        probe = value.get('context', {}).get('probe', {})
        require(value.get('application', {}).get('id') == identity['application_id']
                and value.get('service') == identity['service'] and value.get('source') == identity['source']
                and value.get('session', {}).get('id') == local['session_id'] and probe.get('run_id') == run_id,
                'foreign backend identity', 'FAIL')
        kind = value.get('type'); owner = value.get('view', {}).get('id')
        require(kind in {'view','action','resource','session','long_task','vital'}, 'backend error or unknown event', 'FAIL')
        if kind != 'session': require(owner in views, 'foreign observed backend owner', 'FAIL')
        if kind == 'view':
            require(owner not in seen_views and value['view'].get('name') == views[owner]['name'],
                    'duplicate or changed backend View', 'FAIL')
            seen_views.add(owner)
        elif kind in {'action','resource'}:
            key = (kind, value.get(kind, {}).get('id'))
            observed = dict(kind=kind, event_id=key[1], session_id=local['session_id'], view_id=owner,
                            phase=probe.get('phase'), source_scene=probe.get('source_scene'))
            require(key not in seen_work and work.get(key) == observed, 'wrong observed backend work owner or identity', 'FAIL')
            seen_work.add(key)
    if seen_views != set(views) or seen_work != set(work):
        raise Rejected('backend expected View/work identities are not all indexed', 'PENDING')
    return contract.validate_backend(local, run_id, rows, len(rows), identity=identity)


class Backend:
    """One immutable local capture, fixed query dates and bounded indexing polls."""
    def __init__(self, capture, folder, identity, *, deadline, maximum_attempts, poll_seconds,
                 notify=shared.notify_request, wait=time.sleep):
        self.capture, self.folder = Path(capture), Path(folder)
        raw, result = recorder.verified(self.capture)
        require(not self.folder.exists(), 'focus backend output already consumed')
        require(setup.finite(deadline) and time.time() < deadline <= time.time() + transport.MAX_BUDGET_SECONDS,
                'backend cutoff unavailable')
        require(type(maximum_attempts) is int and 1 <= maximum_attempts <= 24
                and setup.finite(poll_seconds) and 0 < poll_seconds <= 60, 'unbounded indexing policy')
        require(t.identifier(identity.get('application_id')) and t.identifier(result['local']['session_id']),
                'backend query identity invalid')
        require(set(identity) == {'application_id','service','source'} and identity['source'] == 'ios'
                and isinstance(identity['service'],str) and identity['service'], 'backend source/service missing')
        self.folder.mkdir(); transport.preflight(self.folder)
        self.source = {str(self.capture/n): setup.file_sha(self.capture/n) for n in ['definition.json','raw.jsonl','result.json']}
        self.definition = dict(capture=self.source, identity=dict(identity), run_id=result['run_id'],
            query='@application.id:'+identity['application_id']+' @session.id:'+result['local']['session_id'],
            interval=shared.query_interval(raw,result['cutoff_bytes']), deadline=deadline,
            maximum_attempts=maximum_attempts, poll_seconds=poll_seconds,
            minimum_rows=0, expected_identity_rows=len(result['local']['views'])+len(result['local']['work']),
            native_admission=False, cleanup='PENDING', overall='UNQUALIFIED')
        self.raw_definition = t.encode(self.definition); t.save(self.folder/'definition.json', self.raw_definition)
        self.notify, self.wait, self.used = notify, wait, False

    def live(self):
        require(time.time() < self.definition['deadline'], 'original backend cutoff expired')
        require(t.encode(self.definition) == self.raw_definition
                and setup.read(self.folder/'definition.json') == self.raw_definition, 'backend definition changed')
        require(all(setup.file_sha(p) == h for p,h in self.source.items()), 'sealed focus source changed')
        return True

    def collect(self):
        require(not self.used, 'focus collector already consumed'); self.used = True
        requests = []
        try:
            _, captured = recorder.verified(self.capture); local = captured['local']; d = self.definition
            for attempt in range(1, d['maximum_attempts'] + 1):
                self.live()
                query_id = dict(run_id=str(uuid.uuid4()), nonce=str(uuid.uuid4()))
                request = transport.begin(self.folder, query_id, d['query'], d['interval']['start'],
                    d['interval']['end'], d['deadline'], minimum_rows=d['minimum_rows'])
                request_raw = setup.read(request); requests.append(str(request)); self.notify(request)
                try:
                    try: returned = transport.wait(request, process_live=self.live)
                    except Rejected as error:
                        if error.state != 'PENDING': raise
                        try: shared.saved_inventory(request, request_raw)
                        except Rejected as observed:
                            require(observed.state == 'PENDING', 'pending publication differs from original evidence')
                            raise
                        raise ValueError('pending callback replaced a complete inventory')
                    rows, bindings = shared.saved_inventory(request, request_raw)
                    require(rows == returned, 'returned rows replaced saved tool response')
                    joined = partial_inventory(local, d['run_id'], rows, d['identity'])
                except Rejected as error:
                    if error.state != 'PENDING': raise
                    self.live()
                    t.save(self.folder/f'pending-{attempt:02d}.json', t.encode(dict(state='PENDING', reason=str(error),
                        request_sha256=t.sha(request_raw), deadline=d['deadline'], at=time.time())))
                    require(attempt < d['maximum_attempts'] and time.time()+d['poll_seconds'] < d['deadline'],
                            'expected inventory incomplete within original budget')
                    self.wait(d['poll_seconds']); continue
                self.live()
                result = dict(state='BACKEND_FOCUS_OWNERSHIP_JOINED', ownership=joined, attempts=attempt,
                    requests=requests, inventory_bindings=bindings, deadline=d['deadline'], at=time.time(),
                    query_interval=d['interval'], capture=self.source, cleanup='PENDING', overall='UNQUALIFIED',
                    release_acceptance=False, teardown_authorized=False)
                t.save(self.folder/'result.json',t.encode(result)); self.live()
                return result
            raise ValueError('indexing poll bound exhausted')
        except Exception as error:
            t.save(self.folder/'failure.json', t.encode(dict(state=getattr(error,'state','INVALID'),
                reason=str(error), requests=requests, at=time.time(), deadline=self.definition['deadline'],
                scenario='UNCHANGED', evidence='UNQUALIFIED', cleanup='PENDING', teardown_authorized=False)))
            raise
