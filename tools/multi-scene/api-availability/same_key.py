#!/usr/bin/env python3
"""Use the existing API builder/runner for the finite concurrent same-key slice."""
import argparse
import json
import hashlib
from pathlib import Path
import build
import run
import same_key_contract as contract

DEFINITION = build.shared.REPO/'DatadogRUM/MultiSceneSupport/Results/EXP-225-same-key-definition.json'
HELPERS = ['build.py', 'run.py', 'contract.py', 'same_key.py', 'same_key_contract.py', '../acceptance/s2_hosting_workflow.py',
           '../acceptance/acceptance_common.py', '../baselines/run.py']
SOURCE = 'd6f6967e5ebd0e87ea639505b5e5d62e44becfcf698ee767cf304b8aa661e6fc'


def candidate_binding(root, definition):
    revision=definition['source']
    result=build.shared.capture(['git','ls-tree','-r',revision,'--',*build.shared.PATHS])
    blobs={}
    for line in result.stdout.decode().splitlines():
        metadata,path=line.split('\t',1);mode,kind,blob=metadata.split()
        contract.require(kind=='blob' and mode=='100644', 'unexpected source-tree member')
        blobs[path]=blob
    plan=build.shared.read(root/'plan.json')
    contract.require(set(blobs)==set(plan['sdk'])-{'Package.swift'}, 'candidate revision membership differs')
    for path,expected in blobs.items():
        data=(root/'sdk'/path).read_bytes()
        actual=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
        contract.require(actual==expected, 'candidate revision bytes differ: '+path)
    return dict(revision=revision,blobs=blobs,generated_package_sha256=plan['sdk']['Package.swift'])


def verify(root):
    frozen = build.shared.read(root/'same-key-inputs.json')
    contract.require(frozen['definition_sha256'] == build.shared.sha(DEFINITION), 'definition changed')
    contract.require(frozen['helpers'] == {n: build.shared.sha(build.HERE/n) for n in HELPERS}, 'helpers changed')
    plan = build.verify(root)
    contract.require(frozen['candidate'] == candidate_binding(root,json.loads(DEFINITION.read_text())), 'candidate binding changed')
    contract.require(plan['source'] == SOURCE and plan.get('multiple_scenes') is True and Path(plan['fixture_directory']) == build.HERE/'same-key', 'incorrect source/fixture')
    return frozen


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['prepare', 'build', 'swift', 'objc'])
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args(); root = args.root.resolve()
    definition = json.loads(DEFINITION.read_text())
    if args.action == 'prepare':
        build.prepare(root, fixture_directory=build.HERE/'same-key', multiple_scenes=True)
        build.shared.save(root/'same-key-inputs.json', dict(definition_sha256=build.shared.sha(DEFINITION),
            helpers={n: build.shared.sha(build.HERE/n) for n in HELPERS},candidate=candidate_binding(root,definition)), exclusive=True)
        verify(root)
    elif args.action == 'build':
        verify(root); build.build(root, 'simulator'); verify(root)
    else:
        verify(root)
        if args.action == 'objc':
            first = build.shared.read(root/'cells/27.0-swift/summary.json')
            contract.require(first['overall'] == 'PASS', 'first native mechanism qualification did not pass')
        env = definition['environment']
        passed = run.run(root, env['device'], env['runtime'], args.action, qualification=contract)
        verify(root)
        raise SystemExit(0 if passed else 1)


if __name__ == '__main__': main()
