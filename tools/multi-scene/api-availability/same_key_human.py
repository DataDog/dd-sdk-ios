#!/usr/bin/env python3
"""Prepare and compile the human setup continuation; never admit native work."""
import argparse
import json
from pathlib import Path
import shutil
import sys

import build
import same_key
import same_key_setup


HELPERS = sorted(set(same_key.HELPERS + ['same_key_human.py', 'same_key_setup.py',
    '../interactive-transitions/physical_release.py', '../app-acceptance/capture_io.py']))
SOURCE = '94842cc8ad7b104c1394c236b98b95b6c24a0956'
TRANSITION = 'DatadogRUM/MultiSceneSupport/Results/navigation-documentation-consolidation-20260924.json'
_protected = build.protected


def protected():
    values = _protected()
    return {k: values[k] for k in ['Datadog/Datadog.xcodeproj/project.pbxproj', 'xcconfigs/Datadog.local.xcconfig']}


def reference(path):
    path = Path(path).resolve(strict=True)
    return dict(path=str(path), sha256=build.shared.sha(path))


def members():
    paths = {(build.HERE/name).resolve() for name in HELPERS}
    for module in list(sys.modules.values()):
        value = getattr(module, '__file__', None)
        if value:
            path = Path(value).resolve()
            if path.is_relative_to(build.HERE.parent) and path.suffix == '.py' and not path.name.startswith('test_'):
                paths.add(path)
    return {str(path.relative_to(build.shared.REPO)): build.shared.sha(path) for path in sorted(paths)}


def verify(root):
    build.protected = protected
    bound = build.shared.read(root/'human-inputs.json')
    definition = bound['definition']
    build.require(build.shared.sha(definition['path']) == definition['sha256'], 'human definition changed')
    value = build.shared.read(definition['path'])
    build.require(value['state'] == 'DEFINED_BEFORE_IMPLEMENTATION' and value['source'] == SOURCE
                  and value['limits']['native_launches'] == 0, 'human preparation scope changed')
    original = value['original_result']
    build.require(build.shared.sha(original['path']) == original['sha256'], 'original failed run changed')
    result = build.shared.read(original['path'])
    build.require(result['automatic_path'] == 'STOPPED_NO_EQUIVALENT_RETRY' and result['cleanup']['verdict'] == 'PASS',
                  'original native path not stopped/clean')
    build.require(bound['workspace_transition'] == reference(build.shared.REPO/TRANSITION)
                  and bound['helpers'] == members() == build.shared.tree(root/'helpers'), 'human preparation helpers changed')
    plan = build.verify(root)
    build.require(plan['source'] == same_key.SOURCE and plan['multiple_scenes'] is True
                  and plan['native_admitted'] is False, 'human source/mode differs')
    build.require(bound['candidate'] == same_key.candidate_binding(root, value), 'human candidate source changed')
    return bound


def prepare(root, definition):
    value = build.shared.read(definition)
    build.require(value['state'] == 'DEFINED_BEFORE_IMPLEMENTATION' and value['source'] == SOURCE
                  and value['limits']['native_launches'] == 0, 'preparation is not separately defined')
    build.protected = protected
    build.prepare(root, fixture_directory=build.HERE/'same-key', multiple_scenes=True)
    frozen = members(); (root/'helpers').mkdir()
    for name in frozen:
        target = root/'helpers'/name; target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(build.shared.REPO/name, target)
    build.shared.save(root/'human-inputs.json', dict(definition=reference(definition), helpers=frozen,
        candidate=same_key.candidate_binding(root, value), workspace_transition=reference(build.shared.REPO/TRANSITION),
        native_admitted=False), exclusive=True)
    verify(root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'verify', 'build'])
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--definition', type=Path)
    args = parser.parse_args(); root = args.root.resolve()
    if args.action == 'prepare':
        build.require(args.definition is not None, 'definition required')
        prepare(root, args.definition.resolve())
    else:
        verify(root)
        if args.action == 'build':
            review = build.shared.read(root/'review.json')
            build.require(review['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan'
                          and review['inputs_sha256'] == build.shared.sha(root/'human-inputs.json')
                          and review['scope'] == 'OFFLINE_AND_BUILD_ONLY', 'human build review missing')
            build.build(root, 'simulator'); verify(root)
    print(json.dumps(dict(state='PREPARED_NATIVE_UNADMITTED', inputs=reference(root/'human-inputs.json'),
                         native_launches=0)))


if __name__ == '__main__':
    main()
