#!/usr/bin/env python3
# Unless explicitly stated otherwise, all files in this repository are licensed under the
# Apache License Version 2.0. This product includes software developed at Datadog
# (https://www.datadoghq.com/). Copyright 2025-Present Datadog, Inc.
"""Fetch pinned ffe-system-test-data snapshots into git-ignored folders; never edit imported files.

ci/feature-flags-precomputed-fixtures.json lists the sources. Each source has its own upstream path prefix,
destination folder, commit pin and file map, so later fixture sets reuse this pipeline.
The default mode materializes every pin; --update moves the pins.

Source kinds:
- `precomputed-assignments`: the case corpus under `<prefix>cases/`, with extracted responses and an index.
- `files`: every file under the prefix, copied byte for byte, with an index.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

REPOSITORY = 'https://github.com/DataDog/ffe-system-test-data.git'
KINDS = {'precomputed-assignments', 'files'}


# Files that the OS writes into folders (for example Finder on macOS). They are never part of a snapshot.
IGNORED_NAMES = {'.DS_Store'}


def fetch(source, ref):
    """Shallow-fetch one revision, with a time limit and retries, so a slow network cannot stall a test run."""
    subprocess.run(['git', 'init', '-q', str(source)], check=True)
    command = ['git', '-c', 'http.lowSpeedLimit=1000', '-c', 'http.lowSpeedTime=30',
               '-C', str(source), 'fetch', '-q', '--depth=1', REPOSITORY, ref]
    for attempt in range(1, 4):
        try:
            if subprocess.run(command, timeout=180).returncode == 0:
                return
        except subprocess.TimeoutExpired:
            pass
        if attempt < 3:
            time.sleep(5 * attempt)
    raise SystemExit(f'Could not fetch {REPOSITORY} at {ref}. Check access to github.com, '
                     'or pass --source <local ffe-system-test-data checkout that contains this commit>.')


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


def indexed(spec, result):
    """The files that the index lists: the cases for `precomputed-assignments`, every prefix file for `files`."""
    if spec['kind'] == 'precomputed-assignments':
        return sorted(p for p in result if p.startswith('cases/') and p.endswith('.json'))
    extra = set(spec['files'].values())
    return sorted(p for p in result if p not in extra and p not in {'index.json', 'SOURCE.json'}
                  and not p.endswith('.meta'))


def snapshot(source, ref, spec):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/-]*', ref) or '..' in ref:
        raise ValueError('Invalid fixture revision')
    sha = git(source, 'rev-parse', '--verify', ref + '^{commit}').decode().strip()
    if not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise ValueError('Expected a full source commit SHA')
    prefix = spec['prefix']
    result = {}
    for entry in git(source, 'ls-tree', '-rz', '--full-tree', sha).split(b'\0'):
        if not entry:
            continue
        metadata, raw_path = entry.split(b'\t', 1)
        path = raw_path.decode()
        target = spec['files'].get(path)
        if spec['kind'] == 'precomputed-assignments':
            if path.startswith(prefix + 'cases/') and path.endswith('.json'):
                target = path[len(prefix):]
        elif target is None and path.startswith(prefix):
            target = path[len(prefix):]
        if target is None:
            continue
        if target in {'index.json', 'SOURCE.json'} or target.startswith('responses/'):
            raise ValueError('Fixture path is reserved: ' + path)
        mode, kind, blob = metadata.decode().split()
        if mode not in {'100644', '100755'} or kind != 'blob':
            raise ValueError('Fixture entries must be ordinary files: ' + path)
        result[target] = git(source, 'cat-file', 'blob', blob)
    files = indexed(spec, result)
    if not files or not all(p in result for p in spec['files'].values()):
        raise ValueError(f"Missing or empty fixture set for {spec['name']}")
    if spec['kind'] == 'precomputed-assignments':
        for path in files:
            data = json.loads(result[path])
            if not isinstance(data, dict) or data.get('name') != Path(path).stem:
                raise ValueError('Invalid fixture identity: ' + path)
            if not isinstance(data.get('evaluations'), list):
                raise TypeError('Missing evaluations: ' + path)
            result['responses/' + path] = response_bytes(result[path])
    result['index.json'] = (json.dumps(files, indent=2) + '\n').encode()
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
        if path.is_file() and path.suffix != '.meta' and path.name not in IGNORED_NAMES:
            result[path.relative_to(destination).as_posix()] = path.read_bytes()
    return result


def verify(destination, spec):
    content = read_snapshot(destination)
    metadata = json.loads(content.pop('SOURCE.json'))
    if metadata['repository'] != REPOSITORY or not re.fullmatch(r'[0-9a-f]{40}', metadata['commit']):
        raise ValueError('Invalid source provenance')
    hashes = {p: hashlib.sha256(v).hexdigest() for p, v in sorted(content.items())}
    if hashes != metadata['files']:
        raise ValueError('Snapshot content differs from its recorded checksums')
    files = indexed(spec, content)
    if not files or json.loads(content['index.json']) != files:
        raise ValueError('Missing, empty, or stale fixture index')
    print(f"Verified {spec['name']}: {len(files)} fixtures at {metadata['commit']}")


def unity_metadata(destination, name):
    namespace = 'ffe-precomputed/' if name == 'precomputed-assignments' else 'ffe-' + name + '/'
    for asset in sorted(destination.rglob('*')):
        if asset.suffix == '.meta':
            continue
        meta = asset.with_name(asset.name + '.meta')
        if not meta.exists():
            guid = uuid.uuid5(uuid.NAMESPACE_URL, namespace + asset.relative_to(destination).as_posix()).hex
            folder = 'folderAsset: yes\n' if asset.is_dir() else ''
            importer = 'DefaultImporter' if asset.is_dir() or asset.suffix != '.json' else 'TextScriptImporter'
            meta.write_text(f'fileFormatVersion: 2\nguid: {guid}\n{folder}{importer}:\n  externalObjects: {{}}\n  userData:\n  assetBundleName:\n  assetBundleVariant:\n')


def write_snapshot(destination, after):
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


def load_sources(config):
    """Validate the manifest: a non-empty list of sources with unique names and destinations."""
    sources = config.get('sources')
    if not isinstance(sources, list) or not sources:
        raise ValueError('ci/feature-flags-precomputed-fixtures.json must list at least one source')
    names, destinations = set(), set()
    for spec in sources:
        name = spec.get('name')
        if not isinstance(name, str) or not re.fullmatch(r'[a-z0-9][a-z0-9-]*', name) or name in names:
            raise ValueError('Each source needs a unique lowercase name')
        if spec.get('kind') not in KINDS:
            raise ValueError(f'Source {name} has an unknown kind')
        prefix = spec.get('prefix')
        if not isinstance(prefix, str) or not re.fullmatch(r'([A-Za-z0-9._-]+/)+', prefix) or '..' in prefix:
            raise ValueError(f'Source {name} needs a folder prefix that ends with /')
        if not isinstance(spec.get('commit'), str) or not re.fullmatch(r'[0-9a-f]{40}', spec['commit']):
            raise ValueError(f'Source {name} must pin a full upstream commit SHA')
        spec.setdefault('files', {})
        if not isinstance(spec['files'], dict) or not all(isinstance(k, str) and isinstance(v, str)
                                                          for k, v in spec['files'].items()):
            raise ValueError(f'Source {name} has an invalid file map')
        if any(not Path(path).parts or Path(path).is_absolute() or '..' in Path(path).parts
               for path in spec['files'].values()):
            raise ValueError(f'Source {name} file map must stay inside the snapshot')
        if spec.get('destination') in destinations:
            raise ValueError(f'Source {name} reuses a destination')
        names.add(name)
        destinations.add(spec.get('destination'))
    return sources


def destination_for(root, spec):
    relative = Path(spec['destination'])
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
    if subprocess.run(['git', '-C', str(root), 'ls-files', '--error-unmatch', '--', str(relative)],
                      capture_output=True).returncode == 0:
        raise ValueError('Destination must not be tracked by git; add it to .gitignore')
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
    return destination


def sync(root, spec, args):
    """Fetch, verify or update one source. Return (commit, file count, pin changed)."""
    pin = spec['commit']
    destination = destination_for(root, spec)
    before = read_snapshot(destination)
    current = json.loads(before['SOURCE.json'])['commit'] if 'SOURCE.json' in before else None
    if args.verify:
        if current != pin:
            raise ValueError(f"Fetched {spec['name']} snapshot ({current}) does not match the pin ({pin}); "
                             'run without --verify')
        verify(destination, spec)
        return pin, len(json.loads(before['index.json'])), False
    ref = (args.ref or 'main') if args.update else pin
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/-]*', ref) or '..' in ref:
        raise ValueError('Invalid fixture revision')
    if not args.update and current == pin:
        verify(destination, spec)
        after = before
    else:
        with tempfile.TemporaryDirectory(prefix='ffe-precompute-') as temporary:
            source = args.source
            fetched = source is None
            if fetched:
                source = Path(temporary) / 'source'
                fetch(source, ref)
                ref = 'FETCH_HEAD'
            after = snapshot(source, ref, spec)
            pinned = before if current == pin else None
            if args.update and pinned is None and json.loads(after['SOURCE.json'])['commit'] != pin:
                # A fresh checkout has no local snapshot, so read the pinned one to compare.
                try:
                    if fetched:
                        fetch(source, pin)
                        pinned = snapshot(source, 'FETCH_HEAD', spec)
                    else:
                        pinned = snapshot(source, pin, spec)
                except (Exception, SystemExit):  # pylint: disable=broad-except
                    # Without a readable pinned snapshot, the new commit counts as a change.
                    pinned = None
        # An upstream commit that changes no imported file keeps the pin.
        if pinned is not None and json.loads(after['SOURCE.json'])['commit'] != pin \
                and {k: v for k, v in pinned.items() if k != 'SOURCE.json'} == \
                {k: v for k, v in after.items() if k != 'SOURCE.json'}:
            after = pinned
        if before != after:
            write_snapshot(destination, after)
    if spec.get('unityMetadata'):
        unity_metadata(destination, spec['name'])
    commit = json.loads(after['SOURCE.json'])['commit']
    return commit, len(json.loads(after['index.json'])), commit != pin


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--update', action='store_true', help='Pin a new upstream revision for every source, then fetch it')
    parser.add_argument('--ref', help='Revision to pin with --update (default: main)')
    parser.add_argument('--source', type=Path, help='Read a local Git checkout instead of fetching')
    parser.add_argument('--verify', action='store_true', help='Verify the fetched snapshots against the pins without network access')
    args = parser.parse_args()
    if args.ref is not None and not args.update:
        parser.error('--ref requires --update; the default run fetches the pins')
    if args.verify and args.update:
        parser.error('Use either --verify or --update')
    root = Path(__file__).resolve().parent.parent
    config_path = root / 'ci/feature-flags-precomputed-fixtures.json'
    config = json.loads(config_path.read_text())
    sources = load_sources(config)
    changes = []
    total = 0
    for spec in sources:
        commit, count, changed = sync(root, spec, args)
        total += count
        print(f"Feature flags fixtures {spec['name']}: {commit}; {count} files; pin changed={str(changed).lower()}")
        if changed:
            spec['commit'] = commit
            changes.append(f"{spec['name']}@{commit}")
    if changes:
        config_path.write_text(json.dumps(config, indent=2) + '\n')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(f"changed={str(bool(changes)).lower()}\nsource_commit={', '.join(changes)}\n"
                         f"fixture_count={total}\n")


if __name__ == '__main__':
    main()
