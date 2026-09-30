"""One isolated diagnostic build from the stopped SDK27.1 split product."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import time

import human_swiftui_refresh as refresh
import human_supported_session as evidence

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
import sys
sys.path.insert(0, str(HERE.parent / 'interactive-transitions'))
import accessibility_ancestry_probe as probe

KEY = 'baseline-27.1'
PATHS = ['tools/multi-scene/automatic-coverage/human_ancestry_probe.py',
         'tools/multi-scene/interactive-transitions/accessibility_ancestry_probe.py',
         'tools/multi-scene/interactive-transitions/test_accessibility_ancestry_probe.py']
require = evidence.require


def bound(reference):
    require(evidence.reference(reference['path']) == reference, 'bound diagnostic input changed')
    return evidence.read(reference['path'])


def inputs(root):
    definition = evidence.read(root / 'definition.json')
    previous = bound(definition['source_plan'])
    stopped = bound(definition['source_attempt'])
    require(definition['state'] == 'DEFINED_NO_NATIVE_ADMISSION'
            and definition['scope']['builds'] == definition['scope']['native_attempts'] == 1
            and stopped['state'] == 'STOPPED_FOLD_CAPTURE_RESTORED'
            and stopped['separate_restoration']['state'] == 'PASS'
            and previous['selected'] == dict(build=KEY,device='duo',framework='SwiftUI',layout='split',multiple_scenes=False)
            and previous['source'] == definition['source_revision'], 'foreign diagnostic scope')
    product = previous['product']; require(product == definition['source_product'], 'product reference changed')
    old_arm = Path(product['path']).parents[4]
    old_root = old_arm.parent
    prior = refresh.verify(old_root)
    require(old_arm.name == KEY and refresh.product(old_root,KEY) == product, 'prior product changed')
    return definition, previous, prior, old_arm


def prepare(root):
    root = root.resolve(); definition, previous, prior, old = inputs(root)
    folder = root / 'build'; require(not folder.exists(), 'diagnostic build already prepared')
    folder.mkdir()
    shutil.copytree(old / 'sdk', folder / 'sdk')
    shutil.copytree(old / 'client', folder / 'client')
    raw = (old / 'client/HumanObservation.swift').read_bytes()
    rendered = probe.render(raw,hashlib.sha256(raw).hexdigest())
    (folder / 'client/HumanObservation.swift').write_bytes(rendered)
    original = prior['arms'][KEY]
    actual = refresh.s.tree(folder / 'client')
    require({p for p in actual if actual[p] != original['client'][p]} == {'HumanObservation.swift'}, 'non-diagnostic fixture change')
    plan = dict(schema_version=1,kind='SWIFTUI_ANCESTRY_DIAGNOSTIC_ONLY',key=KEY,
                definition=evidence.reference(root/'definition.json'),original_plan=definition['source_plan'],
                original_refresh=evidence.reference(old.parent/'refresh-plan.json'),
                original_product=previous['product'],original_arm=original,
                arm=dict(original,client=actual),toolchains=prior['toolchains'],
                helpers={p:evidence.reference(REPO/p) for p in PATHS},
                native_launches=0,created_at=time.time())
    evidence.save(root/'build-plan.json',plan)
    verify(root)


def verify(root):
    root = Path(root); plan = evidence.read(root/'build-plan.json')
    definition, previous, prior, old = inputs(root)
    require(bound(plan['definition']) == definition and plan['original_plan'] == definition['source_plan']
            and bound(plan['original_refresh']) == prior
            and plan['original_product'] == previous['product']
            and plan['original_arm'] == prior['arms'][KEY]
            and plan['toolchains'] == prior['toolchains']
            and plan['kind'] == 'SWIFTUI_ANCESTRY_DIAGNOSTIC_ONLY' and plan['key'] == KEY
            and plan['native_launches'] == 0, 'diagnostic identity differs')
    require(plan['helpers'] == {p:evidence.reference(REPO/p) for p in PATHS}, 'diagnostic helper changed')
    raw = (old/'client/HumanObservation.swift').read_bytes()
    expected = dict(prior['arms'][KEY]['client'], **{'HumanObservation.swift': hashlib.sha256(probe.render(raw,hashlib.sha256(raw).hexdigest())).hexdigest()})
    require(plan['arm'] == dict(prior['arms'][KEY],client=expected)
            and refresh.s.tree(root/'build/client') == expected
            and refresh.s.tree(root/'build/sdk') == plan['arm']['sdk'], 'source changed outside diagnostic')
    return plan


def build(root):
    root = root.resolve(); plan = verify(root)
    review = evidence.read(root/'build-review.json')
    require(review['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan'
            and review['plan_sha256'] == evidence.sha(root/'build-plan.json'), 'diagnostic build lacks exact review')
    seconds = bound(plan['definition'])['budgets_seconds']['build']
    started = time.time(); deadline = started + seconds; folder = root/'build'
    evidence.save(folder/'admission.json',dict(started_at=started,deadline=deadline,
        plan=evidence.reference(root/'build-plan.json'),review=evidence.reference(root/'build-review.json')))
    arm = plan['arm']; env = refresh.prior.build.env(arm['sdk_version'])
    version = subprocess.run(['xcodebuild','-version'],env=env,capture_output=True,text=True,check=True,timeout=30).stdout.strip()
    require(version == plan['toolchains'][arm['sdk_version']]['version'], 'compiler identity changed')
    refresh.prior.build.command(['xcodebuild','build','-project','AutomaticCoverage.xcodeproj','-scheme','Coverage',
        '-configuration','Release','-destination','generic/platform=iOS Simulator','-derivedDataPath',str(folder/'DerivedData'),
        'CODE_SIGNING_ALLOWED=NO','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','-jobs','4','-quiet'],
        folder,'build',arm['sdk_version'],deadline,cwd=folder/'client')
    app = folder/'DerivedData/Build/Products/Release-iphonesimulator/SwiftUIFixture.app'
    info = plistlib.loads((app/'Info.plist').read_bytes()); bundle = arm['bundle_prefix']+'.swiftui'
    require(info['CFBundleIdentifier'] == bundle and info['DTSDKName'] == 'iphonesimulator27.1'
            and info['MinimumOSVersion'] == '16.0'
            and info['UIApplicationSceneManifest']['UIApplicationSupportsMultipleScenes'] is False, 'app identity differs')
    product = dict(path=str(app),bundle=bundle,product=refresh.s.product(app,bundle=bundle),declared_multiple_scenes=False)
    result = dict(state='QUALIFIED_DIAGNOSTIC_BUILD_ONLY',plan=evidence.reference(root/'build-plan.json'),
                  source=arm['revision'],compiler=refresh.compiled(folder,arm),product=product,
                  native_launches=0,gates_closed=[],finished_at=time.time())
    verify(root); require(time.time() < deadline, 'diagnostic build exceeded budget')
    evidence.save(folder/'result.json',result)
    return result


if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['prepare','verify','build'])
    parser.add_argument('--root',type=Path,required=True);args=parser.parse_args()
    {'prepare':prepare,'verify':verify,'build':build}[args.action](args.root)
    print(json.dumps(dict(state='DIAGNOSTIC_ONLY',action=args.action,native_launches=0)))
