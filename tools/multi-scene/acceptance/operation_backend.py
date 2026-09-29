"""Join sealed H06 capture to complete backend evidence, without native work.

The independent display and cleanup verdicts remain pending. Delayed indexing
only repeats the same query interval; it never requests gestures or SDK calls.
"""
import datetime
import json
from pathlib import Path
import re
import sys
import time
import uuid

import operation_completion as completion
import operation_ownership as ownership
import operation_recorder as recorder_contract
import operation_setup as setup
import operation_transport as t
from acceptance_common import Rejected

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'app-acceptance'))
import journey_transport as transport


def query_interval(raw, cutoff):
    rows = [t.load(line) for line in raw[:cutoff].splitlines()]
    timestamps = [row['signal']['timestampMilliseconds'] for row in rows if row['type'] == 'signal']
    t.require(timestamps and all(type(v) is int and v >= 0 for v in timestamps), 'native query timestamps missing')
    # Padding is query coverage, not a latency or duration acceptance threshold.
    start, end = min(timestamps) / 1000 - 120, max(timestamps) / 1000 + 120
    utc = lambda value: datetime.datetime.fromtimestamp(value, datetime.timezone.utc).isoformat()
    return dict(start=utc(start), end=utc(end), minimumNativeMilliseconds=min(timestamps),
                maximumNativeMilliseconds=max(timestamps))


def sealed_source(recorder):
    local = recorder.local; documents = local.folder / 'documents'
    terminal_path = documents / (local.identity['runID'] + '.operations-' + completion.TERMINAL)
    terminal_raw = setup.read(terminal_path)
    joined = completion.validate_snapshot(documents, terminal_raw, identity=local.identity,
                                         publication=local.publication, deadline=local.channel.deadline)
    result_path = recorder.folder / 'result.json'; result_raw = setup.read(result_path); result = t.load(result_raw)
    t.require(isinstance(result.get('artifact'), str) and re.fullmatch(r'probe-[0-9]{6}\.jsonl', result['artifact']),
              'foreign recorder artifact path')
    raw_path = recorder.folder / result['artifact']; raw = setup.read(raw_path, maximum=recorder_contract.MAX_BYTES)
    validated = recorder_contract.validate_stream(raw, identity=local.identity, joined=joined, documents=documents)
    t.require(all(result.get(k) == v for k, v in validated.items()) and result['deadline'] == local.channel.deadline
              and setup.finite(result['finishedAt']) and result['finishedAt'] < result['deadline'],
              'recorder result differs from sealed evidence')
    local_path = local.folder / 'result.json'; local_result = t.load(setup.read(local_path))
    inventory_path = local.folder / 'sealed-inventory.json'
    t.require(local_result['state'] == 'LOCAL_EVIDENCE_COLLECTED' and local_result['identity'] == local.identity
              and local_result['deadline'] == local.channel.deadline and local_result['terminalSHA256'] == t.sha(terminal_raw)
              and local_result['inventorySHA256'] == setup.file_sha(inventory_path)
              and t.load(setup.read(inventory_path)) == joined['inventory'], 'native collector result differs')
    publication_folder = local.host.folder / 'publication'
    publication_path = publication_folder / ('host-publication-' + t.sha(local.publication) + '.json')
    t.require(setup.read(publication_path) == local.publication, 'original host publication changed')
    paths = [result_path, raw_path, local_path, inventory_path, publication_path, publication_folder / 'result.json']
    paths += [documents / name for name in joined['inventory']]
    return dict(identity=t.load(t.encode(local.identity)), backendInputs=validated['backendInputs'],
        interval=query_interval(raw, validated['cutoffBytes']), artifacts={str(p): setup.file_sha(p) for p in paths})


