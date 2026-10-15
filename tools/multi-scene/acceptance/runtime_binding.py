"""Bind reviewed host-only changes to an existing, unused native build plan."""
from pathlib import Path
import time
from acceptance_common import require
import s2_hosting_workflow as shared


def validate(root, plan, *, allowed, excluded=()):
    root=Path(root);allowed=set(allowed);excluded=set(excluded)
    require(shared.tree(root/'helpers')==plan['helpers'], 'original helper snapshot changed')
    receipt=root/'runtime-binding.json'
    if not receipt.exists():
        require(all(shared.sha(shared.REPO/name)==value for name,value in plan['helpers'].items() if name not in excluded),
                'helper changed without a pre-native runtime binding')
        return
    binding=shared.read(receipt)
    require(binding.get('schema_version')==1 and binding.get('kind')=='HOST_ONLY_PRE_NATIVE'
            and binding['plan_sha256']==shared.sha(root/'plan.json'), 'runtime binding belongs to another plan')
    changes=binding['changes']
    require(changes and set(changes)<=allowed and not set(changes)&excluded, 'unapproved runtime helper change')
    require(all(name.startswith('tools/multi-scene/acceptance/') and Path(name).suffix in ['.py','.js'] for name in changes),
            'compiled/native source cannot use a host binding')
    require(shared.tree(root/'runtime-helpers')=={name:row['after'] for name,row in changes.items()}, 'runtime snapshot changed')
    for name,row in changes.items():
        require(row['before']==plan['helpers'].get(name) and row['after']==shared.sha(shared.REPO/name), 'runtime helper changed after binding')
    for name,value in plan['helpers'].items():
        if name not in changes and name not in excluded:require(shared.sha(shared.REPO/name)==value,'unbound helper change')
    require(binding['build_receipts'] and all(shared.sha(root/name)==value for name,value in binding['build_receipts'].items()),
            'original build receipt changed')


def prepare(root, *, allowed, extra, excluded, build_receipts):
    root=Path(root);plan=shared.read(root/'plan.json')
    require(not (root/'runtime-binding.json').exists() and not (root/'native-admission.json').exists(), 'runtime already bound or admitted')
    require(not (root/'cells').exists() or not list((root/'cells').iterdir()), 'native attempt already consumed')
    require(shared.tree(root/'helpers')==plan['helpers'] and shared.protected()==plan['protected'],'original snapshot/workspace changed')
    names=set(plan['helpers'])|set(extra);changes={}
    for name in names-set(excluded):
        value=shared.sha(shared.REPO/name)
        if plan['helpers'].get(name)!=value:changes[name]={'before':plan['helpers'].get(name),'after':value}
    require(changes and set(changes)<=set(allowed), 'change outside explicit host-only scope')
    require(all(name.startswith('tools/multi-scene/acceptance/') and Path(name).suffix in ['.py','.js'] for name in changes),'native source change')
    destination=root/'runtime-helpers';require(not destination.exists(),'runtime snapshot already consumed');destination.mkdir()
    for name in sorted(changes):
        path=destination/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes((shared.REPO/name).read_bytes())
    receipt={'schema_version':1,'kind':'HOST_ONLY_PRE_NATIVE','prepared_at':time.time(),
             'plan_sha256':shared.sha(root/'plan.json'),'changes':changes,
             'build_receipts':{name:shared.sha(root/name) for name in build_receipts},
             'additional_builds':0,'native_launches':0}
    shared.save(root/'runtime-binding.json',receipt,exclusive=True)
    validate(root,plan,allowed=allowed,excluded=excluded)
    return receipt


def reviewed(root):
    root=Path(root);review=shared.read(root/'runtime-review.json');controls=shared.read(root/'runtime-controls.json')
    require(review['state']=='PASS' and review['reviewer']=='/root/c06_runtime_plan'
            and review['binding_sha256']==shared.sha(root/'runtime-binding.json')
            and review['controls_sha256']==shared.sha(root/'runtime-controls.json'),'missing/stale runtime review')
    require(controls['state']=='PASS' and controls['binding_sha256']==shared.sha(root/'runtime-binding.json'),'missing/stale runtime controls')
    return shared.sha(root/'runtime-review.json')
