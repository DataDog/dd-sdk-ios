"""Rebuild the controlled app with its existing Xcode simulator signing contract."""
import argparse
import ast
import copy
import datetime
import inspect
import json
from pathlib import Path

import capture_build
from capture_build import save, sha


def enable_signing(source):
    """Allow exactly the reviewed flag change in the immutable accepted driver."""
    tree = ast.parse(source)
    assert len(tree.body) == 1 and isinstance(tree.body[0], ast.FunctionDef)
    assert tree.body[0].name == 'main'
    changed = copy.deepcopy(tree)
    flags = [node for node in ast.walk(changed) if isinstance(node, ast.Constant)
             and node.value == 'CODE_SIGNING_ALLOWED=NO']
    assert len(flags) == 1, 'Accepted build signing flag missing or ambiguous'
    flags[0].value = 'CODE_SIGNING_ALLOWED=YES'
    return ast.fix_missing_locations(changed)


def build(root, arm):
    definition = json.loads((root / 'definition.json').read_text())
    assert definition['simulator_signing']['adapter_sha256'] == sha(__file__)
    assert definition['simulator_signing']['source_edits'] == 0
    started = datetime.datetime.now(datetime.timezone.utc)
    assert definition['limits']['arm_total_seconds'] == 2100
    save(root / arm / 'build-admission.json', {
        'state': 'ADMITTED_SIGNED_SIMULATOR_BUILD_ONLY', 'started_at': started.isoformat(),
        'deadline': (started + datetime.timedelta(seconds=2100)).isoformat(),
        'definition_sha256': sha(root / 'definition.json'), 'retries': 0,
    })
    module, _ = capture_build.bind(root, arm)
    source = inspect.getsource(module.main)
    replacement = enable_signing(source)
    # The complete source, compiler, dependency, cleanup and log-redaction guards
    # remain the accepted driver. Its on-disk source and all old outputs stay intact.
    exec(compile(replacement, str(Path(__file__)), 'exec'), module.__dict__)
    save(root / arm / 'signing-driver-transition.json', {
        'status': 'EXACT_SINGLE_FLAG_TRANSITION', 'adapter_sha256': sha(__file__),
        'accepted_driver': module.__file__, 'accepted_driver_sha256': sha(module.__file__),
        'before': 'CODE_SIGNING_ALLOWED=NO', 'after': 'CODE_SIGNING_ALLOWED=YES',
        'post_sign_injection': False, 'native_launches': 0,
    })
    module.main(arm)
    capture_build.compiler_membership(root, arm)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('arm', choices=['baseline', 'candidate'])
    args = parser.parse_args()
    build(args.root.resolve(strict=True), args.arm)
