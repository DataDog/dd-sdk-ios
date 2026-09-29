"""Supported-UI recording bridge for the physical H06 session.

This module never drives UI or owns QuickTime's process. The operator of the
supported CUA tool publishes its actual returned AX/error bytes. An unanswered,
late or failed tool call blocks concurrent restoration and task teardown.
"""
import json
from pathlib import Path
import time
import uuid

import operation_display as display
import operation_quicktime as q
import operation_setup as setup
import operation_transport as t

KIND = 'QUICKTIME_CUA'
REVIEWER = '/root/c06_runtime_plan'
CURRENT_CELL = ['startup', 'documents-channel', 'source-bound-display', 'ownership', 'cleanup', 'backend']


def notify_request(reference):
    print(json.dumps(dict(quicktime_request=reference)), flush=True)


def returned(request, *, tool_call_id, completed_at, ax_raw=None, reply_raw=None, error_raw=None):
    """Publish once, only after the actual awaited CUA call has returned.

    AX and reply are the exact full observation and its explicit interpretation.
    An error is retained as returned, never converted into a matching AX snapshot.
    Publication after a cutoff preserves evidence but cannot rescue acceptance.
    """
    path = q.clean(request['path']); raw = display.verified_ref(request, t.MAX_BYTES)
    value = t.load(raw)
    t.require(isinstance(tool_call_id, str) and tool_call_id.strip()
              and q.finite(completed_at) and value['issued_at'] <= completed_at <= time.time(),
              'invalid actual tool return identity')
    t.require((error_raw is not None and ax_raw is None and reply_raw is None)
              or (error_raw is None and isinstance(ax_raw, bytes) and isinstance(reply_raw, bytes)),
              'return must contain actual AX/reply or actual error')
    files = {}
    for name, data in [('ax', ax_raw), ('reply', reply_raw), ('error', error_raw)]:
        if data is not None:
            t.require(isinstance(data, bytes) and 0 < len(data) <= t.MAX_CONTEXT_BYTES, 'invalid raw tool return')
            target = path.parent / ('returned-' + name + '.raw')
            q.publish(target, data); files[name] = display.reference(target)
    marker = dict(schema_version=1, request_sha256=t.sha(raw), tool_call_id=tool_call_id,
                  completed_at=completed_at, published_at=time.time(), files=files)
    q.publish(path.parent / 'returned.json', t.encode(marker))
    return display.reference(path.parent / 'returned.json')


class Exchange:
    """One in-flight UI request. No retry and no late response substitution."""
    def __init__(self, *, notify=notify_request, wait=lambda: time.sleep(.25)):
        self.notify, self.wait = notify, wait
        self.active = None; self.seen = set(); self.blocked = False
        self.refs = []; self.last_refs = []

    @property
    def quiescent(self):
        return self.active is None and not self.blocked

    def verify(self):
        for ref in self.refs:
            q.clean(ref['path']); display.verified_ref(ref, t.MAX_CONTEXT_BYTES)

    def request(self, reference):
        t.require(self.quiescent and reference['sha256'] not in self.seen, 'UI request pending, failed or reused')
        path = q.clean(reference['path']); raw = display.verified_ref(reference, t.MAX_BYTES)
        request = t.load(raw)
        t.require(time.time() < request['deadline'] and not (path.parent / 'returned.json').exists(),
                  'expired or already answered UI request')
        self.active = reference; self.seen.add(reference['sha256'])
        try:
            self.notify(reference)
            while time.time() < request['deadline']:
                if (path.parent / 'returned.json').exists():
                    marker_ref = display.reference(path.parent / 'returned.json')
                    marker = t.load(display.verified_ref(marker_ref, t.MAX_BYTES))
                    t.require(set(marker) == {'schema_version', 'request_sha256', 'tool_call_id',
                                              'completed_at', 'published_at', 'files'}
                              and marker['schema_version'] == 1 and marker['request_sha256'] == t.sha(raw)
                              and isinstance(marker['tool_call_id'], str) and marker['tool_call_id'].strip(),
                              'foreign UI completion')
                    t.require(q.finite(marker['completed_at']) and q.finite(marker['published_at'])
                              and request['issued_at'] <= marker['completed_at'] <= marker['published_at'] <= time.time()
                              and marker['published_at'] < request['deadline'] and time.time() < request['deadline'],
                              'late or invalid UI completion')
                    files = marker['files']; t.require(set(files) in ({'ax', 'reply'}, {'error'}), 'incomplete UI return')
                    values = {}
                    for name, ref in files.items():
                        t.require(q.clean(ref['path']) == path.parent / ('returned-' + name + '.raw'),
                                  'UI return outside original request')
                        values[name] = display.verified_ref(ref, t.MAX_CONTEXT_BYTES)
                    t.require(display.verified_ref(reference, t.MAX_BYTES) == raw
                              and display.verified_ref(marker_ref, t.MAX_BYTES) == t.encode(marker),
                              'UI request or publication changed')
                    self.last_refs = [reference, marker_ref, *files.values()]
                    self.refs.extend(self.last_refs)
                    if 'reply' in values:
                        # A malformed semantic reply is still an actual completed call;
                        # Recorder retains/rejects it. The transport ID must agree when present.
                        reply = t.load(values['reply'])
                        t.require(reply.get('tool_call_id') == marker['tool_call_id'], 'UI tool IDs differ')
                        self.active = None
                    else:
                        self.blocked = True  # A tool error is not proof of an idle UI action.
                    return values
                self.wait()
            raise ValueError('original UI request cutoff expired; completion unknown')
        except BaseException:
            self.blocked = True
            raise


