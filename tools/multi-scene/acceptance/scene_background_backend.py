"""Join a sealed H10 capture to backend evidence without native authority."""
import ast
from pathlib import Path
import sys
import time
import uuid

from acceptance_common import Rejected, require
import scene_background_capture as capture
import scene_background_cycle as cycle
import scene_background_protocol as protocol
import operation_backend as shared
import operation_setup as setup
import operation_transport as t

transport = shared.transport


def helper_sources():
    """Freeze the loaded local import closure used by these verifiers."""
    root = Path(__file__).resolve().parents[1]
    modules = {name: Path(module.__file__).resolve() for name, module in tuple(sys.modules.items())
               if getattr(module, '__file__', None) and not name.startswith('test_')
               and Path(module.__file__).suffix == '.py'
               and Path(module.__file__).resolve().is_relative_to(root)}
    pending = [Path(__file__).resolve()]
    result = {}
    while pending:
        path = pending.pop()
        if str(path) in result: continue
        raw = setup.read(path, maximum=capture.MAXIMUM_BYTES)
        result[str(path)] = t.sha(raw)
        for node in ast.walk(ast.parse(raw)):
            names = [a.name for a in node.names] if isinstance(node, ast.Import) else \
                [node.module] if isinstance(node, ast.ImportFrom) and node.level == 0 else []
            pending.extend(modules[name] for name in names if name in modules)
    return result


def sealed_inputs(directory, reference, identity, challenge):
    protocol.identity(identity)
    protocol.challenge(t.encode(challenge), identity, 3, challenge.get('consumedPhaseReplies', []))
    value = capture.validate_seal(directory, reference, identity=identity, challenge=challenge,
        oracle_source_sha256=setup.file_sha(cycle.__file__))
    seal = t.load(capture.read_reference(directory, reference), maximum=capture.MAXIMUM_BYTES)
    fresh = capture.read_capture(directory, seal['fresh'], identity)
    # Preserve actual signal bytes; the wrapper is only the existing interval reader's format.
    raw = b''.join(b'{"type":"signal","signal":' + row + b'}\n' for row in fresh['raw_signals'])
    interval = shared.query_interval(raw, len(raw))
    artifacts = {str(Path(directory)/r['name']): t.sha(capture.read_reference(directory, r))
                 for r in [reference, seal['inspected'], seal['fresh'], seal['extensionRows']]}
    return dict(identity=identity, seal_reference=reference, challenge=challenge, local=value['local'],
                interval=interval, artifacts=artifacts)


def partial_inventory(local, run_id, rows, identity):
    """Missing expected rows are pending; wrong observed ownership fails immediately."""
    require(set(identity) == {'application_id', 'service', 'source'}
            and all(isinstance(v, str) and v for v in identity.values()), 'missing backend identity')
    require(len({r['id'] for r in rows}) == len(rows), 'duplicate backend event', 'FAIL')
    views = {v['view_id']: v for v in local['views']}
    work = {(w['kind'], w['event_id']): w for w in local['work']}
    seen_views, seen_work = set(), set()
    for row in rows:
        value = row.get('attributes', {}).get('custom', {})
        probe = value.get('context', {}).get('probe', {})
        require(value.get('application', {}).get('id') == identity['application_id']
                and value.get('service') == identity['service'] and value.get('source') == identity['source']
                and value.get('session', {}).get('id') == local['session_id']
                and probe.get('run_id') == run_id, 'foreign backend identity', 'FAIL')
        kind, owner = value.get('type'), value.get('view', {}).get('id')
        require(kind in {'view', 'action', 'resource', 'session', 'long_task', 'vital'},
                'backend error or unknown event', 'FAIL')
        if kind != 'session': require(owner in views, 'foreign observed backend owner', 'FAIL')
        if kind == 'view':
            require(owner not in seen_views and value['view'].get('name') == views[owner]['name'],
                    'duplicate or changed backend View', 'FAIL')
            seen_views.add(owner)
        elif kind in {'action', 'resource'}:
            key = kind, value.get(kind, {}).get('id')
            observed = dict(kind=kind, event_id=key[1], session_id=local['session_id'], view_id=owner,
                            phase=probe.get('phase'), source_scene=probe.get('source_scene'))
            require(key not in seen_work and work.get(key) == observed,
                    'wrong observed backend work owner or identity', 'FAIL')
            seen_work.add(key)
    if seen_views != set(views) or seen_work != set(work):
        raise Rejected('expected H10 View/work identities are not all indexed', 'PENDING')
    return cycle.validate_backend(local, run_id, rows, len(rows), identity=identity)


def pending_observations(request, request_raw, local, run_id, identity):
    """A changing count cannot hide contradictions in actual retained pages."""
    response = request.with_name(request.name.replace('.request.json', '.response.json'))
    maximum = transport.MAX_RESPONSE * transport.PAGE_LIMIT
    raw = setup.read(response, maximum=maximum)
    try: shared.saved_inventory(request, request_raw)
    except Rejected as observed:
        require(observed.state == 'PENDING', 'pending return differs from saved evidence')
    else: raise ValueError('pending return substituted a complete inventory')
    require(setup.read(response, maximum=maximum) == raw, 'pending response changed during verification')
    value = t.load(raw, maximum=maximum)
    rows = [row for page in value['pages'] for row in
            transport.raw_page(page['response'], allow_pagination=True, start_at=page['start_at'])[0]]
    try: partial_inventory(local, run_id, rows, identity)
    except Rejected as error:
        if error.state != 'PENDING': raise
    # Even all expected identities do not make a changing-count inventory complete.
    return dict(response=str(response), response_sha256=t.sha(raw), observed_rows=len(rows),
                observed_contradictions=False, complete_inventory=False)


