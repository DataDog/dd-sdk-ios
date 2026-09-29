"""Copy the qualified public accessibility reader into new SwiftUI products only."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import time
import xml.etree.ElementTree as ET
import human_fixture_refresh as prior

s = prior.s
KIND = 'SWIFTUI_PUBLIC_ACCESSIBILITY_REFRESH'
SCHEME = 'AutomaticCoverage.xcodeproj/xcshareddata/xcschemes/Coverage.xcscheme'
READER = 'tools/multi-scene/interactive-transitions/accessibility_capture.py'
HERE = Path(__file__).resolve().parent
AUTOMATIC_FUNCTION_SHA256 = 'f4bc71c517dcf8592ef6cf98c79963ee0093dc4432b0a766e3abd5528b06df4a'


def renderer():
    spec = importlib.util.spec_from_file_location('automatic_public_accessibility', s.REPO/READER)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def helper_bindings():
    names = [str(Path(__file__).resolve().relative_to(s.REPO)), READER,
             'tools/multi-scene/interactive-transitions/test_accessibility_capture.py',
             'tools/multi-scene/automatic-coverage/test_human_swiftui_refresh.py']
    return {name: s.sha(s.REPO/name) for name in names}


def swiftui_scheme(raw):
    tree = ET.fromstring(raw); entries = tree.find('BuildAction/BuildActionEntries')
    s.require(entries is not None and len(entries) == 2, 'original Coverage scheme changed')
    refs = [entry.find('BuildableReference') for entry in entries]
    s.require(all(ref is not None for ref in refs) and
              {ref.get('BlueprintName') for ref in refs} == {'UIKitFixture', 'SwiftUIFixture'},
              'unexpected original build targets')
    for entry in list(entries):
        if entry.find('BuildableReference').get('BlueprintName') == 'UIKitFixture': entries.remove(entry)
    return ET.tostring(tree, encoding='utf-8', xml_declaration=True)



def render_observer(raw):
    """Rebind the shared traversal to the automatic observer's UIKit text field."""
    reader = renderer(); text = raw.decode()
    s.require(text.count(reader.START) == text.count(reader.END) == 1, 'ambiguous automatic observer')
    start = text.index(reader.START); end = text.index(reader.END, start); function = text[start:end]
    s.require(hashlib.sha256(function.encode()).hexdigest() == AUTOMATIC_FUNCTION_SHA256,
              'automatic accessibility function changed')
    dispatch = reader.START+'\n        if Settings.framework == "SwiftUI" { return publicAccessibility(window) }'
    replacement = function.replace(reader.START, dispatch, 1)+'\n'+reader.PUBLIC_CAPTURE
    rendered = text[:start]+replacement+text[end:]
    s.require(text.count('import Foundation\n') == 1 and 'import ObjectiveC\n' not in text,
              'automatic observer imports changed')
    return rendered.replace('import Foundation\n', 'import Foundation\nimport ObjectiveC\n', 1).encode()


def transformed(source):
    raw = (source/'HumanObservation.swift').read_bytes()
    return {'HumanObservation.swift': render_observer(raw),
            SCHEME: swiftui_scheme((source/SCHEME).read_bytes())}


def prepare(root, source):
    root = Path(root).resolve(); source = Path(source).resolve(); base = prior.verify(source)
    s.require(not root.exists(), 'SwiftUI refresh output already consumed')
    # Verify all old products before preparing copies; none is overwritten or rebuilt in place.
    prior.products(source)
    plan = dict(kind=KIND, prior_refresh=prior.sessions.reference(source/'refresh-plan.json', s),
                original=base['original'], keys=prior.KEYS, toolchains=base['toolchains'], arms={},
                helpers=helper_bindings(), native_launches=0, created_at=time.time())
    root.mkdir(parents=True)
    for key in prior.KEYS:
        folder = root/key; folder.mkdir(); old = source/key
        shutil.copytree(old/'sdk', folder/'sdk'); shutil.copytree(old/'client', folder/'client')
        changes = transformed(old/'client')
        for name, raw in changes.items(): (folder/'client'/name).write_bytes(raw)
        arm = dict(base['arms'][key], client=s.tree(folder/'client'))
        s.require({n for n in arm['client'] if arm['client'][n] != base['arms'][key]['client'][n]} == set(changes),
                  'SwiftUI refresh altered UI, RUM setup or another project input')
        plan['arms'][key] = arm
    s.save(root/'refresh-plan.json', plan, exclusive=True); verify(root)
    return plan


