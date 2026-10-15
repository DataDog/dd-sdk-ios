"""Generated media and synthetic receipt controls; never native or SDK evidence."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid
from unittest.mock import patch

import operation_display as d


def binding():
    return d.identity(str(uuid.uuid4()), str(uuid.uuid4()), {'scene-A': 'a' * 64, 'scene-B': 'b' * 64})


def payloads(identity, phases=('START', 'START')):
    return [d.marker(identity, s) for s in d.SCENES] + [d.marker(identity, s, p)
            for s, p in zip(d.SCENES, phases) if p is not None]


def frame(identity, phases, index=0):
    return dict(index=index, width=640, height=640, geometryValid=True,
                observations=[dict(payload=p, rawNormalizedBounds=[0.10000000001, 0.2, 0.3, 0.4])
                              for p in payloads(identity, phases)],
                pts=dict(value=index, timescale=6, epoch=0, flags=1))


class IntervalControls(unittest.TestCase):
    def setUp(self):
        self.owner = binding()
        self.frames = [frame(self.owner, (p, p), i) for i, p in enumerate(d.PHASES)]

    def test_complete_interval_has_no_native_credit(self):
        result = d.interval(self.frames, self.owner)
        self.assertEqual(result['interval_frames'], 3)
        self.assertFalse(result['native_acceptance'])
        self.assertEqual(result['gates_closed'], [])

    def test_asynchronous_phase_rendering_and_repeated_frames(self):
        phases = [('START', 'START'), ('START', None), ('START', 'RUN'), (None, 'RUN'),
                  ('RUN', 'RUN'), ('RUN', 'RUN'), ('FINAL', 'RUN'), ('FINAL', 'FINAL')]
        result = d.interval([frame(self.owner, p, i) for i, p in enumerate(phases)], self.owner)
        self.assertEqual(result['run_frame'], 4)
        self.assertEqual(len(result['transition_frames']), 2)

    def test_missing_owner_foreign_nonce_and_duplicate_marker_reject(self):
        mutations = [lambda f: f['observations'].pop(0),
                     lambda f: f['observations'][0].update(payload=d.marker(binding(), 'scene-A')),
                     lambda f: f['observations'][1].update(payload=f['observations'][0]['payload']),
                     lambda f: f['observations'][3].update(payload=f['observations'][2]['payload']),
                     lambda f: f['observations'][0].update(payload=None),
                     lambda f: f.update(geometryValid=False)]
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                rows = copy.deepcopy(self.frames); mutate(rows[1])
                with self.assertRaises(d.Rejected): d.interval(rows, self.owner)

    def test_rendering_gap_cannot_hide_stable_interval(self):
        rows = [self.frames[0], self.frames[1], frame(self.owner, ('RUN', None)),
                self.frames[1], self.frames[2]]
        with self.assertRaisesRegex(d.Rejected, 'outside a rendering transition'): d.interval(rows, self.owner)

    def test_regression_skipped_phase_and_early_final_reject(self):
        for phases in [ [('START','START'), ('RUN','START'), ('FINAL','START'), ('FINAL','FINAL')],
                        [('START','START'), ('RUN','RUN'), ('START','RUN'), ('FINAL','FINAL')],
                        [('START','START'), ('FINAL','FINAL')] ]:
            with self.subTest(phases=phases), self.assertRaises(d.Rejected):
                d.interval([frame(self.owner, p, i) for i, p in enumerate(phases)], self.owner)

    def test_missing_anchors_and_unstarted_recording_reject(self):
        for rows in [self.frames[1:], self.frames[:-1], [], [self.frames[0]]]:
            with self.subTest(rows=len(rows)), self.assertRaises(d.Rejected): d.interval(rows, self.owner)

    def test_post_final_tail_is_retained_outside_interval(self):
        result = d.interval([*self.frames, dict(observations=[])], self.owner)
        self.assertEqual(result['retained_tail_frames'], 1)
        self.assertEqual(result['interval_frames'], 3)

    def test_alias_native_bindings_reject(self):
        with self.assertRaises(d.Rejected):
            d.identity(self.owner['run_id'], self.owner['nonce'], {s: 'a' * 64 for s in d.SCENES})


class ReceiptControls(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name); self.owner = binding()

    def receipt(self, frames=None, **changes):
        folder = self.root / str(uuid.uuid4()); folder.mkdir()
        rows = frames or [frame(self.owner, (p,p), i) for i,p in enumerate(d.PHASES)]
        raw = b''.join(json.dumps(r).encode() + b'\n' for r in rows)
        (folder/'frames.jsonl').write_bytes(raw)
        value = dict(schemaVersion=1, state='DECODED', nativeAcceptance=False, kind='MOVIE', readerState='completed',
                     revision=3, framesSHA256=d.sha(folder/'frames.jsonl'), frameCount=len(rows),
                     trackCount=1, decodedOutput=True, pixelFormat=1111970369)
        value.update(changes); d.save(folder/'decoder.json', value)
        return folder

    def test_repeated_equal_pts_and_equivalent_timebases_are_valid(self):
        frames = [frame(self.owner, ('START','START'), i) for i in range(3)]
        frames[0]['pts'].update(value=1, timescale=2)
        frames[1]['pts'].update(value=3, timescale=6)
        frames[2]['pts'].update(value=4, timescale=6)
        self.assertEqual(len(d.receipt(self.receipt(frames), 'MOVIE')[1]), 3)

    def test_failed_cancelled_unknown_and_partial_reader_reject(self):
        for change in [dict(state='DECODER_FAILED'), dict(readerState='cancelled'), dict(readerState='reading'),
                       dict(decodedOutput=False), dict(trackCount=2), dict(frameCount=1), dict(nativeAcceptance=True)]:
            with self.subTest(change=change), self.assertRaises(d.Rejected):
                d.receipt(self.receipt(**change), 'MOVIE')

    def test_regressing_indefinite_or_replaced_pts_reject(self):
        for change in [dict(value=-1), dict(flags=17), dict(timescale=0), dict(epoch=1), dict(value=True)]:
            rows = [frame(self.owner, (p,p), i) for i,p in enumerate(d.PHASES)]; rows[1]['pts'].update(change)
            with self.subTest(change=change), self.assertRaises(d.Rejected): d.receipt(self.receipt(rows), 'MOVIE')

    def test_changed_or_unfinalized_stream_reject(self):
        for truncated in [True, False]:
            folder = self.receipt(); stream = folder/'frames.jsonl'
            stream.write_bytes(stream.read_bytes()[:-1] if truncated else stream.read_bytes() + b'{}\n')
            with self.assertRaises(d.Rejected): d.receipt(folder, 'MOVIE')

    def test_screenshot_cannot_substitute_for_video(self):
        with self.assertRaises(d.Rejected): d.receipt(self.receipt(kind='IMAGE'), 'MOVIE')

    def test_process_timeout_and_failure_are_saved(self):
        media = self.root/'source.mov'; media.write_bytes(b'synthetic-not-native')
        for name, effect in [('timeout', subprocess.TimeoutExpired(['synthetic'], 1, output=b'partial')),
                             ('failed', subprocess.CompletedProcess(['synthetic'], 1, b'', b'failed')),
                             ('launch', OSError('synthetic launch failure'))]:
            folder = self.root/name
            options = dict(side_effect=effect) if isinstance(effect, Exception) else dict(return_value=effect)
            with patch.object(d.subprocess, 'run', **options), self.assertRaises(d.Rejected):
                d.decode(Path(sys.executable).resolve(), d.sha(Path(sys.executable).resolve()), 'MOVIE', media, folder, 1, source_sha256=d.sha(Path(d.__file__).with_suffix('.swift')))
            self.assertTrue((folder/'process.json').is_file())
            self.assertEqual((folder/'raw.mov').read_bytes(), media.read_bytes())
            self.assertFalse(json.loads((folder/'invocation.json').read_text())['native_acceptance'])

    def test_changed_binary_consumed_directory_and_oversized_input_reject(self):
        media = self.root/'source.mov'; media.write_bytes(b'control')
        with self.assertRaises(d.Rejected): d.decode(Path(sys.executable).resolve(), '0'*64, 'MOVIE', media, self.root/'bad', 1, source_sha256=d.sha(Path(d.__file__).with_suffix('.swift')))
        with self.assertRaises(FileExistsError):
            d.decode(Path(sys.executable).resolve(), d.sha(Path(sys.executable).resolve()), 'MOVIE', media, self.root, 1, source_sha256=d.sha(Path(d.__file__).with_suffix('.swift')))
        with patch.object(d, 'MAX_BYTES', 1), self.assertRaises(d.Rejected):
            d.decode(Path(sys.executable).resolve(), d.sha(Path(sys.executable).resolve()), 'MOVIE', media, self.root/'oversize', 1, source_sha256=d.sha(Path(d.__file__).with_suffix('.swift')))


@unittest.skipUnless(os.environ.get('OPERATION_DISPLAY_CODEC'), 'set OPERATION_DISPLAY_CODEC for actual generated-media controls')
class GeneratedMediaControls(unittest.TestCase):
    def setUp(self):
        base = os.environ.get('OPERATION_DISPLAY_ARTIFACTS')
        self.root = Path(tempfile.mkdtemp(prefix=self._testMethodName + '-', dir=base))
        if not base:
            import shutil
            self.addCleanup(shutil.rmtree, self.root)
        self.binary = Path(os.environ['OPERATION_DISPLAY_CODEC'])
        self.binary_sha = d.sha(self.binary); self.owner = binding()
        self.sequence = 0

    def generate(self, spec, movie=False):
        self.sequence += 1
        source = self.root/f'spec-{self.sequence}.json'; d.save(source, spec)
        media = self.root/(f'fixture-{self.sequence}.' + ('mov' if movie else spec.get('format', 'png')))
        result = subprocess.run([str(self.binary), 'fixture-movie' if movie else 'fixture', str(source), str(media)],
                                capture_output=True, timeout=90)
        d.save(self.root/f'generation-{self.sequence}.json', dict(returncode=result.returncode,
               stdout=result.stdout.decode(errors='replace'), stderr=result.stderr.decode(errors='replace'), synthetic=True))
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        return media

    def decode(self, media, kind):
        folder = self.root/(media.stem + '-decoded')
        return d.decode(self.binary, self.binary_sha, kind, media, folder, 90,
                        source_sha256=d.sha(Path(d.__file__).with_suffix('.swift')))

    def test_png_jpeg_scale_and_orientation(self):
        for fmt, scale, orientation in [('png',1,1), ('png',2,1), ('jpeg',1,1), ('jpeg',1,6), ('jpeg',1,8)]:
            with self.subTest(fmt=fmt, scale=scale, orientation=orientation):
                media = self.generate(dict(payloads=payloads(self.owner), format=fmt, scale=scale, orientation=orientation))
                folder = self.decode(media, 'IMAGE'); frames = d.checked(folder, 'IMAGE')
                self.assertEqual(d.inventory(frames[0], self.owner), ('START','START'))
                self.assertEqual(frames[0]['width'], 640*scale)
                self.assertEqual(json.loads((Path(folder['path']).parent/'decoded/decoder.json').read_text())['imageOrientation'], orientation)

    def test_compressed_rotated_movie_and_independent_anchors(self):
        for rotation in [0, 90]:
            with self.subTest(rotation=rotation):
                specs = [dict(payloads=payloads(self.owner, (p,p))) for p in ['START','START','RUN','RUN','FINAL','FINAL']]
                media = self.generate(dict(frames=specs, rotation=rotation), movie=True)
                movie = self.decode(media, 'MOVIE'); anchors = {}
                for phase in d.PHASES:
                    anchors[phase] = self.decode(self.generate(dict(payloads=payloads(self.owner, (phase,phase)))), 'IMAGE')
                result = d.assess(movie, anchors, self.owner, self.root/f'assessment-{rotation}.json')
                self.assertFalse(result['native_acceptance'])
                self.assertEqual(result['retained_tail_frames'], 1)
                self.assertEqual(len(d.checked(movie, 'MOVIE')), 6)
                with self.assertRaises(d.Rejected):
                    d.assess(anchors['START'], anchors, self.owner, self.root/'image-only.json')
                wrong = dict(anchors); wrong['RUN'] = anchors['FINAL']
                with self.assertRaises(d.Rejected): d.assess(movie, wrong, self.owner, self.root/'wrong-anchor.json')

    def test_missing_and_foreign_owner_are_detected_in_real_pixels(self):
        for problem in ['missing', 'foreign']:
            phases = [payloads(self.owner, (p,p)) for p in d.PHASES]
            if problem == 'missing': phases[1].pop(0)
            else: phases[1][0] = d.marker(binding(), 'scene-A')
            media = self.generate(dict(frames=[dict(payloads=p) for p in phases]), movie=True)
            frames = d.checked(self.decode(media, 'MOVIE'), 'MOVIE')
            with self.assertRaises(d.Rejected): d.interval(frames, self.owner)

    def test_saved_manifest_pins_every_artifact(self):
        media = self.generate(dict(payloads=payloads(self.owner)))
        proof = self.decode(media, 'IMAGE')
        manifest = json.loads(Path(proof['path']).read_text())
        for name in ['invocation', 'process', 'raw', 'decoder', 'frames']:
            path = Path(manifest[name]['path']); original = path.read_bytes()
            try:
                path.write_bytes(original + b' ')
                with self.subTest(name=name), self.assertRaises(d.Rejected): d.checked(proof, 'IMAGE')
            finally: path.write_bytes(original)
        original = Path(proof['path']).read_bytes()
        try:
            Path(proof['path']).write_bytes(original + b' ')
            with self.assertRaises(d.Rejected): d.checked(proof, 'IMAGE')
        finally: Path(proof['path']).write_bytes(original)
        self.assertEqual(d.inventory(d.checked(proof, 'IMAGE')[0], self.owner), ('START','START'))

    def test_saved_decode_rechecks_executable_and_source(self):
        import shutil
        codec = self.root/'decoder-copy'; shutil.copy2(self.binary, codec)
        media = self.generate(dict(payloads=payloads(self.owner)))
        proof = d.decode(codec, d.sha(codec), 'IMAGE', media, self.root/'copy-output', 90,
                         source_sha256=d.sha(Path(d.__file__).with_suffix('.swift')))
        with codec.open('ab') as stream: stream.write(b'changed')
        with self.assertRaises(d.Rejected): d.checked(proof, 'IMAGE')
        with self.assertRaises(d.Rejected):
            d.decode(self.binary, self.binary_sha, 'IMAGE', media, self.root/'wrong-source', 90, source_sha256='0'*64)

    def test_truncated_movie_and_corrupt_image_do_not_qualify(self):
        movie = self.generate(dict(frames=[dict(payloads=payloads(self.owner, (p,p))) for p in d.PHASES]), movie=True)
        broken = self.root/'truncated.mov'; broken.write_bytes(movie.read_bytes()[:len(movie.read_bytes())//2])
        image = self.root/'corrupt.png'; image.write_bytes(b'not an image')
        for media, kind in [(broken,'MOVIE'), (image,'IMAGE')]:
            with self.subTest(kind=kind), self.assertRaises(d.Rejected): self.decode(media, kind)
        self.assertTrue((self.root/'truncated-decoded/process.json').is_file())


if __name__ == '__main__':
    unittest.main()
