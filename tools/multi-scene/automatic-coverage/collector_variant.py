#!/usr/bin/env python3
"""Rebuild only modern collectors; retain every original fixture binary/source."""
import argparse
import copy
import json
import os
from pathlib import Path
import shutil
import tempfile
import time
from run import HERE, REPO, RUN_ENV, baseline, call, inventory, protected_state, save


def prepare(parent):
    original = json.loads((parent / 'manifest.json').read_text())
    assert protected_state(REPO) == original['protected']
    attempt = Path(tempfile.mkdtemp(prefix='exp195-collector-'))
    manifest = copy.deepcopy(original)
    manifest.update(created_at=time.time(), head=call(['git','rev-parse','HEAD']), runs=[], failures=[],
                    ui_tests=baseline.fingerprint(HERE / 'UITests'), comparison_prior_attempts=[str(parent)])
    for key, build in manifest['builds'].items():
        if not key.endswith('-27.1'): continue
        root = attempt / key; root.mkdir()
        shutil.copytree(HERE / 'UITests', root / 'UITests')
        settings = {'PRODUCT_BUNDLE_IDENTIFIER':build['bundle_prefix']+'.uitests', 'GENERATE_INFOPLIST_FILE':'YES',
                    'SWIFT_VERSION':'5.0', 'CODE_SIGNING_ALLOWED':'NO'}
        project = {'name':'AutomaticCollector','targets': {'CoverageUITests': {'type':'bundle.ui-testing','platform':'iOS',
                   'deploymentTarget':'16.0','sources':['UITests'],'settings':{'base':settings}}},
                   'schemes':{'Coverage':{'build':{'targets':{'CoverageUITests':['test']}},
                                        'test':{'config':'Release','targets':['CoverageUITests']}}}}
        save(root/'project.json',project)
        call(['xcodegen','generate','--spec','project.json'],cwd=root,log=root/'generate.log')
        command=['xcodebuild','build-for-testing','-project',str(root/'AutomaticCollector.xcodeproj'),'-scheme','Coverage',
                 '-configuration','Release','-destination','generic/platform=iOS Simulator','-derivedDataPath',str(root/'derived'),
                 'CODE_SIGNING_ALLOWED=NO','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','-quiet']
        call(command,log=root/'build.log',timeout=180)
        build['collector_directory']=str(root)
        build['runner']={'path':str(root/'derived/Build/Products/Release-iphonesimulator/CoverageUITests-Runner.app')}
        build['runner']['identity']=inventory(build['runner']['path'])
        build['xctestrun']=str(next((root/'derived/Build/Products').glob('*.xctestrun')))
        build['collector_command']=command
        assert baseline.fingerprint(Path(build['directory'])/'Sources')==manifest['fixture']
        assert all(inventory(app['path'])==app['identity'] for app in build['apps'].values())
        print(json.dumps({'collector':key,'state':'BUILT'}),flush=True)
    save(attempt/'manifest.json',manifest)
    return attempt

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--parent',type=Path,required=True)
    print(prepare(parser.parse_args().parent),flush=True)