def verify(root):
    root = Path(root); plan = s.read(root/'refresh-plan.json')
    previous = prior.sessions.read_reference(plan['prior_refresh'], s)
    source = Path(plan['prior_refresh']['path']).parent; base = prior.verify(source)
    s.require(plan['kind'] == KIND and previous == base and plan['keys'] == prior.KEYS
              and plan['native_launches'] == 0 and plan['original'] == base['original']
              and plan['toolchains'] == base['toolchains'] and plan['helpers'] == helper_bindings(),
              'SwiftUI refresh source or scope changed')
    s.require(set(plan['arms']) == set(prior.KEYS), 'SwiftUI refresh arm inventory changed')
    for key, arm in plan['arms'].items():
        old = base['arms'][key]; changes = transformed(source/key/'client')
        expected = dict(old['client'], **{n: hashlib.sha256(raw).hexdigest() for n, raw in changes.items()})
        s.require(arm == dict(old, client=expected) and s.tree(root/key/'client') == expected
                  and s.tree(root/key/'sdk') == old['sdk'], 'SwiftUI refresh changed non-observer source')
    return plan


def compiled(folder, arm):
    derived = folder/'DerivedData'; lists = {}; sdk = set(); fixture = set()
    expected = {'Observation.swift', 'HumanObservation.swift', 'SwiftUIApp.swift'}
    for path in sorted((derived/'Build/Intermediates.noindex').rglob('*.SwiftFileList')):
        s.require(not path.is_symlink() and 'arm64' in path.parts, 'unexpected compiler architecture/list')
        members = {}
        for name in shlex.split(path.read_text()):
            source = Path(name); s.require(source.is_file() and not source.is_symlink(), 'missing compiler input')
            members[str(source)] = s.sha(source)
            if source.is_relative_to(folder/'sdk'): sdk.add(str(source.relative_to(folder/'sdk')))
            elif source.is_relative_to(folder/'client'):
                s.require(path.stem == 'SwiftUIFixture', 'unadmitted fixture compiler target')
                fixture.add(source.name)
            else: s.require(source.is_relative_to(derived), 'foreign compiler input')
        lists[str(path.relative_to(folder))] = dict(sha256=s.sha(path), members=members)
    s.require(fixture == expected and sdk == {n for n in arm['sdk'] if n.endswith('.swift') and n != 'Package.swift'},
              'SwiftUI compiler membership differs')
    objects = {str(p.relative_to(folder)): s.sha(p) for p in (derived/'Build/Intermediates.noindex').rglob('*.o')}
    s.require(lists and objects, 'compiler output absent')
    return dict(lists=lists, objects=objects, fixture_targets={'SwiftUIFixture': sorted(fixture)})


def compile_one(root, key):
    root = Path(root); plan = verify(root); s.require(key in prior.KEYS, 'unadmitted SwiftUI build')
    folder = root/key; arm = plan['arms'][key]; started = time.time(); deadline = started+prior.build.BUILD_SECONDS
    s.save(folder/'build-admission.json', dict(started_at=started, deadline=deadline,
           plan_sha256=s.sha(root/'refresh-plan.json')), exclusive=True)
    actual = subprocess.run(['xcodebuild', '-version'], env=prior.build.env(arm['sdk_version']),
                            capture_output=True, text=True, check=True, timeout=30).stdout.strip()
    s.require(actual == plan['toolchains'][arm['sdk_version']]['version'], 'original compiler changed')
    prior.build.command(['xcodebuild', 'build', '-project', 'AutomaticCoverage.xcodeproj', '-scheme', 'Coverage',
        '-configuration', 'Release', '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', str(folder/'DerivedData'),
        'CODE_SIGNING_ALLOWED=NO', 'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES', '-jobs', '4', '-quiet'],
        folder, 'build', arm['sdk_version'], deadline, cwd=folder/'client')
    app = folder/'DerivedData/Build/Products/Release-iphonesimulator/SwiftUIFixture.app'
    info = plistlib.loads((app/'Info.plist').read_bytes()); bundle = arm['bundle_prefix']+'.swiftui'
    s.require(info['CFBundleIdentifier'] == bundle and info['DTSDKName'] == 'iphonesimulator'+arm['sdk_version']
              and info['MinimumOSVersion'] == '16.0'
              and info['UIApplicationSceneManifest']['UIApplicationSupportsMultipleScenes'] is False,
              'SwiftUI product identity changed')
    product = dict(path=str(app), bundle=bundle, product=s.product(app, bundle=bundle), declared_multiple_scenes=False)
    result = dict(state='QUALIFIED_BUILD_ONLY', key=key, source=arm['revision'],
                  plan_sha256=s.sha(root/'refresh-plan.json'), compiler=compiled(folder, arm),
                  product=product, finished_at=time.time(), native_launches=0)
    verify(root); s.require(result['finished_at'] < deadline, 'SwiftUI build exceeded original deadline')
    s.save(folder/'build-result.json', result, exclusive=True); return result