class Movie:
    """Session recorder with an actual CUA chain and no fabricated child process."""
    def __init__(self, remote, recorder, *, run_id, exchange=None):
        self.remote, self.recorder = remote, recorder
        self.exchange = exchange if exchange is not None else Exchange()
        b = recorder.binding
        t.require(b['run_id'] == run_id and b['device']['identifier'] == remote.identifier
                  and b['record_deadline'] < b['evidence_deadline'] < b['restore_deadline'] <= remote.execution_until,
                  'QuickTime recorder differs from the original session')
        self.used = False; self.checked = False; self.collected = False
        self.start_requested = False; self.stop_requested = False
        self.restoration = None; self.failure = None

    def step(self, phase):
        request = self.recorder.request(phase)
        if phase == 'START': self.start_requested = True
        if phase == 'STOP': self.stop_requested = True
        values = self.exchange.request(request)
        if 'error' in values:
            self.recorder.fail_pending(values['error'])
        return self.recorder.observe(values['ax'], values['reply'])

    def start(self):
        t.require(not self.used and not self.remote.cleanup_started, 'QuickTime recording already consumed')
        self.used = True
        try:
            self.step('SOURCE'); self.step('START')
        except BaseException as error:
            self.failure = str(error); raise

    def running(self):
        t.require(self.used and not self.collected and self.failure is None and self.exchange.quiescent
                  and not self.remote.cleanup_started, 'QuickTime capture is not live')
        self.exchange.verify(); self.recorder.running()

    def checkpoint(self):
        self.running()
        t.require(not self.checked, 'pre-publication recorder check already consumed')
        self.checked = True
        try:
            self.step('CHECK')
        except BaseException as error:
            self.failure = str(error); raise

    def collect(self, capture):
        self.running()
        t.require(self.checked and capture.movie is self and capture.remote is self.remote
                  and capture.binary_sha256 == self.recorder.binding['decoder']['sha256']
                  and capture.source_sha256 == self.recorder.binding['decoder_source_sha256'],
                  'movie decoder or pre-publication boundary differs')
        self.collected = True
        try:
            self.step('STOP'); self.step('SAVE')
            self.exchange.verify()
            ref = self.recorder.finish()
            result = t.load(display.verified_ref(ref, t.MAX_BYTES))
            t.require(result['state'] == 'CAPTURE_RECEIPTS_CHECKED', 'recording did not finalize')
            return result['decoder']  # Already fully decoded once, never decode twice.
        except BaseException as error:
            self.failure = str(error); raise

    def restore(self):
        if not self.used:
            return
        t.require(self.exchange.quiescent, 'unknown/failed UI completion blocks concurrent restoration')
        t.require(self.restoration is None, 'recorder restoration already consumed')
        # Stop once under the original recording cutoff. A failed/unknown Stop is
        # never retried as part of restoration, and expired phases are not renewed.
        if self.recorder.phase in ('START', 'CHECK') and not self.stop_requested:
            self.step('STOP')
        idle_source = self.recorder.phase == 'SOURCE' and not self.start_requested
        stopped = self.recorder.phase in ('STOP', 'SAVE')
        t.require((idle_source or stopped) and self.recorder.pending is None,
                  'verified stopped recorder required before audio restoration')
        result = self.step('RESTORE')
        folder = Path(result['path']).parent
        refs = [ref for ref in self.recorder.refs if Path(ref['path']).parent == folder]
        self.restoration = dict(result=result, refs=[*refs, *self.exchange.last_refs], binding=self.recorder.binding_raw)
        t.require(self.quiescent, 'recorder restoration not verified')

    @property
    def quiescent(self):
        if not self.exchange.quiescent:
            return False
        if not self.used:
            return True
        if self.restoration is None:
            return False
        try:
            t.require(display.read(self.recorder.output / 'binding.json', t.MAX_BYTES)
                      == self.restoration['binding'], 'restoration binding changed')
            for ref in self.restoration['refs']:
                q.clean(ref['path']); display.verified_ref(ref, t.MAX_CONTEXT_BYTES)
            value = t.load(display.verified_ref(self.restoration['result'], t.MAX_BYTES))
            return value['state'] == 'OBSERVED' and value['phase'] == 'RESTORE'
        except (OSError, ValueError, KeyError):
            return False


