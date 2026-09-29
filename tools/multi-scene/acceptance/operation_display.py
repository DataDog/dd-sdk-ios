"""H06 host pixel preparation. Pixel checks never grant native/SDK acceptance."""
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import time
import uuid

MAX_BYTES = 512 * 1024 * 1024
MAX_FRAMES_BYTES = 128 * 1024 * 1024
MAX_FRAMES = 36000
SCENES = ('scene-A', 'scene-B')
PHASES = ('START', 'RUN', 'FINAL')


class Rejected(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise Rejected(message)


def sha(path):
    path = Path(path)
    require(path.is_file() and not path.is_symlink(), 'missing or symlinked artifact')
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(65536), b''):
            digest.update(chunk)
    return digest.hexdigest()


def read(path, maximum):
    path = Path(path)
    require(path.is_file() and not path.is_symlink(), 'missing or symlinked artifact')
    with path.open('rb') as source:
        raw = source.read(maximum + 1)
    require(len(raw) <= maximum, 'oversized artifact')
    return raw


def save(path, value):
    with Path(path).open('x') as output:
        json.dump(value, output, sort_keys=True, allow_nan=False)
        output.write('\n')


def reference(path):
    return dict(path=str(Path(path).resolve()), sha256=sha(path))


def identity(run_id, nonce, owners):
    require(all(isinstance(v, str) and str(uuid.UUID(v)) == v for v in [run_id, nonce]),
            'invalid display run or nonce')
    require(isinstance(owners, dict) and set(owners) == set(SCENES)
            and all(isinstance(v, str) and re.fullmatch('[0-9a-f]{64}', v) for v in owners.values())
            and len(set(owners.values())) == 2, 'missing or aliased display bindings')
    return dict(run_id=run_id, nonce=nonce, owners=dict(owners))


def marker(binding, scene, phase=None):
    require(scene in SCENES and (phase is None or phase in PHASES), 'invalid marker')
    return '|'.join(['DDH06', '1', binding['run_id'], binding['nonce'], scene,
                     binding['owners'][scene], phase or 'OWNER'])


def inventory(frame, binding):
    """Identity joins only; Swift owns raw numeric pixel conversion/geometry."""
    require(frame.get('geometryValid') is True, 'invalid or overlapping barcode regions')
    observations = frame.get('observations')
    require(isinstance(observations, list) and 2 <= len(observations) <= 4, 'marker inventory incomplete')
    table = {marker(binding, scene, phase): (scene, phase) for scene in SCENES
             for phase in [None, *PHASES]}
    owners, phases = set(), {}
    for row in observations:
        require(isinstance(row, dict) and isinstance(row.get('payload'), str) and row['payload'] in table,
                'foreign, missing or undecodable marker payload')
        scene, phase = table[row['payload']]
        if phase is None:
            require(scene not in owners, 'duplicate owner marker')
            owners.add(scene)
        else:
            require(scene not in phases, 'duplicate phase marker')
            phases[scene] = phase
    require(owners == set(SCENES), 'owned window marker missing')
    return tuple(phases.get(scene) for scene in SCENES)


def interval(frames, binding):
    """Classify every recorded sample through FINAL, without duration thresholds."""
    identity(binding['run_id'], binding['nonce'], binding['owners'])
    start = None
    for index, frame in enumerate(frames):
        try:
            phases = inventory(frame, binding)
        except Rejected:
            continue  # Retained pre-START recording; never interval evidence.
        require(not any(phase in ('RUN', 'FINAL') for phase in phases), 'phase precedes START anchor')
        if phases == ('START', 'START'):
            start = index
            break
    require(start is not None, 'complete START anchor missing')
    last = ['START', 'START']; gaps = [[], []]
    transitions = []; run = None
    for index in range(start, len(frames)):
        phases = inventory(frames[index], binding)
        for owner, phase in enumerate(phases):
            if phase is None:
                gaps[owner].append(index)
                continue
            before, after = PHASES.index(last[owner]), PHASES.index(phase)
            require(before <= after <= before + 1, 'phase skipped or regressed')
            require(phase != 'FINAL' or run is not None, 'FINAL before complete RUN anchor')
            if gaps[owner]:
                require(after == before + 1, 'missing phase outside a rendering transition')
                transitions.append(dict(scene=SCENES[owner], frames=gaps[owner], before=last[owner], after=phase))
                gaps[owner] = []
            last[owner] = phase
        if phases == ('RUN', 'RUN') and run is None:
            run = index
        if phases == ('FINAL', 'FINAL'):
            require(run is not None, 'RUN anchor missing')
            return dict(state='PIXEL_INTERVAL_CHECKED', start_frame=start, run_frame=run, final_frame=index,
                        interval_frames=index - start + 1, retained_prefix_frames=start,
                        retained_tail_frames=len(frames) - index - 1, transition_frames=transitions,
                        native_acceptance=False, gates_closed=[])
    raise Rejected('complete FINAL anchor missing')


