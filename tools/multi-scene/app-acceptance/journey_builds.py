"""Read-only reuse of the two qualified F08 capture products."""
import datetime
import importlib.util
import json
import os
from pathlib import Path
import plistlib

from capture_build import sha
from journey_contract import require

ARMS = dict(baseline='62f64d7b655bdc83f3036c4ad81090a270f6202b', candidate='c9faed816a1d4828d7d8c4b64acae01119425889')


def module(path):
    spec = importlib.util.spec_from_file_location('frozen_capture_source_guard', path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def product(app, manifest):
    app = Path(app).resolve(strict=True)
    files = {str(p.relative_to(app)):sha(p) for p in app.rglob('*') if p.is_file() and not p.is_symlink()}
    links = {str(p.relative_to(app)):os.readlink(p) for p in app.rglob('*') if p.is_symlink()}
    require(files == {name:row['sha256'] for name,row in manifest['files'].items()} and links == manifest['symlinks'],
            'complete installed product changed')
    require(all((app/name).resolve(strict=True).is_relative_to(app) for name in links), 'installed symlink escapes app')
    info = plistlib.loads((app/'Info.plist').read_bytes())
    require(info['DTSDKName'] == 'iphonesimulator27.1' and info['MinimumOSVersion'] == '18.0'
            and info['UIApplicationSceneManifest']['UIApplicationSupportsMultipleScenes'] is False,
            'ordinary app product identity differs')
    return dict(files=len(files), mach_o=len(manifest['mach_o']), bundle_id=info['CFBundleIdentifier'],
                executable=info['CFBundleExecutable'], application_id=info['RUMReleaseValidationApplicationID'],
                app_version=info['CFBundleShortVersionString'], sdk_version=manifest['sdk_version'])


def verify(build_root, arm, completion_sha256, *, installed=None):
    root = Path(build_root).resolve(strict=True)
    require(arm in ARMS and sha(root/'completion.json') == completion_sha256, 'unbound capture build completion')
    completion = json.loads((root/'completion.json').read_text())
    bound = completion['arms'][arm]
    require(completion['state'] == 'TWO_SOURCE_BOUND_CAPTURE_PRODUCTS_QUALIFIED' and bound['source'] == ARMS[arm],
            'wrong qualified source')
    require(datetime.datetime.fromisoformat(bound['finished_at']) < datetime.datetime.fromisoformat(bound['deadline']),
            'original product qualification was late')
    for name,digest in bound['receipts'].items():require(sha(root/arm/name) == digest, 'original build receipt changed')
    require(not (root/arm/'late-product-publication.json').exists(), 'original product publication expired')
    original = root/'capture-build-before-filelist-correction.py'
    definition = json.loads((root/'definition.json').read_text())
    require(sha(original) == definition['adapter_sha256'], 'original source guard changed')
    guard, preparation = module(original).bind(root)
    freeze = json.loads((root/arm/'build-input-freeze.json').read_text())
    guard.source_guard(arm, freeze['workspace_sha256'])
    paths = preparation['arms'][arm]
    require(guard.generated_inventory(Path(paths['app']),Path(paths['sdk'])) == freeze['generated']
            and guard.sdk_membership(Path(paths['sdk'])) == freeze['sdk_membership'], 'qualified compiler inputs changed')
    compiler = json.loads((root/arm/'capture-compiler-receipt.json').read_text())
    require(compiler['status'] == 'PASS', 'capture compiler membership unqualified')
    archives = json.loads((root/arm/'sdk-archive-build-receipt.json').read_text())
    for archive in archives['archives'].values():
        require(sha(archive['path']) == archive['sha256'] and
                all(sha(path) == value for path,value in archive['objects'].items()), 'qualified SDK archive/object changed')
    manifest = json.loads((root/arm/'installed-bundle-freeze.json').read_text())
    require(manifest['source_revision'] == ARMS[arm], 'product source differs')
    identity = product(installed or manifest['app_path'], manifest)
    return dict(state='SOURCE_AND_PRODUCT_REUSED', arm=arm, source=ARMS[arm], manifest=manifest,
                identity=identity, application_path=manifest['app_path'], native_launches=0)
