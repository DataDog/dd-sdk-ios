#!/usr/bin/env python3
# Unless explicitly stated otherwise, all files in this repository are licensed under the
# Apache License Version 2.0. This product includes software developed at Datadog
# (https://www.datadoghq.com/). Copyright 2025-Present Datadog, Inc.
"""Import a reproducible response-signing test snapshot; never edit imported JSON."""
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

REPOSITORY = 'https://github.com/DataDog/ffe-system-test-data.git'


def git(source, *args):
    return subprocess.check_output(['git', '-C', str(source), *args])


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


def snapshot(source, ref):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/-]*', ref) or '..' in ref:
        raise ValueError('Invalid fixture revision')
    sha = git(source, 'rev-parse', '--verify', ref + '^{commit}').decode().strip()
    if not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise ValueError('Expected a full source commit SHA')
    return signing_snapshot(source, sha)


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


def verify(destination):
    content = read_snapshot(destination)
    metadata = json.loads(content.pop('SOURCE.json'))
    if metadata['repository'] != REPOSITORY or not re.fullmatch(r'[0-9a-f]{40}', metadata['commit']):
        raise ValueError('Invalid source provenance')
    hashes = {p: hashlib.sha256(v).hexdigest() for p, v in sorted(content.items())}
    if hashes != metadata['files']:
        raise ValueError('Snapshot content differs from its recorded checksums')
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ref', default='main')
    parser.add_argument('--source', type=Path, help='Read a local Git checkout at the requested committed revision')
    parser.add_argument('--verify', action='store_true', help='Verify local checksums and discovery index without network access')
    parser.add_argument('--check', action='store_true', help='Compare with the recorded upstream SHA; do not write')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    config = json.loads((root / 'ci/response-signing-fixtures.json').read_text())
    relative = Path(config['destination'])
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
        verify(destination)
        return
    before = read_snapshot(destination)
    ref = json.loads(before['SOURCE.json'])['commit'] if args.check else args.ref
    with tempfile.TemporaryDirectory(prefix='ffe-response-signing-') as temporary:
        source = args.source
        if source is None:
            source = Path(temporary) / 'source'
            subprocess.run(['git', 'init', '-q', str(source)], check=True)
            subprocess.run(['git', '-C', str(source), 'fetch', '-q', '--depth=1', REPOSITORY, ref], check=True)
            ref = 'FETCH_HEAD'
        after = snapshot(source, ref)
        changed = {p:v for p,v in before.items() if p != 'SOURCE.json'} != {p:v for p,v in after.items() if p != 'SOURCE.json'}
        if args.check:
            if before != after:
                raise ValueError('Snapshot differs from its recorded source commit')
        elif changed:
            destination.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.TemporaryDirectory(prefix='.response-signing-', dir=destination.parent) as staging:
                staged = Path(staging) / 'snapshot'
                staged.mkdir()
                for path, content in after.items():
                    output = staged / path
                    output.parent.mkdir(parents=True, exist_ok=True)
                    output.write_bytes(content)
                if destination.exists():
                    backup = Path(staging) / 'previous'
                    destination.rename(backup)
                    try:
                        staged.rename(destination)
                    except BaseException:
                        backup.rename(destination)
                        raise
                else:
                    staged.rename(destination)
        selected = before if args.check or not changed else after
        metadata = json.loads(selected['SOURCE.json'])
        count = len(json.loads(selected['index.json']))
        print(f"FFE response-signing fixtures: {metadata['commit']}; {count} files; changed={str(changed).lower()}")
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
                output.write(f"changed={str(changed).lower()}\nsource_commit={metadata['commit']}\nfixture_count={count}\n")


if __name__ == '__main__':
    main()