def preparation(plan, admission):
    """Offline review plus saved native recorder capability; no invented qualification."""
    recorder = plan['recorder']
    t.require(set(recorder) == {'kind', 'preparation'} and recorder['kind'] == KIND,
              'unsupported recorder; no fallback is permitted')
    q.clean(recorder['preparation']['path'])
    value = t.load(display.verified_ref(recorder['preparation'], t.MAX_CONTEXT_BYTES), maximum=t.MAX_CONTEXT_BYTES)
    t.require(admission['scope'] == 'H06_QUICKTIME_FIRST_CELL'
              and admission['recorderPreparation'] == recorder['preparation']
              and value['state'] == 'REVIEWED_QUICKTIME_SESSION_PREPARATION' and value['reviewer'] == REVIEWER
              and value['device'] == plan['device'] and value['helpers'] == plan['helpers']
              and value['toolchain'] == plan['toolchain'] and value['required_current_cell'] == CURRENT_CELL
              and value['native_qualification'] is False, 'QuickTime preparation or first-cell scope differs')
    for key in ['capability', 'capability_review', 'capability_definition']:
        q.clean(value[key]['path'])
    capability = t.load(display.verified_ref(value['capability'], t.MAX_BYTES))
    review = t.load(display.verified_ref(value['capability_review'], t.MAX_BYTES))
    definition = t.load(display.verified_ref(value['capability_definition'], t.MAX_CONTEXT_BYTES), maximum=t.MAX_CONTEXT_BYTES)
    t.require(capability['state'] == 'PASS_CAPTURE_CAPABILITY_ONLY'
              and all(capability[k] == 'PASS' for k in ['scenario_verdict', 'evidence_verdict', 'cleanup_verdict'])
              and capability['decoder_completed'] is True and capability['gate_credit'] is False
              and review['state'] == 'PASS' and review['reviewer'] == REVIEWER
              and definition['decoder']['sha256'] == plan['decoder']['binary']['sha256']
              and definition['decoder']['source_sha256'] == plan['decoder']['source']['sha256']
              and setup.file_sha(q.clean(definition['movie'])) == capability['movie_sha256'],
              'saved recorder capability absent or changed')
    return value