def receipt(folder, kind):
    """Reject failed, partial, replaced or non-presentational decoder output."""
    folder = Path(folder)
    value = json.loads(read(folder / 'decoder.json', 65536))
    require(value.get('schemaVersion') == 1 and value.get('state') == 'DECODED'
            and value.get('nativeAcceptance') is False and value.get('kind') == kind
            and value.get('readerState') == 'completed' and value.get('revision') == 3,
            'decoder did not finalize the requested media')
    raw = read(folder / 'frames.jsonl', MAX_FRAMES_BYTES)
    require(raw.endswith(b'\n') and hashlib.sha256(raw).hexdigest() == value.get('framesSHA256'),
            'partial or changed frame stream')
    frames = [json.loads(row) for row in raw.splitlines()]
    require(type(value.get('frameCount')) is int and len(frames) == value['frameCount']
            and 0 < len(frames) <= MAX_FRAMES, 'incomplete frame inventory')
    previous = None
    for index, frame in enumerate(frames):
        require(type(frame.get('index')) is int and frame['index'] == index
                and all(type(frame.get(k)) is int and 0 < frame[k] <= 8192 for k in ['width', 'height']),
                'frame index or dimensions invalid')
        if kind == 'MOVIE':
            pts = frame.get('pts')
            require(isinstance(pts, dict) and set(pts) == {'value', 'timescale', 'epoch', 'flags'}
                    and all(type(v) is int for v in pts.values()) and 0 < pts['timescale'] < 2 ** 31
                    and -(2 ** 63) <= pts['value'] < 2 ** 63 and -(2 ** 63) <= pts['epoch'] < 2 ** 63
                    and pts['flags'] in (1, 3), 'invalid presentation time')
            if previous:
                require(pts['epoch'] == previous['epoch']
                        and pts['value'] * previous['timescale'] >= previous['value'] * pts['timescale'],
                        'presentation time regressed')
            previous = pts
        else:
            require('pts' not in frame, 'image receipt contains movie sample time')
    if kind == 'MOVIE':
        require(value.get('trackCount') == 1 and value.get('decodedOutput') is True
                and value.get('pixelFormat') == 1111970369, 'unqualified video decoding mode')
    else:
        require(len(frames) == 1, 'screenshot is not one image')
    return value, frames


def decode(binary, expected_binary_sha, kind, source, folder, timeout, *, source_sha256):
    """Freeze the actual input before an independently bounded decoder process."""
    require(kind in ('IMAGE', 'MOVIE') and type(timeout) in (int, float) and math.isfinite(timeout)
            and 0 < timeout <= 1800, 'invalid decoder kind or resource budget')
    binary, source, folder = Path(binary).absolute(), Path(source).absolute(), Path(folder).absolute()
    codec_source = Path(__file__).with_suffix('.swift')
    require(sha(binary) == expected_binary_sha and sha(codec_source) == source_sha256,
            'decoder executable or source changed')
    require(source.is_file() and not source.is_symlink() and 0 < source.stat().st_size <= MAX_BYTES,
            'invalid or oversized media')
    folder.mkdir(parents=False, exist_ok=False)
    raw = folder / ('raw' + source.suffix)
    copied = 0
    with source.open('rb') as src, raw.open('xb') as dst:
        for block in iter(lambda: src.read(65536), b''):
            copied += len(block)
            require(copied <= MAX_BYTES, 'media grew beyond resource limit')
            dst.write(block)
    require(copied > 0 and sha(source) == sha(raw), 'media changed while freezing')
    argv = [str(binary), kind.lower(), str(raw), str(folder / 'decoded')]
    invocation = dict(argv=argv, source=reference(source), raw=reference(raw), binary=reference(binary),
                      decoder_source=reference(codec_source),
                      resource_timeout=timeout, started_at=time.time(), native_acceptance=False)
    save(folder / 'invocation.json', invocation)
    try:
        result = subprocess.run(argv, capture_output=True, check=False, timeout=timeout)
        observed = dict(returncode=result.returncode, stdout=result.stdout.decode(errors='replace'),
                        stderr=result.stderr.decode(errors='replace'), timed_out=False)
    except subprocess.TimeoutExpired as error:
        observed = dict(returncode=None, stdout=(error.stdout or b'').decode(errors='replace'),
                        stderr=(error.stderr or b'').decode(errors='replace'), timed_out=True)
    except OSError as error:
        observed = dict(returncode=None, stdout='', stderr=str(error), timed_out=False)
    observed['finished_at'] = time.time()
    save(folder / 'process.json', observed)
    require(observed['returncode'] == 0 and not observed['timed_out'], 'decoder failed or exceeded resource budget')
    require(sha(binary) == expected_binary_sha and sha(codec_source) == source_sha256
            and sha(raw) == invocation['raw']['sha256'],
            'decoder or pinned media changed')
    value, _ = receipt(folder / 'decoded', kind)
    require(value['inputSHA256'] == invocation['raw']['sha256'], 'decoder used different media')
    manifest = dict(schema_version=1, kind=kind, decoder_source=reference(codec_source), executable=reference(binary),
                    invocation=reference(folder/'invocation.json'), process=reference(folder/'process.json'),
                    raw=reference(raw), decoder=reference(folder/'decoded/decoder.json'),
                    frames=reference(folder/'decoded/frames.jsonl'), native_acceptance=False)
    save(folder/'manifest.json', manifest)
    return reference(folder/'manifest.json')


