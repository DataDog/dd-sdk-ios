#!/usr/bin/env python3
# Unless explicitly stated otherwise, all files in this repository are licensed under the
# Apache License Version 2.0. This product includes software developed at Datadog
# (https://www.datadoghq.com/). Copyright 2025-Present Datadog, Inc.
"""Import a reproducible precompute test snapshot; never edit imported JSON."""
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
import uuid
from pathlib import Path

REPOSITORY = 'https://github.com/DataDog/ffe-system-test-data.git'
PREFIX = 'precomputed-assignments/'
FILES = {
    'schemas/precomputed-assignment.schema.json': 'schema.json',
    'precomputed-assignments/README.md': 'README.md',
    'LICENSE': 'LICENSE',
    'NOTICE': 'NOTICE',
}


def git(source, *args):
    return subprocess.check_output(['git', '-C', str(source), *args])


def response_bytes(content):
    """Extract the top-level response without re-encoding any numeric token."""
    text = content.decode('utf-8')
    decoder = json.JSONDecoder()
    position = text.index('{') + 1
    while True:
        while text[position].isspace() or text[position] == ',':
            position += 1
        if text[position] == '}':
            raise ValueError('Fixture is missing response')
        key, position = decoder.raw_decode(text, position)
        while text[position].isspace():
            position += 1
        if text[position] != ':':
            raise ValueError('Invalid fixture object')
        position += 1
        while text[position].isspace():
            position += 1
        start = position
        _, position = decoder.raw_decode(text, position)
        if key == 'response':
            return text[start:position].encode('utf-8') + b'\n'


def signing_snapshot(source, sha):
    prefix = 'response-signing/v1/'
    manifest = json.loads(git(source, 'show', sha + ':' + prefix + 'manifest.json'))
    if manifest.get('schema_version') != 1 or not manifest.get('files'):
        raise ValueError('Missing or unsupported signing manifest')
    result = {}
    for name, metadata in manifest['files'].items():
        if not re.fullmatch(r'[a-z0-9-]+[.]json', name):
            raise ValueError('Invalid signing suite filename')
        raw = git(source, 'show', sha + ':' + prefix + name)
        if hashlib.sha256(raw).hexdigest() != metadata['sha256']:
            raise ValueError('Signing suite differs from the upstream manifest: ' + name)
        result[name] = raw
    for source_path, name in [('response-signing/README.md', 'README.md'),
                              (prefix + 'manifest.json', 'manifest.json'),
                              ('LICENSE', 'LICENSE'), ('NOTICE', 'NOTICE')]:
        result[name] = git(source, 'show', sha + ':' + source_path)
    result['index.json'] = (json.dumps(sorted(manifest['files']), indent=2) + '\n').encode()
    result['SOURCE.json'] = (json.dumps({
        'repository': REPOSITORY, 'commit': sha,
        'files': {p: hashlib.sha256(v).hexdigest() for p, v in sorted(result.items())},
    }, indent=2) + '\n').encode()
    return result


def snapshot(source, ref, signing=False):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/-]*', ref) or '..' in ref:
        raise ValueError('Invalid fixture revision')
    sha = git(source, 'rev-parse', '--verify', ref + '^{commit}').decode().strip()
    if not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise ValueError('Expected a full source commit SHA')
    if signing:
        return signing_snapshot(source, sha)
    result = {}
    for entry in git(source, 'ls-tree', '-rz', '--full-tree', sha).split(b'\0'):
        if not entry:
            continue
        metadata, raw_path = entry.split(b'\t', 1)
        path = raw_path.decode()
        target = FILES.get(path)
        if path.startswith(PREFIX + 'cases/') and path.endswith('.json'):
            target = path[len(PREFIX):]
        if target is None:
            continue
        mode, kind, blob = metadata.decode().split()
        if mode != '100644' or kind != 'blob':
            raise ValueError('Fixture entries must be ordinary files: ' + path)
        result[target] = git(source, 'cat-file', 'blob', blob)
    cases = sorted(p for p in result if p.startswith('cases/'))
    if not cases or not all(p in result for p in FILES.values()):
        raise ValueError('Missing or empty precomputed fixture corpus')
    for path in cases:
        data = json.loads(result[path])
        if not isinstance(data, dict) or data.get('name') != Path(path).stem:
            raise ValueError('Invalid fixture identity: ' + path)
        if not isinstance(data.get('evaluations'), list):
            raise TypeError('Missing evaluations: ' + path)
        result['responses/' + path] = response_bytes(result[path])
    result['index.json'] = (json.dumps(cases, indent=2) + '\n').encode()
    result['SOURCE.json'] = (json.dumps({
        'repository': REPOSITORY,
        'commit': sha,
        'files': {p: hashlib.sha256(v).hexdigest() for p, v in sorted(result.items())},
    }, indent=2) + '\n').encode()
    return result


def read_snapshot(destination):
    if not destination.exists():
        return {}
    result = {}
    for path in destination.rglob('*'):
        if path.is_symlink():
            raise ValueError('Snapshot must not contain symbolic links')
        if path.is_file() and path.suffix != '.meta':
            result[path.relative_to(destination).as_posix()] = path.read_bytes()
    return result


