"""Passive full-display readiness; geometry is a hint, never ownership evidence."""
import copy
import hashlib
import json
import math
import time


def require(condition, message):
    if not condition:
        raise ValueError('fold readiness: ' + message)


def positive(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def display_signature(display):
    require(isinstance(display.get('uniqueId'), str) and display['uniqueId']
            and display.get('active') is True and type(display.get('primary')) is bool,
            'actual active display identity missing')
    size = display.get('nativeSize')
    require(type(size) is list and len(size) == 2 and all(positive(n) for n in size)
            and positive(display.get('pointScale'))
            and display.get('currentOrientation') in ('rot0', 'rot90', 'rot180', 'rot270'),
            'actual display geometry invalid')
    return (display['uniqueId'], tuple(size), display['currentOrientation'],
            display['pointScale'], display['primary'])


def matches(size, scale, display):
    display_signature(display)
    require(type(size) is list and len(size) == 2 and all(positive(n) for n in size)
            and positive(scale), 'native geometry invalid')
    pixels = display['nativeSize']
    if display['currentOrientation'] in ('rot90', 'rot270'):
        pixels = pixels[::-1]
    # Coordinates are points. Accept serialization roundoff within half a pixel.
    return (abs(scale - display['pointScale']) <= .0001
            and all(abs(a * scale - b) <= .5 for a, b in zip(size, pixels)))


class Readiness:
    def __init__(self, *, prefix, before_sequence, run, binding, display):
        self.run, self.binding = run, copy.deepcopy(binding)
        self.display = copy.deepcopy(display)
        self.signature = display_signature(display)
        self.prefix = b''
        self.boundary = before_sequence
        self.hint = None
        self.consumed = False
        rows = self.stream(prefix)
        require(rows and rows[-1]['sequence'] >= before_sequence
                and any(r['sequence'] == before_sequence and r['kind'] == 'human_snapshot'
                        for r in rows), 'validated pre-fold snapshot absent')
        self.boundary = rows[-1]['sequence']

    def stream(self, raw):
        require(type(raw) is bytes and raw.startswith(self.prefix), 'native prefix replaced or truncated')
        complete = raw[:raw.rfind(b'\n') + 1]
        rows = [json.loads(line) for line in complete.splitlines()]
        require(rows and all(r.get('run_id') == self.run for r in rows), 'foreign or restored native run')
        require(all(type(r.get('sequence')) is int and r['sequence'] == i
                    for i, r in enumerate(rows, 1)), 'missing or reordered native sequence')
        require(len([r for r in rows if r['kind'] == 'launch']) == 1, 'missing or duplicate launch')
        bindings = [r['payload'] for r in rows if r['kind'] == 'human_window_binding']
        require(bindings == [self.binding], 'native ownership binding changed')
        require(not any(r['kind'] == 'human_failure' for r in rows), 'native observer failed')
        require(not any(r['sequence'] > self.boundary and r['kind'] in
                        ('human_callback', 'native_input', 'human_scroll_begin',
                         'human_scroll_end', 'native_background') for r in rows),
                'unadmitted input or background during fold')
        self.prefix = complete
        return rows

    def observe(self, raw):
        require(not self.consumed, 'readiness already consumed')
        rows = self.stream(raw)
        geometry = [r for r in rows if r['kind'] == 'geometry' and r['sequence'] > self.boundary]
        self.hint = None
        if not geometry:
            return None
        latest = geometry[-1]
        scenes = latest['payload']['scenes']
        require(len(scenes) == 1 and scenes[0]['id'] == self.binding['scene']
                and scenes[0]['activation'] == 0, 'geometry scene changed or left foreground')
        windows = scenes[0]['windows']
        if not any(matches([w['width'], w['height']], self.display['pointScale'], self.display)
                   for w in windows):
            return None
        # The legacy geometry stream does not carry window/root IDs. A matching
        # auxiliary window may trigger capture, but cannot qualify the snapshot.
        self.hint = dict(state='GEOMETRY_HINT_ONLY', scenario_credit=False,
                         sequence=latest['sequence'], stream_sequence=rows[-1]['sequence'],
                         prefix_sha256=hashlib.sha256(self.prefix).hexdigest(),
                         display=self.display, binding=self.binding)
        return self.hint

    def finish(self, row, raw, display, validate_owner):
        require(self.hint is not None and self.consumed, 'no consumed geometry hint')
        require(row['sequence'] > self.hint['stream_sequence'], 'snapshot preceded readiness')
        rows = self.stream(raw)
        require(row in rows and row['kind'] == 'human_snapshot', 'fresh snapshot absent from joined stream')
        require(display_signature(display) == self.signature, 'actual display changed after capture')
        validate_owner(row, self.binding, display)
        return dict(state='OWNED_FOLD_SNAPSHOT_READY', scenario_credit=False,
                    hint_sequence=self.hint['sequence'], snapshot_sequence=row['sequence'],
                    prefix_sha256=hashlib.sha256(self.prefix).hexdigest(), display=display)


def collect(gate, *, read_events, snapshot, actual_display, validate_owner,
            persist, live, deadline, post_hint_seconds, clock=time.time, pause=time.sleep):
    """One condition wait, one owned snapshot and one post-snapshot display read.

    Callbacks own request/checkpoint/process validation and durable transport
    responses. This helper never sends input or changes the caller's deadline.
    """
    phase = 'GEOMETRY_READINESS'
    latest_raw = gate.prefix
    require(positive(deadline) and positive(post_hint_seconds), 'invalid observation budget')
    phase_deadline = deadline

    def check():
        require(clock() < phase_deadline, phase + '_DEADLINE_EXPIRED')
        live(phase_deadline)

    check()
    try:
        while True:
            check()
            latest_raw = read_events()
            hint = gate.observe(latest_raw)
            check()
            if hint is not None:
                # One budget covers hint persistence, the owned snapshot, the
                # actual display read and final assertion/persistence together.
                phase_deadline = min(deadline, clock() + post_hint_seconds)
                break
            pause(min(.1, max(0, deadline - clock())))
        persist('observed-geometry-events.jsonl', latest_raw)
        persist('geometry-events.jsonl', gate.prefix)
        persist('geometry-hint.json', json.dumps(hint, indent=2).encode() + b'\n')
        gate.consumed = True
        phase = 'OWNED_SNAPSHOT'
        check()
        row, raw = snapshot(phase_deadline)
        check()
        phase = 'POST_SNAPSHOT_DISPLAY'
        display = actual_display(phase_deadline)
        check()
        result = gate.finish(row, raw, display, validate_owner)
        result.update(original_deadline=deadline,post_hint_deadline=phase_deadline)
        persist('owned-readiness.json', json.dumps(result, indent=2).encode() + b'\n')
        check()
        return row
    except Exception as error:
        # Retain the actual last complete prefix even on nonconvergence. Never
        # turn it into a writer checkpoint or retry a failed snapshot.
        persist('stopped-geometry-events.jsonl', gate.prefix)
        persist('stopped-observed-events.jsonl', latest_raw)
        persist('readiness-stop.json', json.dumps(dict(state='INVALID_READINESS',phase=phase,
            reason=str(error),deadline=phase_deadline,original_deadline=deadline,
            finished_at=clock(),scenario_credit=False)).encode() + b'\n')
        raise