def saved_inventory(request, request_raw):
    """Rejoin the actual publication to its original count/page tool returns."""
    t.require(setup.read(request) == request_raw, 'backend request changed after publication')
    bound, folder = transport.binding(request)
    publication_path = folder / 'publication.json'; publication = t.load(setup.read(publication_path))
    response_path = request.with_name(request.name.replace('.request.json', '.response.json'))
    response_raw = setup.read(response_path, maximum=transport.MAX_RESPONSE * transport.PAGE_LIMIT)
    response = t.load(response_raw, maximum=transport.MAX_RESPONSE * transport.PAGE_LIMIT)
    t.require(publication['state'] in {'COMPLETE_INVENTORY', 'PENDING', 'INVALID'}
              and publication['request_sha256'] == t.sha(request_raw)
              and publication['response_sha256'] == t.sha(response_raw) and publication['deadline'] == bound['deadline']
              and setup.finite(publication['published_at'])
              and bound['issued_at'] <= publication['published_at'] < bound['deadline'], 'foreign or late backend publication')
    labels = sorted(p.name.removesuffix('.receipt.json') for p in folder.glob('page*.receipt.json'))
    t.require(labels == ['page' + str(i).zfill(3) for i in range(len(labels))]
              and len(labels) == len(response['pages']) <= transport.PAGE_LIMIT, 'backend page publication gap')
    paths = [request, publication_path, response_path]
    for index, label in enumerate(['count', *labels]):
        raw_path = folder / (label + '.raw.json'); raw = setup.read(raw_path, maximum=transport.MAX_RESPONSE)
        receipt_path = folder / (label + '.receipt.json'); receipt = t.load(setup.read(receipt_path))
        t.require(receipt['state'] == ('COUNT_CAPTURED' if label == 'count' else 'PAGE_CAPTURED')
                  and receipt['request_sha256'] == t.sha(request_raw) and receipt['raw_sha256'] == t.sha(raw)
                  and all(setup.finite(receipt[k]) for k in ['received_at', 'published_at'])
                  and bound['issued_at'] <= receipt['received_at'] <= receipt['published_at'] <= publication['published_at'],
                  'backend raw response receipt differs')
        actual = response['count_response'] if label == 'count' else response['pages'][index - 1]['response']
        t.require(t.load(raw, maximum=transport.MAX_RESPONSE) == actual, 'backend response replaced original tool return')
        if label != 'count':
            t.require(receipt['start_at'] == response['pages'][index - 1]['start_at'], 'backend receipt offset differs')
        paths += [raw_path, receipt_path]
    try:
        rows = transport.pollable_inventory(response, bound['request'], row_limit=transport.ROW_LIMIT,
            page_limit=transport.PAGE_LIMIT, minimum_rows=bound['minimum_rows'], allow_pagination=True)
    except Rejected as error:
        t.require(publication['state'] == ('PENDING' if error.state == 'PENDING' else 'INVALID'),
                  'backend rejection differs from saved publication state')
        raise
    t.require(publication['state'] == 'COMPLETE_INVENTORY' and publication['rows'] == len(rows),
              'backend publication does not prove complete inventory')
    return rows, {str(p): setup.file_sha(p) for p in paths}


def notify_request(path):
    print(json.dumps(dict(backend_request=str(path))), flush=True)


