"""Durable, bounded F08 MCP transport. No native launch or input authority.

Retain each exact tool return before parsing. Native execution is independent of
backend indexing; every request uses its original fixed interval and deadline.
"""
import argparse
import base64
import datetime
import hashlib
import json
from pathlib import Path
import sys
import time
import uuid

from capture_io import atomic, encoded, bounded_read
from capture_contract import loads
from journey_contract import require
from app_journey_transport import raw_count, raw_page, pollable_inventory
from acceptance_common import Rejected

MAX_PART = 49_152
MAX_RESPONSE = 2_097_152
ROW_LIMIT = 2000
PAGE_LIMIT = 41


def sha(raw):return hashlib.sha256(raw).hexdigest()


def live(bound):
    require(time.time() < bound['deadline'], 'original backend deadline expired')


def preflight(directory):
    directory = Path(directory)
    require(directory.is_dir() and not any(p.is_symlink() for p in [directory, *directory.parents]), 'unprepared transport directory')
    probe = directory / ('.response-publication-' + uuid.uuid4().hex)
    raw = encoded({'schema_version': 1, 'publication': str(uuid.uuid4())})
    atomic(probe, raw)
    require(probe.read_bytes() == raw and loads(raw)['schema_version'] == 1, 'response publication unavailable')
    probe.unlink()
    return {'state': 'RESPONSE_PUBLICATION_READY', 'native_launches': 0}


def begin(directory, identity, query, start, end, deadline, *, minimum_rows=0):
    """Freeze the query interval once; a follow-up poll keeps these same dates."""
    directory = Path(directory)
    preflight(directory)
    for value in identity.values():require(str(uuid.UUID(value)) == value, 'invalid query identity')
    require(set(identity) == {'run_id', 'nonce'}, 'wrong query identity shape')
    dates = [datetime.datetime.fromisoformat(value.replace('Z', '+00:00')) for value in (start, end)]
    require(all(d.tzinfo for d in dates) and dates[0] < dates[1], 'query interval is not fixed UTC dates')
    require(isinstance(query, str) and query and 0 <= minimum_rows <= ROW_LIMIT, 'invalid backend request')
    issued = time.time()
    require(issued < deadline <= issued + 600, 'backend budget differs')
    key = str(uuid.uuid4())
    path = directory / (key + '.request.json')
    spool = directory / key
    spool.mkdir(mode=0o700)
    bound = dict(schema_version=1, request=dict(identity, query=query, **{'from':start, 'to':end}),
                 issued_at=issued, deadline=deadline, row_limit=ROW_LIMIT, page_limit=PAGE_LIMIT,
                 minimum_rows=minimum_rows)
    atomic(path, encoded(bound))
    live(bound)
    return path


def binding(path):
    path = Path(path).resolve(strict=True)
    require(path.name.endswith('.request.json'), 'foreign response target')
    bound = loads(bounded_read(path, 16_384))
    require(bound['schema_version'] == 1 and bound['row_limit'] == ROW_LIMIT and bound['page_limit'] == PAGE_LIMIT,
            'transport limits changed')
    folder = path.with_name(path.name.removesuffix('.request.json'))
    require(folder.is_dir() and not folder.is_symlink(), 'unprepared response spool')
    return bound, folder


def label_name(label):
    require(label == 'count' or len(label) == 7 and label.startswith('page') and label[4:].isdigit()
            and int(label[4:]) < PAGE_LIMIT, 'invalid response label')
    return label


def part(path, label, index, data):
    bound, folder = binding(path)
    label_name(label)
    require(type(index) is int and 0 <= index < (MAX_RESPONSE + MAX_PART - 1) // MAX_PART
            and isinstance(data, bytes) and 0 < len(data) <= MAX_PART, 'response part exceeds bound')
    require(not (folder / (label + '.raw.json')).exists(), 'response was already sealed')
    target = folder / (label + '.' + str(index).zfill(3) + '.part')
    atomic(target, data)
    # Late observations remain diagnostic bytes, never accepted evidence.
    live(bound)
    return dict(state='RESPONSE_PART_RETAINED', label=label, index=index, bytes=len(data), sha256=sha(data))


