#!/usr/bin/env python3
"""Check selected artifact references without executing helpers or changing evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import re


def select(value, pointer):
    if not pointer:
        return value
    if not pointer.startswith('/'):
        raise ValueError('pointer must be empty or an absolute JSON pointer')
    for segment in pointer[1:].split('/'):
        key = segment.replace('~1', '/').replace('~0', '~')
        value = value[int(key)] if isinstance(value, list) else value[key]
    return value


def references(value):
    if isinstance(value, dict):
        if 'path' in value and 'sha256' in value:
            yield value
        for child in value.values():
            yield from references(child)
    elif isinstance(value, list):
        for child in value:
            yield from references(child)


def inspect(value, repo, mapping=None):
    rows = []
    for ref in references(value):
        name, expected = ref['path'], ref['sha256']
        if not isinstance(name, str) or not isinstance(expected, str) or not re.fullmatch('[0-9a-f]{64}', expected):
            raise ValueError('malformed artifact reference')
        path = Path(name)
        if not path.is_absolute():
            path = Path(repo) / path
        if mapping:
            old, new = mapping
            if path.is_relative_to(old):
                path = new / path.relative_to(old)
        # Configuration is neither a restart artifact nor safe diagnostic output.
        if path.suffix == '.xcconfig':
            state = 'CONFIGURATION_EXCLUDED'
        elif path.is_symlink() or not path.is_file():
            state = 'MISSING_OR_REDIRECTED'
        else:
            state = 'MATCH' if hashlib.sha256(path.read_bytes()).hexdigest() == expected else 'CHANGED'
        rows.append(dict(path=name, resolved_path=str(path), state=state))
    if not rows:
        raise ValueError('selection contains no hashed file references')
    return dict(state='PASS' if all(r['state'] == 'MATCH' for r in rows) else 'INCOMPLETE',
                evidence_level='SELECTED_FILE_INTEGRITY_ONLY', transitive_closure_verified=False,
                files=len(rows), results=rows, native_admitted=False, gates_closed=[])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--owner', type=Path, required=True)
    parser.add_argument('--pointer', default='')
    parser.add_argument('--map-root', help='Inspect a relocated evidence tree as OLD=NEW; never rewrite references')
    args = parser.parse_args()
    mapping = None
    if args.map_root:
        old, separator, new = args.map_root.partition('=')
        if not separator or not Path(old).is_absolute() or not Path(new).is_absolute():
            parser.error('--map-root requires two absolute roots as OLD=NEW')
        mapping = Path(old), Path(new)
    value = select(json.loads(args.owner.read_text()), args.pointer)
    result = inspect(value, Path(__file__).resolve().parents[2], mapping)
    print(json.dumps(result, indent=2))
    return 0 if result['state'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