def verify(destination, signing=False):
    content = read_snapshot(destination)
    metadata = json.loads(content.pop('SOURCE.json'))
    if metadata['repository'] != REPOSITORY or not re.fullmatch(r'[0-9a-f]{40}', metadata['commit']):
        raise ValueError('Invalid source provenance')
    hashes = {p: hashlib.sha256(v).hexdigest() for p, v in sorted(content.items())}
    if hashes != metadata['files']:
        raise ValueError('Snapshot content differs from its recorded checksums')
    if signing:
        manifest = json.loads(content['manifest.json'])
        if manifest.get('schema_version') != 1 or not manifest.get('files'):
            raise ValueError('Missing or unsupported signing manifest')
        cases = sorted(manifest['files'])
        if json.loads(content['index.json']) != cases:
            raise ValueError('Stale signing suite index')
        for name, entry in manifest['files'].items():
            if hashes.get(name) != entry['sha256']:
                raise ValueError('Signing manifest checksum mismatch: ' + name)
        print(f"Verified {len(cases)} signing suites at {metadata['commit']}")
        return
    cases = sorted(p for p in content if p.startswith('cases/') and p.endswith('.json'))
    if not cases or json.loads(content['index.json']) != cases:
        raise ValueError('Missing, empty, or stale fixture index')
    print(f"Verified {len(cases)} fixtures at {metadata['commit']}")


def unity_metadata(destination):
    for asset in sorted(destination.rglob('*')):
        if asset.suffix == '.meta':
            continue
        meta = asset.with_name(asset.name + '.meta')
        if not meta.exists():
            guid = uuid.uuid5(uuid.NAMESPACE_URL, 'ffe-precomputed/' + asset.relative_to(destination).as_posix()).hex
            folder = 'folderAsset: yes\n' if asset.is_dir() else ''
            importer = 'DefaultImporter' if asset.is_dir() or asset.suffix != '.json' else 'TextScriptImporter'
            meta.write_text(f'fileFormatVersion: 2\nguid: {guid}\n{folder}{importer}:\n  externalObjects: {{}}\n  userData:\n  assetBundleName:\n  assetBundleVariant:\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--signing', action='store_true', help='Import or verify the response-signing snapshot')
    parser.add_argument('--ref', default='main')
    parser.add_argument('--source', type=Path, help='Read a local Git checkout at the requested committed revision')
    parser.add_argument('--verify', action='store_true', help='Verify local checksums and discovery index without network access')
    parser.add_argument('--check', action='store_true', help='Compare with the recorded upstream SHA; do not write')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    config = json.loads((root / 'ci/precomputed-fixtures.json').read_text())
    relative = Path(config['signing_destination' if args.signing else 'destination'])
    if relative.is_absolute() or '..' in relative.parts:
        raise ValueError('Destination must be inside the repository')
    destination = root / relative
    resolved = destination.resolve()
    if not resolved.is_relative_to(root):
        raise ValueError('Destination escapes the repository')
    if resolved == root or '.git' in relative.parts:
        raise ValueError('Destination must be a dedicated directory inside the repository')
    if resolved != destination:
        raise ValueError('Destination must not contain symbolic links')
    if destination.exists():
        if not destination.is_dir():
            raise ValueError('Destination must be a directory')
        if any(destination.iterdir()):
            provenance = destination / 'SOURCE.json'
            if not provenance.is_file():
                raise ValueError('Destination must be empty or contain a previous snapshot')
            metadata = json.loads(provenance.read_text())
            if metadata.get('repository') != REPOSITORY or not isinstance(metadata.get('files'), dict):
                raise ValueError('Destination must contain valid snapshot provenance')
            extra = read_snapshot(destination).keys() - metadata['files'].keys() - {'SOURCE.json'}
            if extra:
                raise ValueError('Destination contains files outside the previous snapshot')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/-]*', args.ref) or '..' in args.ref:
        raise ValueError('Invalid fixture revision')
    if args.verify:
        verify(destination, args.signing)
        return
    before = read_snapshot(destination)
    ref = json.loads(before['SOURCE.json'])['commit'] if args.check else args.ref
    with tempfile.TemporaryDirectory(prefix='ffe-precompute-') as temporary:
        source = args.source
        if source is None:
            source = Path(temporary) / 'source'
            subprocess.run(['git', 'init', '-q', str(source)], check=True)
            subprocess.run(['git', '-C', str(source), 'fetch', '-q', '--depth=1', REPOSITORY, ref], check=True)
            ref = 'FETCH_HEAD'
        after = snapshot(source, ref, args.signing)
        changed = {p:v for p,v in before.items() if p != 'SOURCE.json'} != {p:v for p,v in after.items() if p != 'SOURCE.json'}
        if args.check:
            if before != after:
                raise ValueError('Snapshot differs from its recorded source commit')
        elif changed:
            destination.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.TemporaryDirectory(prefix='.precompute-', dir=destination.parent) as staging:
                staged = Path(staging) / 'snapshot'
                staged.mkdir()
                for path, content in after.items():
                    output = staged / path
                    output.parent.mkdir(parents=True, exist_ok=True)
                    output.write_bytes(content)
                # Preserve Unity's existing asset identities when refreshing a snapshot.
                if destination.exists():
                    for meta in destination.rglob('*.meta'):
                        rel = meta.relative_to(destination)
                        asset = staged / str(rel)[:-5]
                        if asset.exists():
                            (staged / rel).write_bytes(meta.read_bytes())
                    backup = Path(staging) / 'previous'
                    destination.rename(backup)
                    try:
                        staged.rename(destination)
                    except BaseException:
                        backup.rename(destination)
                        raise
                else:
                    staged.rename(destination)
        if config.get('unityMetadata') and not args.check:
            unity_metadata(destination)
        selected = before if args.check or not changed else after
        metadata = json.loads(selected['SOURCE.json'])
        count = len(json.loads(selected['index.json']))
        print(f"FFE precomputed fixtures: {metadata['commit']}; {count} files; changed={str(changed).lower()}")
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
                output.write(f"changed={str(changed).lower()}\nsource_commit={metadata['commit']}\nfixture_count={count}\n")


if __name__ == '__main__':
    main()
