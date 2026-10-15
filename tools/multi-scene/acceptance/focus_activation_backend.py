"""Collect existing H04 telemetry with no native input or teardown authority."""
from pathlib import Path
import time
import uuid

from acceptance_common import Rejected, require
import focus_activation_inventory as inventory
import focus_activation_recorder as recorder
import operation_backend as shared
import operation_setup as setup
import operation_transport as t

transport = shared.transport


def partial_inventory(local, run_id, rows, identity):
    """Wrong observed values fail; absent expected identities remain pending."""
    try:
        result = inventory.validate(local, run_id, rows, len(rows), identity=identity, partial=True)
    except ValueError as error:
        raise Rejected(str(error), "FAIL") from error
    if result["state"] == "PENDING":
        raise Rejected("backend expected View/work identities are not all indexed", "PENDING")
    return result


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