class Backend:
    """Independent, fixed indexing budget over one immutable sealed capture."""
    def __init__(self, directory, reference, identity, challenge, folder, backend_identity, *,
                 deadline, maximum_attempts, poll_seconds, notify=shared.notify_request, wait=time.sleep):
        self.directory, self.folder = Path(directory), Path(folder)
        # Copy mutable caller inputs before establishing their frozen definition.
        self.reference, self.identity, self.challenge, self.backend_identity = \
            [t.load(t.encode(v)) for v in [reference, identity, challenge, backend_identity]]
        self.source = sealed_inputs(self.directory, self.reference, self.identity, self.challenge)
        require(not self.folder.exists(), 'H10 backend output already consumed')
        require(setup.finite(deadline) and time.time() < deadline <= time.time() + transport.MAX_BUDGET_SECONDS,
                'backend cutoff unavailable')
        require(type(maximum_attempts) is int and 1 <= maximum_attempts <= 24
                and setup.finite(poll_seconds) and 0 < poll_seconds <= 60, 'unbounded indexing policy')
        require(set(self.backend_identity) == {'application_id', 'service', 'source'}
                and t.identifier(self.backend_identity['application_id'])
                and isinstance(self.backend_identity['service'], str) and self.backend_identity['service']
                and self.backend_identity['source'] == 'ios'
                and t.identifier(self.source['local']['session_id']), 'backend query identity invalid')
        self.helpers = helper_sources()
        self.folder.mkdir(); transport.preflight(self.folder)
        self.definition = dict(source=self.source, helpers=self.helpers, backend_identity=self.backend_identity,
            query='@application.id:' + self.backend_identity['application_id']
                + ' @session.id:' + self.source['local']['session_id'],
            deadline=deadline, maximum_attempts=maximum_attempts, poll_seconds=poll_seconds,
            native_admitted=False, process_liveness_required=False, gates_closed=[])
        self.frozen = t.encode(self.definition); t.save(self.folder/'definition.json', self.frozen)
        self.notify, self.wait, self.used = notify, wait, False

    def live(self):
        require(t.encode(self.definition) == self.frozen
                and setup.read(self.folder/'definition.json', maximum=capture.MAXIMUM_BYTES) == self.frozen,
                'H10 backend definition changed')
        require(time.time() < self.definition['deadline'], 'original backend cutoff expired')
        require(all(setup.file_sha(p) == h for p, h in self.helpers.items()), 'H10 verifier source changed')
        require(all(setup.file_sha(p) == h for p, h in self.source['artifacts'].items()), 'sealed H10 source changed')
        return True

    def collect(self):
        require(not self.used, 'H10 collector already consumed'); self.used = True
        requests = []
        try:
            require(sealed_inputs(self.directory, self.reference, self.identity, self.challenge) == self.source,
                    'sealed H10 inputs changed')
            d = self.definition; local = self.source['local']; interval = self.source['interval']
            for attempt in range(1, d['maximum_attempts'] + 1):
                self.live()
                query_id = dict(run_id=str(uuid.uuid4()), nonce=str(uuid.uuid4()))
                request = transport.begin(self.folder, query_id, d['query'], interval['start'], interval['end'],
                                          d['deadline'], minimum_rows=0)
                request_raw = setup.read(request); requests.append(str(request)); self.notify(request)
                observations = None
                try:
                    try: returned = transport.wait(request, process_live=self.live)
                    except Rejected as error:
                        if error.state != 'PENDING': raise
                        observations = pending_observations(request, request_raw, local,
                                                           self.identity['runID'], self.backend_identity)
                        raise
                    rows, bindings = shared.saved_inventory(request, request_raw)
                    require(rows == returned, 'returned rows replaced saved tool response')
                    joined = partial_inventory(local, self.identity['runID'], rows, self.backend_identity)
                except Rejected as error:
                    if error.state != 'PENDING': raise
                    self.live()
                    t.save(self.folder/f'pending-{attempt:02d}.json', t.encode(dict(state='PENDING', reason=str(error),
                        request_sha256=t.sha(request_raw), observed_evidence=observations,
                        deadline=d['deadline'], at=time.time())))
                    require(attempt < d['maximum_attempts'] and time.time() + d['poll_seconds'] < d['deadline'],
                            'expected H10 inventory incomplete within original budget')
                    self.wait(d['poll_seconds']); continue
                self.live()
                result = dict(state='BACKEND_H10_OWNERSHIP_JOINED', ownership=joined, attempts=attempt,
                    requests=requests, inventory_bindings=bindings, deadline=d['deadline'], at=time.time(),
                    query_interval=interval, source=self.source, scenario='UNCHANGED', display='PENDING',
                    cleanup='PENDING', overall='UNQUALIFIED', release_acceptance=False,
                    teardown_authorized=False, gates_closed=[])
                t.save(self.folder/'result.json', t.encode(result)); self.live()
                return result
            raise ValueError('indexing poll bound exhausted')
        except Exception as error:
            positive = self.folder/'result.json'
            if positive.exists():
                # Keep prospective bytes as evidence, outside the accepted-result path.
                positive.rename(self.folder/'invalidated-result.json')
            t.save(self.folder/'failure.json', t.encode(dict(state=getattr(error, 'state', 'INVALID'),
                reason=str(error), requests=requests, at=time.time(), deadline=self.definition['deadline'],
                scenario='UNCHANGED', evidence='UNQUALIFIED', cleanup='PENDING',
                release_acceptance=False, teardown_authorized=False, gates_closed=[])))
            raise
