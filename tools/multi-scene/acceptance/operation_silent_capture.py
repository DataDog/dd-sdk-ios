"""Host-only silent recording primitives, without native admission authority.

The future adapter must bind fresh supported-tool source/display observations
before and after capture, inspect tracks and fully decode the movie. This module
does not implement that source producer or admit H06. Child liveness is not proof
that any screen pixels were recorded.
"""
import math
import json
import os
from pathlib import Path
import signal
import subprocess
import threading
import time

import operation_display as pixels
import operation_media as media

SCREENCAPTURE = '/usr/sbin/screencapture'


def silent_command(destination, rectangle, seconds):
    destination = Path(destination)
    pixels.require(destination.is_absolute() and destination.parent.is_dir()
                   and destination.resolve() == destination and not destination.exists(),
                   'recording destination is not fresh and canonical')
    pixels.require(isinstance(rectangle, (list, tuple)) and len(rectangle) == 4
                   and all(type(v) is int for v in rectangle)
                   and all(abs(v) <= 32768 for v in rectangle[:2])
                   and all(0 < v <= 8192 for v in rectangle[2:]), 'invalid capture rectangle')
    pixels.require(type(seconds) is int and 1 <= seconds <= 1800, 'invalid fixed recording limit')
    # Audio, cursor/click overlays, interactive selection and opening apps are absent.
    return [SCREENCAPTURE, '-x', '-v', '-V' + str(seconds),
            '-R' + ','.join(map(str, rectangle)), str(destination)]


def checked_tracks(value, expected_sha256):
    pixels.require(isinstance(value, dict) and value.get('schemaVersion') == 1
                   and value.get('state') == 'SILENT_TRACKS'
                   and value.get('inputSHA256') == expected_sha256
                   and value.get('nativeAcceptance') is False
                   and value.get('decodedFrames') is False, 'foreign or unqualified track inspection')
    tracks = value.get('tracks')
    pixels.require(isinstance(tracks, list) and tracks
                   and all(isinstance(x, dict) and set(x) == {'id', 'mediaType'}
                           and type(x['id']) is int and x['id'] > 0
                           and isinstance(x['mediaType'], str) for x in tracks)
                   and len({x['id'] for x in tracks}) == len(tracks), 'invalid track inventory')
    videos = sum(x['mediaType'] == 'vide' for x in tracks)
    audios = sum(x['mediaType'] == 'soun' for x in tracks)
    pixels.require(type(value.get('videoTrackCount')) is int
                   and type(value.get('audioTrackCount')) is int
                   and videos == value['videoTrackCount'] == 1
                   and audios == value['audioTrackCount'] == 0, 'audio or ambiguous video tracks present')
    return dict(state='SILENT_TRACKS_COMPONENT_CHECKED', native_acceptance=False,
                decoded_frames=False, gates_closed=[])


def checked_raw(reference):
    """Verify the complete evidence seal; this still grants no capture capability."""
    result = json.loads(pixels.verified_ref(reference, 65536))
    folder = Path(reference['path']).parent
    keys = {'definition', 'invocation', 'process-started', 'process-finished'}
    pixels.require(result.get('state') == 'RAW_MOVIE_UNQUALIFIED'
                   and result.get('native_acceptance') is False
                   and result.get('source_qualified') is False
                   and set(result.get('artifacts', {})) == keys, 'incomplete raw movie seal')
    values = {}
    for name, ref in result['artifacts'].items():
        pixels.require(Path(ref['path']) == folder / (name + '.json'), 'raw evidence moved or reused')
        values[name] = json.loads(pixels.verified_ref(ref, 65536))
    media_ref = result['media']
    pixels.require(Path(media_ref['path']) == folder / 'screen.mov', 'movie outside its recording')
    pixels.verified_ref(media_ref, pixels.MAX_BYTES)
    definition, invocation = values['definition'], values['invocation']
    started, finished = values['process-started'], values['process-finished']
    seconds = math.floor(definition['record_until'] - invocation['started_at'])
    expected = [SCREENCAPTURE, '-x', '-v', '-V' + str(seconds),
                '-R' + ','.join(map(str, definition['rectangle'])), media_ref['path']]
    pixels.require(invocation['definition'] == result['artifacts']['definition']
                   and invocation['argv'] == started['argv'] == expected
                   and type(started['pid']) is int and started['pid'] > 0
                   and started['pid'] == started['group'] == finished['pid'] == finished['group']
                   and invocation['started_at'] <= finished['started_at'] < definition['record_until']
                   and finished['started_at'] <= finished['finished_at'] < definition['stop_until']
                   and finished['deadline'] == definition['stop_until'], 'command, child or cutoff seal differs')
    pixels.require(finished['returncode'] == 0 and finished['original_returncode'] is None
                   and finished['forced'] is False and finished['expired'] is False
                   and finished['reaped'] is True and finished['remaining'] == []
                   and finished['failure'] is None and finished['native_acceptance'] is False,
                   'recording completion is unqualified')
    return dict(state='RAW_MOVIE_EVIDENCE_SEALED', native_acceptance=False,
                source_qualified=False, gates_closed=[])


