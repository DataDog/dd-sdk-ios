"""Freeze complete F08 capture products after their source-bound build qualification."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shlex
import stat
import subprocess
import time

from capture_build import save, sha

MACH_O = {bytes.fromhex(value) for value in ('feedface', 'feedfacf', 'cefaedfe', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}


def archive_members(raw):
    assert raw.startswith(b"!<arch>\n"), "Not a static archive"
    position, result, symbols = 8, {}, []
    while position < len(raw):
        header = raw[position:position + 60]
        assert len(header) == 60 and header[58:] == b"`\n", "Invalid archive header"
        size = int(header[48:58])
        assert size >= 0 and position + 60 + size <= len(raw), "Truncated archive member"
        name = header[:16].decode().strip()
        payload = raw[position + 60:position + 60 + size]
        if name.startswith("#1/"):
            length = int(name[3:])
            assert 0 < length <= size, "Invalid extended archive name"
            name, payload = payload[:length].rstrip(b"\0").decode(), payload[length:]
        else:
            name = name.rstrip("/")
        digest = hashlib.sha256(payload).hexdigest()
        if name in {"__.SYMDEF", "__.SYMDEF SORTED"}:
            symbols.append(dict(name=name, sha256=digest))
        else:
            assert Path(name).name == name and name.endswith(".o") and name not in result, "Foreign or duplicate archive member"
            result[name] = digest
        position += 60 + size + size % 2
    assert position == len(raw) and len(symbols) == 1 and result, "Archive inventory incomplete"
    return result, symbols[0]


def archive_build_receipt(root, arm, reference):
    destination = root / arm / "sdk-archive-build-receipt.json"
    assert not destination.exists(), "Archive build receipt already exists"
    freeze = json.loads((root / arm / "build-input-freeze.json").read_text())
    preparation = json.loads((root / "preparation.json").read_text())
    accepted = Path(preparation["accepted_build_root"])
    derived = root / arm / "DerivedData"
    old_derived = accepted / arm / "DerivedData"
    log = (root / arm / "build.log").read_text().splitlines()
    old_log = (accepted / arm / "build.log").read_text().splitlines()

    def producer(lines, output):
        commands = []
        for line in lines:
            if not line.strip().startswith("/Applications/") or " -o " + str(output) not in line:continue
            tokens = shlex.split(line)
            if Path(tokens[0]).name == "libtool" and tokens[tokens.index("-o") + 1] == str(output):commands.append(tokens)
        assert len(commands) == 1, "Missing or ambiguous libtool producer"
        return commands[0]

    archives = {}
    assert set(reference["static_sdk_archives"]) == set(freeze["sdk_membership"])
    for name, source in freeze["sdk_membership"].items():
        output = derived / "Build/Products/Debug-iphonesimulator" / (name + ".framework") / name
        old_output = Path(reference["static_sdk_archives"][name]["path"])
        command = producer(log, output)
        normalized = [token.replace(str(derived), str(old_derived)) for token in command]
        assert normalized == producer(old_log, old_output), (name, "libtool flags or inputs differ")
        filelists = [Path(command[index + 1]) for index, token in enumerate(command[:-1]) if token == "-filelist"]
        folder = derived / "Build/Intermediates.noindex/Datadog.build/Debug-iphonesimulator" / (name + ".build") / "Objects-normal/arm64"
        assert filelists == [folder / (name + ".LinkFileList")]
        objects = [Path(line.strip().strip('"')) for line in filelists[0].read_text().splitlines() if line.strip()]
        wanted = {Path(path).stem + ".o" for path in source["files"]} | {name + "_vers.o"}
        assert len(wanted) == len(source["files"]) + 1
        assert len(objects) == len(set(objects)) == len(wanted)
        assert {path.name for path in objects} == wanted and all(path.parent == folder for path in objects), "Foreign or missing compiler object"
        version = folder.parent.parent / "DerivedSources" / (name + "_vers.c")
        old_version = Path(str(version).replace(str(derived), str(old_derived)))
        assert version.read_bytes() == old_version.read_bytes(), "Unqualified generated version object source"
        hashes = {path.name: sha(path) for path in objects}
        members, symbol = archive_members(output.read_bytes())
        assert members == hashes, (name, "Archive members differ from source-qualified compiler outputs")
        archives[name] = dict(path=str(output), sha256=sha(output), producer=command, normalized_producer=normalized,
                              filelist=dict(path=str(filelists[0]), sha256=sha(filelists[0])),
                              objects={str(path): hashes[path.name] for path in objects}, members=members, symbol_table=symbol)
    receipt = dict(status="SOURCE_BOUND_CURRENT_BUILD_ARCHIVES", archives=archives,
                   build_receipt_sha256=sha(root / arm / "build-receipt.json"),
                   input_freeze_sha256=sha(root / arm / "build-input-freeze.json"),
                   compiler_receipt_sha256=sha(root / arm / "capture-compiler-receipt.json"))
    save(destination, receipt)
    return receipt


def qualify(root, arm):
    preparation = json.loads((root / 'preparation.json').read_text())
    accepted = Path(preparation['accepted_build_root'])
    reference = json.loads((accepted / arm / 'installed-bundle-freeze.json').read_text())
    build = json.loads((root / arm / 'build-receipt.json').read_text())
    compiler = json.loads((root / arm / 'capture-compiler-receipt.json').read_text())
    assert build['status'] == compiler['status'] == 'PASS'
    archive_receipt = archive_build_receipt(root, arm, reference)
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
    assert set(files) == set(reference['files']), 'Product file inventory differs'
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
    normalized = [token.replace(str(derived), str(old_derived)) for token in final]
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
    save(root / arm / 'installed-bundle-freeze.json', result)
    assert time.time() < deadline, 'Product qualification publication is late'
    return dict(arm=arm, status='PRODUCT_FROZEN', files=len(files), mach_o=len(binaries), sdk_archives=len(archives), native_launches=0)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('arm', choices=['baseline', 'candidate'])
    arguments = parser.parse_args()
    root = arguments.root.resolve(strict=True)
    receipt = root / arguments.arm / 'product-qualification.json'
    assert not receipt.exists(), 'Product qualification already attempted'
    outcome = dict(status='INVALID', arm=arguments.arm, native_launches=0)
    try:
        outcome.update(qualify(root, arguments.arm))
        outcome['manifest_sha256'] = sha(root / arguments.arm / 'installed-bundle-freeze.json')
    except Exception as error:
        outcome['reason'] = str(error)
        raise
    finally:
        outcome['finished_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        save(receipt, outcome)
    deadline = datetime.datetime.fromisoformat(json.loads((root / arguments.arm / 'build-admission.json').read_text())['deadline']).timestamp()
    if time.time() >= deadline:
        save(root / arguments.arm / 'late-product-publication.json', dict(status='INVALID', deadline=deadline, finished_at=time.time()))
        raise TimeoutError('Product verdict publication exceeded the original deadline')
    print(json.dumps(outcome))
