"""Read-only baseline-matched orientation readiness for the local S2 continuation."""
import math
import copy
import json
from pathlib import Path
import struct
import sys
import time
import zlib

import physical_io as io
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'app-acceptance'))
from capture_io import atomic, encoded

shared = io.shared
require = io.require
KIND = 'BASELINE_MATCHED_PHYSICAL_SETUP_V1'


def reference(path):
    path = Path(path).resolve(strict=True)
    return dict(path=str(path), sha256=shared.sha(path))


def bound(record, *, json=True):
    path = Path(record['path'])
    require(path.is_file() and not path.is_symlink() and shared.sha(path) == record['sha256'],
            'changed physical setup evidence')
    return shared.read(path) if json else path.read_bytes()


def png_size(data):
    """Validate the actual RGB/RGBA screenshot, including its compressed pixels."""
    require(len(data) <= 32*1024*1024 and data[:8] == b'\x89PNG\r\n\x1a\n', 'invalid setup PNG')
    offset = 8; header = None; packed = bytearray(); ended = False
    while offset < len(data):
        require(offset+12 <= len(data), 'truncated setup PNG')
        size = struct.unpack('>I', data[offset:offset+4])[0]; tag = data[offset+4:offset+8]
        end = offset+12+size; require(end <= len(data), 'truncated setup PNG chunk')
        payload = data[offset+8:end-4]
        require(zlib.crc32(tag+payload) == struct.unpack('>I', data[end-4:end])[0], 'setup PNG checksum differs')
        if header is None:
            require(tag == b'IHDR' and size == 13, 'missing setup PNG header')
            header = struct.unpack('>IIBBBBB', payload)
            w, h, bits, color, compression, filtering, interlace = header
            require(0 < w <= 10000 and 0 < h <= 10000 and bits in [8, 16] and color in [2, 6]
                    and (compression, filtering, interlace) == (0, 0, 0), 'unsupported setup PNG')
        elif tag == b'IHDR':
            require(False, 'duplicate setup PNG header')
        if tag == b'IDAT': packed.extend(payload)
        if tag == b'IEND':
            require(size == 0 and end == len(data), 'invalid setup PNG end'); ended = True
        offset = end
    require(ended and packed, 'incomplete setup PNG')
    stride = w*(3 if color == 2 else 4)*(bits//8)+1; expected = stride*h
    require(expected <= 64*1024*1024, 'oversized setup PNG pixels')
    decoder = zlib.decompressobj()
    try: pixels = decoder.decompress(packed, expected+1)
    except zlib.error: require(False, 'invalid setup PNG pixels')
    require(len(pixels) == expected and decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail
            and all(pixels[n] <= 4 for n in range(0, expected, stride)), 'incomplete setup PNG pixels')
    return [w, h]


def pose(raw, device):
    value = io.display(raw, device)
    args = raw['info']['arguments']
    require(args.count('--device') == 1, 'ambiguous physical setup device')
    result = raw['result']; screen = result['displays'][0]; orientation = result.get('orientation', {})
    for numbers in [value['nativeSize'], value['bounds'][0], value['bounds'][1], [value['pointScale']]]:
        require(len(numbers) in [1, 2] and all(type(n) in [int, float] and math.isfinite(n) for n in numbers),
                'invalid physical setup coordinates')
    require(value['bounds'][0] == [0, 0] and all(n > 0 for n in value['bounds'][1]), 'invalid physical setup panel')
    require(screen.get('nativeOrientation') in ['rot0', 'rot90', 'rot180', 'rot270']
            and orientation.get('currentDeviceNonFlatOrientation') in
                ['portrait', 'portraitUpsideDown', 'landscapeLeft', 'landscapeRight']
            and type(orientation.get('currentDeviceOrientationLocked')) is bool, 'missing actual setup orientation')
    return dict(display=value, native_orientation=screen['nativeOrientation'],
                device_orientation=orientation['currentDeviceNonFlatOrientation'],
                orientation_locked=orientation['currentDeviceOrientationLocked'])


def baseline(basis, oracle):
    """Rejoin the accepted source snapshot; Home readiness cannot prove app ownership."""
    folder = basis['root']/'cells'/basis['pins']['cell']/'input'/'setup.detail.before'
    names = ['events.jsonl', 'writer-checkpoint.json', 'request.json', 'display.json', 'ready.png']
    refs = {name: reference(folder/name) for name in names}
    request = bound(refs['request.json']); run = basis['assessment']['source']['run_id']
    rows = oracle.checkpoint(bound(refs['events.jsonl'], json=False), bound(refs['writer-checkpoint.json']), run, request['request_id'])
    snapshot, binding = oracle.snapshot(rows, bound(refs['request.json'], json=False), run)
    scene, window = oracle.topology(snapshot['payload']['topology'], binding)
    actual = pose(bound(refs['display.json']), basis['plan']['device']); pixels = png_size(bound(refs['ready.png'], json=False))
    require(request['phase'] == 'setup.detail.before' and scene['orientation'] == 3
            and actual['device_orientation'] == 'landscapeLeft' and actual['display']['currentOrientation'] == 'rot0',
            'baseline landscape setup differs')
    scale = scene['screen_scale']
    require(scale == actual['display']['pointScale'] and pixels == actual['display']['bounds'][1]
            and all(math.isclose(n*scale, p, abs_tol=.01, rel_tol=0) for bounds in
                    [scene['screen_bounds'], scene['coordinate_bounds'], window['bounds']] for n, p in zip(bounds[2:], pixels)),
            'baseline owned scene/window/display axes disagree')
    return dict(kind=KIND, device=basis['plan']['device'], expected=actual, pixels=pixels, baseline=refs,
                scope='Setup orientation only; native scene/window and telemetry checks remain required.')


def validate(root, plan, now=None):
    """Rejoin raw one-use observations and receipts, rather than trusting a PASS label."""
    root = Path(root); proof = shared.read(root/'setup.json'); now = time.time() if now is None else now
    require(proof['kind'] == KIND and proof['plan_sha256'] == plan['plan_sha256'] and proof['device'] == plan['device']
            and proof['expected'] == plan['physical_setup'], 'foreign physical setup proof')
    require(Path(proof['admission']['path']) == root.resolve()/'admission.json', 'foreign setup admission')
    admission = bound(proof['admission'])
    require(admission == {k:proof[k] for k in ['kind','plan_sha256','device','expected','started_at','deadline']}
            and all(type(proof[k]) in [int,float] and math.isfinite(proof[k]) for k in ['started_at','finished_at','deadline'])
            and 0 < proof['deadline']-proof['started_at'] <= 120, 'setup original admission or budget differs')
    require(proof['started_at'] <= proof['finished_at'] < proof['deadline'] and 0 <= now-proof['finished_at'] < 300,
            'stale or late physical setup proof')
    image_ref = proof['image']; require(Path(image_ref['path']) == root.resolve()/'setup.png', 'foreign setup image')
    actuals = []; prior = proof['started_at']
    for name, command in [('before', 'info.displays'), ('image', 'capture.screenshot'), ('after', 'info.displays')]:
        entry = proof['observations'][name]; raw = bound(entry['response']); receipt = bound(entry['receipt'])
        actual = bound(entry['returned'])
        require(actual == dict(response=raw,receipt=receipt), 'setup files differ from actual returned observations')
        response_path = Path(entry['response']['path']); receipt_path = Path(entry['receipt']['path'])
        require(response_path.parent == receipt_path.parent and response_path.parent.parent == root.resolve()/'commands'
                and Path(entry['returned']['path']) == response_path.parent/'returned.json'
                and response_path.name == 'response.json' and receipt_path.name == 'receipt.json', 'foreign setup command record')
        require(receipt['returncode'] == 0 and receipt['before'] == receipt['remaining'] == []
                and receipt['quiescence_error'] is None and receipt['response_sha256'] == entry['response']['sha256']
                and prior <= receipt['started_at'] <= receipt['finished_at'] < receipt['deadline'] <= proof['deadline'],
                'unqualified physical setup command receipt')
        args = raw['info']['arguments']; require(args.count('--device') == 1, 'ambiguous setup device')
        result = io.returned(raw, plan['device'], 'devicectl.device.'+command)
        require(args.count('--json-output') == 1 and args[args.index('--json-output')+1] == str(response_path),
                'setup response publication differs')
        if name == 'image':
            require(args.count('--destination') == 1 and args[args.index('--destination')+1] == image_ref['path']
                    and result['destination'] == Path(image_ref['path']).as_uri() and result['deviceIdentifier'] == plan['device']
                    and result['imageFormat'] == 'png', 'foreign setup screenshot destination')
            pixels = png_size(bound(image_ref, json=False))
            require(pixels == [result['width'], result['height']], 'setup image and response disagree')
        else: actuals.append(pose(raw, plan['device']))
        prior = receipt['finished_at']
    require(0 <= now-prior < 300 and prior <= proof['finished_at']
            and actuals[0] == actuals[1] == plan['physical_setup']['expected']
            and pixels == plan['physical_setup']['pixels'], 'SETUP_NOT_READY: restore the saved landscapeLeft orientation before installation')
    require(proof['state'] == 'PASS', 'physical setup proof not qualified')
    return proof


def capture(root, plan, deadline):
    """Read display/image/display with fixed budgets; never activate or install an app."""
    root = Path(root).resolve(); require(not root.exists(), 'physical setup output already consumed'); root.mkdir()
    started = time.time(); require(started+1 < deadline <= started+120, 'physical setup budget expired or excessive')
    remote = io.Device(plan['device'], root/'commands'); observations = {}; image = root/'setup.png'
    proof = dict(kind=KIND, state='UNQUALIFIED', plan_sha256=plan['plan_sha256'], device=plan['device'],
                 expected=plan['physical_setup'], started_at=started, deadline=deadline, observations=observations)
    atomic(root/'admission.json',encoded({k:proof[k] for k in ['kind','plan_sha256','device','expected','started_at','deadline']}))
    proof['admission'] = reference(root/'admission.json')
    try:
        for name, args in [('before', ['device', 'info', 'displays']),
                           ('image', ['device', 'capture', 'screenshot', '--destination', str(image)]),
                           ('after', ['device', 'info', 'displays'])]:
            raw, receipt = remote.command(args, name, deadline, seconds=30)
            actual = copy.deepcopy(dict(response=raw,receipt=receipt))
            folder = remote.output/(str(remote.sequence).zfill(5)+'-'+name)
            response_bytes = (folder/'response.json').read_bytes(); receipt_bytes = (folder/'receipt.json').read_bytes()
            atomic(folder/'returned.json',encoded(actual))
            require(json.loads(response_bytes) == actual['response'] and json.loads(receipt_bytes) == actual['receipt']
                    and __import__('hashlib').sha256(response_bytes).hexdigest() == actual['receipt']['response_sha256'],
                    'setup publication replaced after actual tool return')
            observations[name] = dict(response=reference(folder/'response.json'), receipt=reference(folder/'receipt.json'),
                                      returned=reference(folder/'returned.json'))
            require((folder/'response.json').read_bytes() == response_bytes and (folder/'receipt.json').read_bytes() == receipt_bytes,
                    'setup publication changed while binding')
        proof.update(image=reference(image), finished_at=time.time(), state='PASS')
        atomic(root/'setup.json', encoded(proof)); validate(root, plan)
    except BaseException as error:
        proof.update(state='SETUP_NOT_READY', finished_at=time.time(), reason=str(error))
        atomic(root/'setup.json', encoded(proof), exclusive=False)
        raise
    return proof