class ProcessRecording:
    """One owned child and immutable cutoffs; source/UI qualification is external."""
    def __init__(self, folder, *, rectangle, record_until, stop_until):
        pixels.require(all(type(v) in (int, float) and math.isfinite(v) for v in (record_until, stop_until))
                       and time.time() + 3 < record_until < stop_until, 'recording lacks finalization reserve')
        self.folder = Path(folder); self.folder.mkdir()
        self.record_until, self.stop_until = record_until, stop_until
        self.destination = self.folder / 'screen.mov'
        self.rectangle = tuple(rectangle)
        self.definition = dict(rectangle=list(rectangle), record_until=record_until,
                               stop_until=stop_until, native_acceptance=False)
        silent_command(self.destination, rectangle, 1)  # Validate before any process can start.
        pixels.save(self.folder / 'definition.json', self.definition)
        self.definition_ref = pixels.reference(self.folder / 'definition.json')
        self.frozen = (self.folder, self.destination, self.rectangle, record_until, stop_until)
        pixels.save(self.folder / 'publication-preflight.json', dict(state='WRITABLE', native_acceptance=False))
        self.process = None; self.used = False; self.reaped = False; self.expired = False
        self.watchdog = None; self.stop_attempted = False

    def binding(self):
        pixels.require((self.folder, self.destination, self.rectangle, self.record_until, self.stop_until)
                       == self.frozen, 'recording identity or cutoff changed')
        pixels.verified_ref(self.definition_ref)

    def start(self):
        pixels.require(not self.used, 'recording already consumed')
        self.used = True
        self.binding()
        started_at = time.time()
        seconds = math.floor(self.record_until - started_at)
        argv = silent_command(self.destination, self.rectangle, seconds)
        pixels.save(self.folder / 'invocation.json', dict(argv=argv, started_at=started_at,
                    definition=self.definition_ref, native_acceptance=False, source_qualified=False))
        self.invocation_ref = pixels.reference(self.folder / 'invocation.json')
        with (self.folder / 'console.log').open('xb') as stream:
            self.process = subprocess.Popen(argv, stdout=stream, stderr=subprocess.STDOUT,
                                            start_new_session=True)
        self.watchdog = threading.Timer(max(0, self.stop_until - time.time()), self.expire)
        self.watchdog.daemon = True; self.watchdog.start()
        try:
            pixels.save(self.folder / 'process-started.json', dict(pid=self.process.pid,
                        group=self.process.pid, argv=argv, recorder_ready=False))
            self.started_ref = pixels.reference(self.folder / 'process-started.json')
            self.running()
        except BaseException:
            self.finish(accept=False)
            raise

    def running(self):
        self.binding()
        pixels.require(self.process is not None and self.process.poll() is None
                       and not self.expired and not self.stop_attempted
                       and time.time() < self.record_until, 'recording stopped or expired')

    def expire(self):
        self.expired = True
        if self.process is not None and self.process.poll() is None:
            try: os.killpg(self.process.pid, signal.SIGKILL)
            except ProcessLookupError: pass

    def finish(self, *, accept):
        pixels.require(self.process is not None and not self.stop_attempted, 'recording stop already consumed')
        self.stop_attempted = True
        original_returncode = self.process.poll()
        started_at = time.time(); signals = []; forced = False; failure = None; remaining = None
        stop_until = self.frozen[-1]  # Cleanup cannot inherit a mutated cutoff.
        try:
            pixels.require(started_at < stop_until, 'original stop cutoff expired')
            if original_returncode is None:
                try: os.killpg(self.process.pid, signal.SIGINT); signals.append('SIGINT')
                except ProcessLookupError: pass
                try: self.process.wait(timeout=max(.001, stop_until - time.time() - 2))
                except subprocess.TimeoutExpired: forced = True
            if self.process.poll() is None:
                os.killpg(self.process.pid, signal.SIGKILL); signals.append('SIGKILL')
                self.process.wait(timeout=max(.001, stop_until - time.time()))
            remaining = media.group_members(self.process.pid, stop_until)
            if remaining:
                forced = True
                os.killpg(self.process.pid, signal.SIGKILL); signals.append('SIGKILL')
                remaining = media.group_members(self.process.pid, stop_until)
            self.reaped = self.process.poll() is not None and remaining == []
            if self.reaped and self.watchdog is not None: self.watchdog.cancel()
        except BaseException as error:
            failure = dict(type=type(error).__name__, reason=str(error))
        result = dict(pid=self.process.pid, group=self.process.pid, original_returncode=original_returncode,
                      returncode=self.process.poll(), signals=signals, forced=forced,
                      expired=self.expired, reaped=self.reaped, remaining=remaining,
                      started_at=started_at, finished_at=time.time(), deadline=stop_until,
                      failure=failure, native_acceptance=False, source_qualified=False)
        pixels.save(self.folder / 'process-finished.json', result)
        pixels.require(self.reaped and time.time() < stop_until, 'recorder cleanup unproved')
        if not accept: return result
        pixels.require(original_returncode is None and failure is None and not forced and not self.expired
                       and started_at < self.frozen[-2]
                       and self.process.returncode == 0, 'recording failed or ended before requested stop')
        self.binding()
        pixels.verified_ref(self.invocation_ref)
        pixels.verified_ref(self.started_ref)
        pixels.require(self.destination.is_file() and not self.destination.is_symlink()
                       and 0 < self.destination.stat().st_size <= pixels.MAX_BYTES, 'missing or oversized movie')
        result['media'] = pixels.reference(self.destination)
        result['state'] = 'RAW_MOVIE_UNQUALIFIED'
        result['artifacts'] = {'definition': self.definition_ref, 'invocation': self.invocation_ref,
                               'process-started': self.started_ref,
                               'process-finished': pixels.reference(self.folder / 'process-finished.json')}
        pixels.save(self.folder / 'raw-result.json', result)
        checked_raw(pixels.reference(self.folder / 'raw-result.json'))
        return result
