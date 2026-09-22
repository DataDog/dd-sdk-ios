import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest

from capture_patch import render, stage, DEFINITION, OBSERVABILITY, DELEGATE, DASHBOARD


@unittest.skipUnless(os.environ.get('CAPTURE_ACCEPTED_SOURCE'), 'accepted app source supplied by the bounded host run')
class OverlayTests(unittest.TestCase):
    def setUp(self):
        self.source = Path(os.environ['CAPTURE_ACCEPTED_SOURCE'])

    def test_only_declared_overlay_and_original_sources_unchanged(self):
        before = {path: (self.source / path).read_bytes() for path in DEFINITION['existing_input_sources']}
        overlay = render(self.source)
        self.assertEqual(set(overlay), set(before) | set(DEFINITION['new_app_paths']))
        self.assertEqual(before, {path: (self.source / path).read_bytes() for path in before})
        self.assertEqual([path for path in overlay if path.endswith('.pbxproj') or path.endswith('.xcconfig')], [])
        monitor = overlay[OBSERVABILITY + 'UserMonitorLive.swift'].decode()
        original = before[OBSERVABILITY + 'UserMonitorLive.swift'].decode()
        self.assertEqual(original[original.index('private let ignoredErrorMessages'):], monitor[monitor.index('private let ignoredErrorMessages'):])
        self.assertIn('content.trackRUMView(name: name.rawValue, attributes: attributes.raw)\n#if os(iOS)\n', monitor)
        self.assertEqual(monitor.count('return RUMView(name: viewName, attributes: attributes.raw)'), 1)
        delegate = overlay[DELEGATE].decode()
        self.assertEqual(delegate[delegate.index('    func setUpNavigationControllersDelegate'):delegate.index('    func navigationController')],
                         before[DELEGATE].decode()[before[DELEGATE].decode().index('    func setUpNavigationControllersDelegate'):before[DELEGATE].decode().index('    func navigationController')])
        dashboard = overlay[DASHBOARD].decode()
        self.assertEqual(dashboard.count('super.viewDidAppear(animated)'), 1)
        self.assertEqual(dashboard.count('super.viewDidDisappear(animated)'), 1)
        self.assertNotIn('class CaptureHostingController', '\n'.join(value.decode() for value in overlay.values()))

    def test_stale_and_symlinked_input_rejected_before_overlay_creation(self):
        with tempfile.TemporaryDirectory() as temporary:
            copy = Path(temporary) / 'source';copy.mkdir()
            for relative in DEFINITION['existing_input_sources']:
                path = copy / relative;path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((self.source / relative).read_bytes())
            first = next(iter(DEFINITION['existing_input_sources']));path = copy / first
            original = path.read_bytes();path.write_bytes(original + b'\n')
            target = Path(temporary) / 'overlay'
            with self.assertRaises(ValueError):stage(copy, target)
            self.assertFalse(target.exists())
            path.unlink();path.symlink_to(self.source / first)
            with self.assertRaises(ValueError):stage(copy, target)
            self.assertFalse(target.exists())

    def test_existing_overlay_cannot_be_rewritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / 'overlay';receipt = stage(self.source, target)
            frozen = (target / 'overlay.json').read_bytes()
            with self.assertRaises(ValueError):stage(self.source, target)
            self.assertEqual((target / 'overlay.json').read_bytes(), frozen)
            for relative, digest in receipt['overlay_sha256'].items():
                self.assertEqual(hashlib.sha256((target / relative).read_bytes()).hexdigest(), digest)


if __name__ == '__main__':unittest.main()