class Backend:
    """One sealed capture, fixed dates/cutoff, fresh transport identity per poll."""
    def __init__(self, recorder, *, deadline, maximum_attempts, poll_seconds,
                 notify=notify_request, wait=time.sleep):
        self.recorder = recorder; self.local = recorder.local
        self.original_deadline = self.local.channel.deadline; self.deadline = deadline
        t.require(setup.finite(deadline) and time.time() < deadline <= self.original_deadline
                  and deadline <= time.time() + transport.MAX_BUDGET_SECONDS, 'backend cutoff outside original budget')
        t.require(type(maximum_attempts) is int and 1 <= maximum_attempts <= 24
                  and setup.finite(poll_seconds) and 0 < poll_seconds <= 60, 'unbounded backend polling')
        self.maximum_attempts, self.poll_seconds = maximum_attempts, poll_seconds
        self.notify, self.wait, self.used = notify, wait, False
        self.source = sealed_source(recorder)
        owners = self.source['backendInputs']
        self.query = '@application.id:' + owners['application_id'] + ' @session.id:' + owners['session_id'] + \
            ' (@type:operation OR @vital.type:operation_step)'
        self.folder = recorder.folder / 'backend'; self.folder.mkdir()
        transport.preflight(self.folder)
        self.definition = dict(source=self.source, query=self.query, deadline=deadline, originalDeadline=self.original_deadline,
            maximumAttempts=maximum_attempts, pollSeconds=poll_seconds, expectedRows=12, nativeWorkAdmitted=False,
            processLivenessRequired=False, display='PENDING', cleanup='PENDING', overall='UNQUALIFIED')
        self.definition_raw = t.encode(self.definition); t.save(self.folder / 'definition.json', self.definition_raw)

    def live(self):
        t.require(time.time() < self.deadline, 'original backend cutoff expired')
        t.require(self.deadline == self.definition['deadline']
                  and self.local.channel.deadline == self.original_deadline
                  and self.local.channel.identity == self.source['identity'] == self.local.identity
                  and self.maximum_attempts == self.definition['maximumAttempts']
                  and self.poll_seconds == self.definition['pollSeconds'] and self.query == self.definition['query']
                  and setup.read(self.folder / 'definition.json') == self.definition_raw,
                  'backend identity, limits or definition changed')
        return True

    def check_source(self):
        self.live()
        t.require(sealed_source(self.recorder) == self.source, 'sealed native source changed during backend collection')
        self.live()

    def collect(self):
        t.require(not self.used, 'backend collector already consumed'); self.used = True
        requests = []
        try:
            for attempt in range(1, self.maximum_attempts + 1):
                self.check_source()
                identity = dict(run_id=str(uuid.uuid4()), nonce=str(uuid.uuid4()))
                interval = self.source['interval']
                request = transport.begin(self.folder, identity, self.query, interval['start'], interval['end'],
                                          self.deadline, minimum_rows=12)
                request_raw = setup.read(request); requests.append(str(request))
                t.save(self.folder / f'attempt-{attempt:02d}.json', t.encode(dict(nativeIdentity=self.source['identity'],
                    request=str(request), requestSHA256=t.sha(request_raw), transportIdentity=identity,
                    deadline=self.deadline)))
                self.notify(request)
                try:
                    returned = transport.wait(request, process_live=self.live)
                except Rejected as error:
                    if error.state != 'PENDING': raise
                    # Do not treat an arbitrary callback's PENDING as an actual
                    # index observation: decode the saved original publication.
                    try: saved_inventory(request, request_raw)
                    except Rejected as observed:
                        t.require(observed.state == 'PENDING', 'backend pending return differs from saved evidence')
                    else: raise ValueError('backend pending return substituted a complete inventory')
                    self.check_source()
                    t.save(self.folder / f'pending-{attempt:02d}.json', t.encode(dict(state='PENDING', reason=str(error),
                        requestSHA256=t.sha(request_raw), deadline=self.deadline, finishedAt=time.time())))
                    t.require(attempt < self.maximum_attempts and time.time() + self.poll_seconds < self.deadline,
                              'backend inventory incomplete within original budget')
                    self.wait(self.poll_seconds)
                    continue
                rows, bindings = saved_inventory(request, request_raw)
                t.require(returned == rows, 'backend return substituted saved inventory')
                self.check_source()
                joined = ownership.validate(rows, count=len(rows), **self.source['backendInputs'])
                self.live()
                result = dict(state='BACKEND_OWNERSHIP_JOINED', ownership=joined, identity=self.source['identity'],
                    sourceSHA256=t.sha(t.encode(self.source)), requests=requests, inventoryBindings=bindings,
                    queryInterval=self.source['interval'], attempts=attempt, deadline=self.deadline, finishedAt=time.time(),
                    scenario='UNCHANGED', display='PENDING', cleanup='PENDING', overall='UNQUALIFIED',
                    releaseAcceptance=False, teardownAuthorized=False)
                t.save(self.folder / 'result.json', t.encode(result)); self.live()
                return result
        except Exception as error:
            t.save(self.folder / 'failure.json', t.encode(dict(state=getattr(error, 'state', 'INVALID'),
                reason=str(error), errorType=type(error).__name__, deadline=self.deadline, finishedAt=time.time(),
                requests=requests, scenario='UNCHANGED', evidence='UNQUALIFIED', cleanup='PENDING',
                releaseAcceptance=False, teardownAuthorized=False)))
            raise