def verified_ref(value, maximum=None):
    require(isinstance(value, dict) and set(value) == {'path', 'sha256'}
            and isinstance(value['path'], str) and Path(value['path']).is_absolute()
            and isinstance(value['sha256'], str) and re.fullmatch('[0-9a-f]{64}', value['sha256']),
            'malformed artifact reference')
    if maximum is None:
        require(sha(value['path']) == value['sha256'], 'saved artifact changed')
        return None
    raw = read(value['path'], maximum)
    require(hashlib.sha256(raw).hexdigest() == value['sha256'], 'saved artifact changed')
    return raw


def checked(proof, kind):
    """Consume a hash-pinned immutable manifest, not an unbound output folder."""
    manifest = json.loads(verified_ref(proof, 65536))
    folder = Path(proof['path']).parent
    require(Path(proof['path']).name == 'manifest.json' and manifest.get('schema_version') == 1
            and manifest.get('kind') == kind and manifest.get('native_acceptance') is False,
            'wrong decoder manifest')
    for key, name in [('invocation','invocation.json'), ('process','process.json'),
                      ('decoder','decoded/decoder.json'), ('frames','decoded/frames.jsonl')]:
        require(manifest[key]['path'] == str(folder/name), 'manifest artifact path differs')
    require(Path(manifest['raw']['path']).parent == folder, 'raw media escaped manifest folder')
    for key in ['decoder_source', 'executable', 'raw', 'decoder', 'frames']:
        verified_ref(manifest[key])
    invocation = json.loads(verified_ref(manifest['invocation'], 65536))
    process = json.loads(verified_ref(manifest['process'], 65536))
    require(invocation.get('binary') == manifest['executable']
            and invocation.get('decoder_source') == manifest['decoder_source']
            and invocation.get('raw') == manifest['raw']
            and invocation.get('argv') == [manifest['executable']['path'], kind.lower(),
                                         manifest['raw']['path'], str(folder/'decoded')],
            'decoder invocation identity differs')
    require(process.get('returncode') == 0 and process.get('timed_out') is False,
            'media process failed or unfinished')
    value, frames = receipt(folder/'decoded', kind)
    require(value.get('inputSHA256') == manifest['raw']['sha256'], 'receipt refers to different saved media')
    return frames


def assess(movie, anchors, binding, output):
    require(set(anchors) == set(PHASES), 'independent START/RUN/FINAL screenshots required')
    result = interval(checked(movie, 'MOVIE'), binding)
    paths = [movie['path'], *[anchors[p]['path'] for p in PHASES]]
    require(len(set(paths)) == 4, 'media/anchor evidence reused')
    for phase in PHASES:
        frames = checked(anchors[phase], 'IMAGE')
        require(inventory(frames[0], binding) == (phase, phase), 'screenshot phase does not match anchor')
    result.update(binding=binding, movie=movie, screenshots=anchors,
                  tail_scope='All samples after the first complete FINAL are retained but excluded. Native causality must prove no critical work occurs there.',
                  native_join='UNQUALIFIED: native owners, physical display mapping and causal admission are still required')
    save(output, result)
    return result