def product(root, key):
    root = Path(root); plan = verify(root); s.require(key in plan['arms'], 'unknown SwiftUI product')
    folder = root/key; result = s.read(folder/'build-result.json'); admission = s.read(folder/'build-admission.json')
    arm = plan['arms'][key]
    s.require(result['state'] == 'QUALIFIED_BUILD_ONLY' and result['key'] == key and result['source'] == arm['revision']
              and result['plan_sha256'] == admission['plan_sha256'] == s.sha(root/'refresh-plan.json')
              and admission['started_at'] < result['finished_at'] < admission['deadline']
              and result['compiler'] == compiled(folder, arm), 'unqualified SwiftUI build')
    value = result['product']
    s.require(Path(value['path']) == folder/'DerivedData/Build/Products/Release-iphonesimulator/SwiftUIFixture.app'
              and value['bundle'] == arm['bundle_prefix']+'.swiftui' and value['declared_multiple_scenes'] is False
              and value['product'] == s.product(value['path'], bundle=value['bundle']), 'SwiftUI product changed')
    return value


def products(root):
    plan = verify(root); result = prior.products(Path(plan['prior_refresh']['path']).parent)
    for key in prior.KEYS: result[key+'-SwiftUI-single'] = product(root, key)
    return result


def oracle(raw, measurement):
    """Add the existing graph checks to the frozen oracle; retain all other bytes."""
    current = (HERE/'human_contract.py').read_bytes()
    start = current.index(b'def accessibility_owner('); end = current.index(b'\ndef target(', start)
    owner = current[start:end]
    anchor = b"    frame=rectangle(item['frame_in_window'])"
    s.require(raw.count(b'def accessibility_owner(') == 0 and raw.count(b'\ndef target(') == 1
              and raw.count(anchor) == 1, 'original target oracle changed')
    rendered = raw.replace(b'\ndef target(', b'\n'+owner+b'def target(', 1).replace(
        anchor, b"    accessibility_owner(value['accessibility'],item,binding['window'])\n"+anchor, 1)
    return rendered, dict(policy='public-accessibility-ownership-v3', predecessor=measurement,
        original_sha256=measurement['original_sha256'], rendered_sha256=hashlib.sha256(rendered).hexdigest(),
        graph_sha256=hashlib.sha256(owner).hexdigest(),
        scope='Existing public container, identifier and visibility checks; other native, Home, timing and scroll assertions unchanged.')


def historical_base(base):
    """Verify the observer-only transition while assessing old UIKit/Home evidence."""
    if base['measurement'].get('policy') != 'public-accessibility-ownership-v3': return base
    ref = base['observer_refresh']; prior.sessions.read_reference(ref, s)
    root = Path(ref['path']).parent; plan = verify(root)
    old_root = Path(plan['prior_refresh']['path']).parent
    s.require(base['products'] == products(root), 'new SwiftUI products are not bound to the refresh')
    predecessor = base['measurement']['predecessor']
    s.require(predecessor['policy'] == 'diagnostic-timing-scroll-identity-v2'
              and predecessor['original_sha256'] == base['measurement']['original_sha256'],
              'foreign accessibility oracle predecessor')
    return dict(base, products=prior.products(old_root), observer_refresh=plan['prior_refresh'], measurement=predecessor)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('action', choices=['prepare', 'build', 'verify'])
    parser.add_argument('--root', type=Path, required=True); parser.add_argument('--original', type=Path)
    parser.add_argument('--key', choices=prior.KEYS); args = parser.parse_args()
    if args.action == 'prepare': s.require(args.original is not None, 'prior refresh required'); prepare(args.root, args.original)
    elif args.action == 'build': compile_one(args.root, args.key)
    else: verify(args.root)
    print(json.dumps(dict(state='SWIFTUI_REFRESH_ONLY', root=str(args.root), native_launches=0)))
