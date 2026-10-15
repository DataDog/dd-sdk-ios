#!/usr/bin/env python3
"""Prepare the eight pre-defined one-window, manifest-true comparison cells."""
import argparse
import copy
import json
from pathlib import Path
import plistlib
import shutil
import tempfile
import time
from run import DEFINITION, REPO, app_metadata, baseline, call, inventory, protected_state, save, namespace, validate_frozen_inputs


def prepare_variant(parent):
    original = json.loads((parent / 'manifest.json').read_text())
    validate_frozen_inputs(parent, original)
    definition = json.loads(DEFINITION.read_text()) if original.get('experiment', 'EXP-195') == 'EXP-195' else original['definition']
    assert definition['manifest_true_followup']['defined_before_implementation'] is True
    assert definition['manifest_true_followup']['cells'] == 8
    assert original.get('declared_multiple_scenes', False) is False
    assert protected_state(REPO) == original['protected']
    attempt = Path(tempfile.mkdtemp(prefix=namespace(original.get('experiment', 'EXP-195')) + '-manifest-true-'))
    manifest = copy.deepcopy(original)
    manifest.update(created_at=time.time(), head=call(['git', 'rev-parse', 'HEAD']), definition=definition,
                    runs=[], failures=[], declared_multiple_scenes=True, parent_build_attempt=str(parent))
    manifest.pop('comparison_prior_attempts', None)
    manifest['builds'] = {key: value for key, value in manifest['builds'].items() if key.endswith('-27.1')}
    assert set(manifest['builds']) == {'baseline-27.1', 'candidate-27.1'}
    for key, build in manifest['builds'].items():
        assert baseline.fingerprint(Path(build['directory']) / 'Sources') == manifest['fixture']
        build['app_metadata'] = {}
        for framework, app in build['apps'].items():
            source = Path(app['path'])
            assert inventory(source) == app['identity']
            destination = attempt / 'products' / key / source.name
            shutil.copytree(source, destination)
            info_path = destination / 'Info.plist'
            old_info = plistlib.loads(info_path.read_bytes())
            assert old_info['UIApplicationSceneManifest']['UIApplicationSupportsMultipleScenes'] is False
            info = copy.deepcopy(old_info)
            info['UIApplicationSceneManifest']['UIApplicationSupportsMultipleScenes'] = True
            info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
            restored = copy.deepcopy(plistlib.loads(info_path.read_bytes()))
            restored['UIApplicationSceneManifest']['UIApplicationSupportsMultipleScenes'] = False
            assert restored == old_info, 'variant changed more than scene declaration'
            assert inventory(destination) == app['identity'], 'variant changed Mach-O code'
            app.update(path=str(destination), original_app_path=str(source), original_metadata=app_metadata(source))
            build['app_metadata'][framework] = app_metadata(destination)
    save(attempt / 'definition.json', definition)
    save(attempt / 'manifest.json', manifest)
    return attempt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parent', type=Path, required=True)
    print(prepare_variant(parser.parse_args().parent), flush=True)