def seal(path, label, parts, digest):
    bound, folder = binding(path)
    label_name(label)
    files = sorted(folder.glob(label + '.*.part'))
    require(type(parts) is int and parts > 0 and len(files) == parts
            and [p.name for p in files] == [label + '.' + str(i).zfill(3) + '.part' for i in range(parts)],
            'response parts missing or reordered')
    raw = b''.join(bounded_read(p, MAX_PART) for p in files)
    require(len(raw) <= MAX_RESPONSE and sha(raw) == digest, 'actual tool return digest differs')
    target = folder / (label + '.raw.json')
    atomic(target, raw)
    receipt = dict(label=label, request_sha256=sha(Path(path).read_bytes()), received_at=time.time(),
                   raw_sha256=sha(raw), bytes=len(raw), state='INVALID')
    try:
        live(bound)
        response = loads(raw)
        if label == 'count':
            count = raw_count(response)
            require(count <= ROW_LIMIT, 'count exceeds frozen bound')
            receipt.update(state='COUNT_CAPTURED', count=count, pending=count < bound['minimum_rows'])
        else:
            rows, total = raw_page(response)
            require(total <= ROW_LIMIT and len(rows) <= ROW_LIMIT, 'page exceeds frozen bound')
            receipt.update(state='PAGE_CAPTURED', rows=len(rows), total=total)
        live(bound)
    except Exception as error:
        receipt['reason'] = str(error)
        raise
    finally:
        receipt['published_at'] = time.time()
        atomic(folder / (label + '.receipt.json'), encoded(receipt))
    live(bound)
    return receipt


def finish(path):
    bound, folder = binding(path)
    count_receipt = loads((folder / 'count.receipt.json').read_bytes())
    require(count_receipt['state'] == 'COUNT_CAPTURED', 'count not qualified')
    labels = sorted(p.name.removesuffix('.receipt.json') for p in folder.glob('page*.receipt.json'))
    require(labels == ['page' + str(i).zfill(3) for i in range(len(labels))] and len(labels) <= PAGE_LIMIT,
            'page publication gap')
    response = dict(request=bound['request'], count_response=loads((folder / 'count.raw.json').read_bytes()), pages=[])
    offset = 0
    for label in ['count', *labels]:
        receipt = loads((folder / (label + '.receipt.json')).read_bytes())
        raw = bounded_read(folder / (label + '.raw.json'), MAX_RESPONSE)
        require(receipt['raw_sha256'] == sha(raw) and receipt['request_sha256'] == sha(Path(path).read_bytes())
                and bound['issued_at'] <= receipt['received_at'] <= receipt['published_at'] < bound['deadline'],
                'foreign, changed or late response')
        if label != 'count':
            require(receipt['state'] == 'PAGE_CAPTURED', 'page not qualified')
            response['pages'].append(dict(start_at=offset, response=loads(raw)))
            offset += receipt['rows']
    if count_receipt['pending']:
        require(not labels, 'pages collected after pending count')
        response['count_pending'] = True
    state = 'COMPLETE_INVENTORY'
    try:
        live(bound)
        rows = pollable_inventory(response, bound['request'], row_limit=ROW_LIMIT, page_limit=PAGE_LIMIT,
                                  minimum_rows=bound['minimum_rows'])
    except Rejected as error:
        if error.state != 'PENDING':raise
        response['pending'] = str(error)
        rows = []
        state = 'PENDING'
    destination = Path(path).with_name(Path(path).name.replace('.request.json', '.response.json'))
    atomic(destination, encoded(response))
    live(bound)
    receipt = dict(state=state, rows=len(rows), published_at=time.time(), deadline=bound['deadline'],
                   response_sha256=sha(destination.read_bytes()), request_sha256=sha(Path(path).read_bytes()))
    atomic(folder / 'publication.json', encoded(receipt))
    live(bound)
    return receipt


def wait(path, *, process_live=lambda: True):
    bound, folder = binding(path)
    monotonic_end = time.monotonic() + max(0, bound['deadline'] - time.time())
    response_path = Path(path).with_name(Path(path).name.replace('.request.json', '.response.json'))
    while not (folder / 'publication.json').exists():
        live(bound)
        require(time.monotonic() < monotonic_end and process_live(), 'backend wait expired or owner exited')
        time.sleep(.1)
    live(bound)
    publication = loads((folder / 'publication.json').read_bytes())
    raw = bounded_read(response_path, MAX_RESPONSE * PAGE_LIMIT)
    require(publication['response_sha256'] == sha(raw) and publication['request_sha256'] == sha(Path(path).read_bytes())
            and publication['published_at'] < bound['deadline'], 'stale or late inventory publication')
    response = loads(raw)
    return pollable_inventory(response, bound['request'], row_limit=ROW_LIMIT, page_limit=PAGE_LIMIT,
                              minimum_rows=bound['minimum_rows'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['part', 'seal', 'finish'])
    parser.add_argument('--request', type=Path, required=True)
    parser.add_argument('--label')
    parser.add_argument('--index', type=int)
    parser.add_argument('--payload')
    parser.add_argument('--parts', type=int)
    parser.add_argument('--sha256')
    args = parser.parse_args()
    if args.operation == 'part':value = part(args.request, args.label, args.index, base64.b64decode(args.payload, validate=True))
    elif args.operation == 'seal':value = seal(args.request, args.label, args.parts, args.sha256)
    else:value = finish(args.request)
    print(json.dumps(value))


if __name__ == '__main__':main()
