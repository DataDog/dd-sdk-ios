"""Qualify fresh signed F08 products with the established compiler/archive checks.

The original unsigned qualifier remains immutable for its frozen receipts. This
variant adds only the source-declared simulator signing transition to that contract.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import plistlib
import shlex
import stat
import time
import subprocess

from capture_build import save, sha
from capture_product import MACH_O, archive_members, archive_build_receipt
from signing_contract import packaged_entitlements, source_entitlements, signing_link_transition, signing_inventory


def qualify(root, arm, archive_sha=None):
    preparation = json.loads((root / 'preparation.json').read_text())
    accepted = Path(preparation['accepted_build_root'])
    reference = json.loads((accepted / arm / 'installed-bundle-freeze.json').read_text())
    build = json.loads((root / arm / 'build-receipt.json').read_text())
    compiler = json.loads((root / arm / 'capture-compiler-receipt.json').read_text())
    assert build['status'] == compiler['status'] == 'PASS'
    if archive_sha is None:
        archive_receipt = archive_build_receipt(root, arm, reference)
    else:
        path=root/arm/'sdk-archive-build-receipt.json'
        assert sha(path)==archive_sha, 'Saved archive qualification changed'
        archive_receipt=json.loads(path.read_text())
        assert archive_receipt['status']=='SOURCE_BOUND_CURRENT_BUILD_ARCHIVES'
        for key,name in [('build_receipt_sha256','build-receipt.json'),
                         ('input_freeze_sha256','build-input-freeze.json'),
                         ('compiler_receipt_sha256','capture-compiler-receipt.json')]:
            assert archive_receipt[key]==sha(root/arm/name), 'Saved archive input changed'
        assert set(archive_receipt['archives'])==set(reference['static_sdk_archives'])
        for row in archive_receipt['archives'].values():
            assert sha(row['path'])==row['sha256']
            assert all(sha(path)==value for path,value in row['objects'].items()), 'Saved compiler object changed'
            members,symbol=archive_members(Path(row['path']).read_bytes())
            assert members==row['members'] and symbol==row['symbol_table']
    deadline = datetime.datetime.fromisoformat(json.loads((root / arm / 'build-admission.json').read_text())['deadline']).timestamp()

    def command(arguments):
        remaining = deadline - time.time()
        assert remaining > 0, 'Original build qualification deadline expired'
        return subprocess.check_output(arguments, text=True, timeout=min(30, remaining))

    app = Path(build['app_path'])
    old_app = Path(reference['app_path'])
    derived = root / arm / 'DerivedData'
    old_derived = accepted / arm / 'DerivedData'
    files, links, binaries = {}, {}, {}
    for path in sorted(app.rglob('*')):
        name = str(path.relative_to(app))
        if path.is_symlink():
            assert path.resolve(strict=True).is_relative_to(app), 'Product symlink escapes bundle'
            links[name] = os.readlink(path)
        elif path.is_file():
            metadata = path.stat()
            files[name] = dict(sha256=sha(path), size=metadata.st_size, mode=stat.S_IMODE(metadata.st_mode))
            with path.open('rb') as source:
                if source.read(4) in MACH_O:binaries[name] = files[name]['sha256']
    signature_files = signing_inventory(files, reference['files'])
    assert links == reference['symlinks'], 'Product symlink inventory differs'
    assert set(binaries) == set(reference['mach_o']), 'Full Mach-O inventory differs'
    assert all(files[name]['mode'] == old['mode'] for name, old in reference['files'].items()), 'Product file modes differ'
    for name in binaries:
        assert command(['xcrun', 'lipo', '-archs', str(app / name)]).strip() == command(['xcrun', 'lipo', '-archs', str(old_app / name)]).strip(), (name, 'architecture differs')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    old_info = plistlib.loads((old_app / 'Info.plist').read_bytes())
    for key in ('CFBundleIdentifier', 'CFBundleExecutable', 'DTSDKName', 'DTXcode', 'MinimumOSVersion', 'GitShortSHA'):
        assert info.get(key) == old_info.get(key), (key, 'bundle build identity differs')
    assert info['DTSDKName'] == 'iphonesimulator27.1'
    for key in ('RUMReleaseValidationClientToken', 'RUMReleaseValidationApplicationID'):
        assert info[key] == old_info[key], 'Controlled configuration differs'
    dylib = app / (info['CFBundleExecutable'] + '.debug.dylib')
    dynamic_links = command(['xcrun', 'otool', '-L', str(dylib)])
    assert dynamic_links.replace(str(app), str(old_app)) == reference['debug_dylib_links'], 'Dynamic dependency inventory differs'
    assert 'ReleaseValidationCapture' in command(['xcrun', 'nm', '-g', str(dylib)]), 'Capture not present in linked app code'
    log = (root / arm / 'build.log').read_text()
    commands = []
    for line in log.splitlines():
        if not line.strip().startswith('/Applications/') or ' -o ' + str(dylib) not in line:continue
        tokens = shlex.split(line)
        if tokens[tokens.index('-o') + 1] == str(dylib):commands.append(tokens)
    assert len(commands) == 1, 'Missing or ambiguous final app link command'
    final = commands[0]
    unsigned_options, section_paths = signing_link_transition(final, derived, embedded=False)
    normalized = [token.replace(str(derived), str(old_derived)) for token in unsigned_options]
    assert normalized == reference['final_link_command'], 'Final linker options or search paths differ'
    searches = [Path(final[index + 1]) for index, token in enumerate(final[:-1]) if token == '-F']
    searches.extend(Path(token[2:]) for token in final if token.startswith('-F') and len(token) > 2)
    frameworks = [final[index + 1] for index, token in enumerate(final[:-1]) if token == '-framework']
    archives = {}
    for name in reference['static_sdk_archives']:
        assert frameworks.count(name) == 1, (name, 'SDK link membership differs')
        paths = [directory / (name + '.framework') / name for directory in searches]
        resolved = next((path for path in paths if path.is_file()), None)
        expected = derived / 'Build/Products/Debug-iphonesimulator' / (name + '.framework') / name
        assert resolved == expected and resolved.resolve() == expected, (name, 'foreign SDK archive resolution')
        with resolved.open('rb') as source:assert source.read(8) == b'!<arch>\n', (name, 'SDK is not a static archive')
        binding = archive_receipt["archives"][name]
        assert str(resolved) == binding["path"] and sha(resolved) == binding["sha256"], "Link-resolved archive differs from the current qualified producer"
        members, symbol = archive_members(resolved.read_bytes())
        assert members == binding["members"] and symbol == binding["symbol_table"], "Link-resolved members differ"
        archives[name] = dict(path=str(resolved), sha256=sha(resolved))
    lists = [Path(final[index + 1]) for index, token in enumerate(final[:-1]) if token == '-filelist']
    assert len(lists) == 1 and lists[0].is_relative_to(derived)
    entries = [Path(line.strip().strip('"')) for line in lists[0].read_text().splitlines() if line.strip()]
    old_list = Path(reference['app_link_filelist']['path'])
    old_entries = [str(Path(line.strip().strip('"')).relative_to(old_derived)) for line in old_list.read_text().splitlines() if line.strip()]
    assert [str(path.relative_to(derived)) for path in entries] == old_entries
    assert all(path.is_file() for path in entries) and len(entries) == len(set(entries))
    assert time.time() < deadline, 'Product qualification publication is late'
    result = dict(arm=arm, frozen_at=datetime.datetime.now(datetime.timezone.utc).isoformat(), app_path=str(app),
                  source_revision=build['source_revision'], application_revision=reference['application_revision'],
                  sdk_version=reference['sdk_version'], files=files, symlinks=links, mach_o=binaries,
                  debug_dylib_links=dynamic_links, static_sdk_archives=archives, final_link_command=final,
                  app_link_filelist=dict(path=str(lists[0]), sha256=sha(lists[0]), objects=len(entries)),
                  build_receipt_sha256=sha(root / arm / 'build-receipt.json'),
                  input_freeze_sha256=sha(root / arm / 'build-input-freeze.json'),
                  capture_compiler_sha256=sha(root / arm / 'capture-compiler-receipt.json'),
                  archive_build_receipt_sha256=sha(root / arm / 'sdk-archive-build-receipt.json'),
                  qualifier_sha256=sha(__file__), postflight=build['postflight'])
    source_root = Path(preparation['arms'][arm]['app'])
    declared = plistlib.loads((source_root / 'Derived/Entitlements/DatadogApp.entitlements').read_bytes())
    def launcher_command(build_log, executable):
        matches=[]
        for line in build_log.splitlines():
            if not line.strip().startswith('/Applications/') or ' -o ' + str(executable) not in line:continue
            tokens=shlex.split(line)
            if tokens[tokens.index('-o')+1] == str(executable):matches.append(tokens)
        assert len(matches)==1, 'Missing or ambiguous launcher link command'
        return matches[0]
    launcher=app/info['CFBundleExecutable']
    launcher_options=launcher_command(log,launcher)
    unsigned_launcher,section_paths=signing_link_transition(launcher_options,derived,embedded=True)
    old_launcher=old_app/info['CFBundleExecutable']
    old_launcher_options=launcher_command((accepted/arm/'build.log').read_text(),old_launcher)
    assert [token.replace(str(derived),str(old_derived)) for token in unsigned_launcher]==old_launcher_options, 'Launcher link options differ beyond signing'
    xml=Path(section_paths['__entitlements']).read_bytes()
    der=Path(section_paths['__ents_der']).read_bytes()
    simulated=plistlib.loads(xml)
    effective=packaged_entitlements(launcher.read_bytes(),xml,der)
    # Xcode's simulated and code-signature planes are retained separately.
    signed = command(['codesign', '-d', '--entitlements', ':-', str(app)])
    signed = plistlib.loads(signed.encode()) if signed.strip() else {}
    signed_input=Path(section_paths['__entitlements'].replace('-Simulated.xcent','.xcent'))
    assert signed == plistlib.loads(signed_input.read_bytes()), 'Code-signature packaging input differs'
    for key in set(signed) & set(effective):
        assert signed[key] == effective[key], 'Conflicting signed/simulated entitlement'
    identity = source_entitlements(declared, effective, info, 'JKFCB4CN7C')
    command(['codesign', '--verify', '--deep', '--strict', str(app)])
    result['simulator_signing'] = dict(identity=identity, signed_entitlements=signed,
        simulated_entitlements=simulated, signature_files=signature_files,
        packaging_inputs={name:dict(path=path, sha256=sha(path)) for name,path in section_paths.items()},
        source_entitlements_sha256=sha(source_root / 'Derived/Entitlements/DatadogApp.entitlements'),
        signed_packaging_input=dict(path=str(signed_input),sha256=sha(signed_input)),
        omitted_source_entitlements=sorted(set(declared)-set(effective)), launcher_link_command=launcher_options,
        source= 'Existing generated entitlements and Xcode simulator packaging; no injection')
    save(root / arm / 'installed-bundle-freeze.json', result)
    assert time.time() < deadline, 'Product qualification publication is late'
    return dict(arm=arm, status='PRODUCT_FROZEN', files=len(files), mach_o=len(binaries), sdk_archives=len(archives), native_launches=0)

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root',type=Path)
    parser.add_argument('arm',choices=['baseline','candidate'])
    parser.add_argument('--archive-receipt-sha256')
    args=parser.parse_args();root=args.root.resolve(strict=True)
    outcome=dict(status='INVALID',arm=args.arm,native_launches=0)
    try:
        outcome.update(qualify(root,args.arm,args.archive_receipt_sha256))
        outcome['manifest_sha256']=sha(root/args.arm/'installed-bundle-freeze.json')
    except Exception as error:
        outcome['reason']=str(error)
        raise
    finally:
        outcome['finished_at']=datetime.datetime.now(datetime.timezone.utc).isoformat()
        save(root/args.arm/('product-reassessment.json' if args.archive_receipt_sha256 else 'product-qualification.json'),outcome)
    print(json.dumps(outcome))
