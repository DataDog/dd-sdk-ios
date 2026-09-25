#!/usr/bin/env python3
"""Candidate-only S2 WebView continuation; consumed baseline artifacts stay read-only."""
import argparse
import json
from pathlib import Path
import time
from acceptance_common import require
from app_journey_transport import pollable_inventory
import s2_hosting_workflow as shared
import s2_webview_workflow as builds
import s2_webview_driver as driver
import s2_webview_session as oracle

KIND='S2_WEBVIEW_CANDIDATE_CONTINUATION'
REVIEWER='/root/c06_runtime_plan'
BUDGETS={'native':900,'marker_backend':300,'human_fold':300,'backend':300,'cleanup':120}
HELPERS=list(dict.fromkeys(builds.HELPERS+[str(Path(__file__).relative_to(shared.REPO))]))


def reference(path):
    path=Path(path);require(path.is_file() and not path.is_symlink(),'missing/symlinked input')
    return {'path':str(path),'sha256':shared.sha(path)}


def bound(reference_value, expected=None):
    path=Path(reference_value['path'])
    require(expected is None or path==expected,'foreign referenced path')
    require(reference(path)==reference_value,'referenced evidence changed')
    return shared.read(path)


def original_inputs(original, backend):
    paths=[original/name for name in ['plan.json','runtime-binding.json','runtime-review.json','runtime-controls.json','review.json','controls-qualification.json']]
    for folder in [original/'helpers',original/'runtime-helpers',original/'cells/A',backend]:
        paths.extend(p for p in folder.rglob('*') if p.is_file())
    for arm in shared.ARMS:
        paths.extend(original/arm/name for name in ['build-result.json','build-admission.json','source.tar'])
    return {str(p):reference(p)['sha256'] for p in sorted(set(paths))}


def verify_original(original):
    plan=shared.read(original/'plan.json')
    require(plan['gate']=='S2:T10' and plan['definition']['runtime_preparation'].get('scenario')=='navigation-ttl', 'foreign original scenario')
    require(shared.protected()==plan['protected'],'protected workspace changed')
    require(shared.tree(original/'helpers')==plan['helpers'],'original helper snapshot changed')
    binding=shared.read(original/'runtime-binding.json')
    require(binding['kind']=='HOST_ONLY_PRE_NATIVE' and binding['plan_sha256']==shared.sha(original/'plan.json'),'foreign original runtime')
    require(shared.tree(original/'runtime-helpers')=={name:row['after'] for name,row in binding['changes'].items()},'original runtime snapshot changed')
    require(all(row['before']==plan['helpers'].get(name) for name,row in binding['changes'].items()),'runtime predecessor differs')
    require(all(shared.sha(original/name)==value for name,value in binding['build_receipts'].items()),'original build receipts changed')
    builds.runtime_binding.reviewed(original)
    review=shared.read(original/'review.json');controls=shared.read(original/'controls-qualification.json')
    require(review['state']=='PASS' and review['reviewer']==REVIEWER and review['plan_sha256']==shared.sha(original/'plan.json')
            and review['controls_sha256']==shared.sha(original/'controls-qualification.json') and controls['state']=='PASS'
            and controls['helpers']==plan['helpers'],'original source review changed')
    for arm,source in shared.ARMS.items():
        require(plan['arms'][arm]['revision']==source,'foreign source revision')
        require(shared.tree(original/arm/'sdk')==plan['arms'][arm]['sdk'],'original SDK source changed')
        shared.verify_client(original/arm/'client',plan['arms'][arm]['client'])
        builds.verify_archived_build(original,arm,plan)
    return plan


def baseline_qualification(original, backend, plan):
    folder=original/'cells/A';summary=shared.read(folder/'summary.json');identity=summary['identity']
    require(summary['scenario']=='PASS' and summary['cleanup']=='PASS'
            and summary['state']=='INVALID' and summary['reason']=='backend response deadline','baseline stopped outside reviewed transport boundary')
    require(identity['arm']=='A' and identity['source']==shared.ARMS['A'] and identity['fixture']==plan['arms']['A']['fixture']
            and summary['plan_sha256']==shared.sha(original/'plan.json')
            and summary['build_sha256']==shared.sha(original/'A/build-result.json'),'baseline source/build/fixture differs')
    require(all(shared.sha(folder/name)==value for name,value in summary['artifacts'].items()),'baseline artifacts changed')
    document=shared.read(folder/'behavior-evidence.json')
    local=driver.prove_terminal(document,identity,folder,(folder/'initial-displays.raw.json').read_bytes(),summary['device']['udid'],summary['host_run'],mode='navigation-ttl',require_backend=False)
    require(local==shared.read(folder/'behavior-result.json'),'saved baseline native behavior changed')
    result=shared.read(backend/'summary.json');review=shared.read(backend/'review.json');admission=bound(result['admission'],backend/'admission.json')
    require(review['state']=='PASS' and review['reviewer']==REVIEWER and review['summary_sha256']==shared.sha(backend/'summary.json'),'baseline backend review missing or changed')
    require(result['state']=='SAVED_BASELINE_BACKEND_QUALIFIED' and result['native_launches']==0
            and admission['issued_at']<=result['started_at']<=result['finished_at']<admission['deadline']==result['deadline'],'unqualified/late baseline retrieval')
    require(bound(result['original_summary'],folder/'summary.json')==summary and bound(admission['original_summary'],folder/'summary.json')==summary,'baseline summary replaced')
    bound(admission['local_behavior'],folder/'behavior-result.json')
    markers=bound(admission['marker_assessment']);bound(markers['original_summary'],folder/'summary.json');bound(markers['behavior'],folder/'behavior-evidence.json')
    marker_bound=bound(markers['request']);marker_raw=bound(markers['raw_response'])
    rows=pollable_inventory(marker_raw,marker_bound['request'],row_limit=100,page_limit=6,minimum_rows=4)
    callbacks=[r for r in document['records'] if r['kind']=='webkit-callback']
    oracle.acknowledge_markers(document,callbacks,rows,identity)
    raw=bound(result['raw_response'],backend/'raw-response.json')
    require(raw['request']==admission['request'] and raw['finished_at']<admission['deadline'],'foreign/late full inventory')
    inventory=pollable_inventory(raw,admission['request'],row_limit=100,page_limit=6,minimum_rows=7)
    local['browser_rows']=rows
    qualified=oracle.backend_session(inventory,local,pending=False)
    require(qualified==result['backend'],'saved backend result differs from raw inventory')
    return {'identity':identity,'native_summary':reference(folder/'summary.json'),'native_behavior':reference(folder/'behavior-evidence.json'),
            'native_result':reference(folder/'behavior-result.json'),'backend_summary':reference(backend/'summary.json'),
            'backend_review':reference(backend/'review.json'),'backend':qualified}


def prepare(args):
    root=args.root.resolve();original=args.original.resolve();backend=args.backend.resolve()
    require(not root.exists(),'continuation output already exists')
    require(not (original/'cells/B').exists() and not (original/'admissions/B.json').exists(),'candidate already consumed')
    plan=verify_original(original);baseline=baseline_qualification(original,backend,plan)
    root.mkdir(parents=True);(root/'cells').mkdir()
    value={'schema_version':1,'kind':KIND,'arm':'B','scenario':'navigation-ttl','created_at':time.time(),'original':str(original),'backend':str(backend),
           'original_inputs':original_inputs(original,backend),'original_plan':reference(original/'plan.json'),'baseline':baseline,
           'candidate_build':reference(original/'B/build-result.json'),'protected':shared.protected(),'budgets':BUDGETS,
           'helpers':{name:shared.sha(shared.REPO/name) for name in HELPERS},'additional_builds':0,'additional_baselines':0}
    shared.freeze_helpers(root,value['helpers']);shared.save(root/'plan.json',value,exclusive=True)
    verify(root)
    print(json.dumps({'state':'CANDIDATE_PREPARED','root':str(root),'plan_sha256':shared.sha(root/'plan.json'),'native_launches':0}),flush=True)


def verify(root):
    plan=shared.read(root/'plan.json');original=Path(plan['original']);backend=Path(plan['backend'])
    require(plan['kind']==KIND and plan['arm']=='B' and plan['scenario']=='navigation-ttl' and plan['budgets']==BUDGETS,'candidate scope changed')
    require(shared.protected()==plan['protected'],'protected workspace changed')
    require(shared.tree(root/'helpers')==plan['helpers'] and all(shared.sha(shared.REPO/name)==sha for name,sha in plan['helpers'].items()
            if name!=builds.DEFINITION),'candidate helpers changed')
    require(original_inputs(original,backend)==plan['original_inputs'],'original evidence changed')
    original_plan=verify_original(original)
    require(baseline_qualification(original,backend,original_plan)==plan['baseline'],'baseline qualification changed')
    bound(plan['original_plan'],original/'plan.json');bound(plan['candidate_build'],original/'B/build-result.json')
    return plan


def admission(root, plan, device):
    value=shared.read(root/'admission.json');review=shared.read(root/'review.json');controls=shared.read(root/'controls.json');now=time.time()
    require(review['state']=='PASS' and review['reviewer']==REVIEWER and review['plan_sha256']==shared.sha(root/'plan.json')
            and review['controls_sha256']==shared.sha(root/'controls.json') and controls['state']=='PASS'
            and controls['helpers']==plan['helpers'],'candidate review/controls changed')
    require(value['state']=='ADMITTED' and value['arm']=='B' and value['scenario']=='navigation-ttl'
            and value['plan_sha256']==shared.sha(root/'plan.json') and value['review_sha256']==shared.sha(root/'review.json')
            and value['baseline']==plan['baseline'] and value['candidate_build']==plan['candidate_build']
            and value['budgets']==BUDGETS and 0<=now-value['issued_at']<=300,'foreign/stale candidate admission')
    identity=value['identity'];prior=plan['baseline']['identity']
    for key in ['run_id','nonce']:
        oracle.identifier(identity[key]);require(identity[key]!=prior[key],'reused baseline identity')
    frozen=shared.read(Path(plan['original'])/'plan.json')
    require(identity==dict(run_id=identity['run_id'],nonce=identity['nonce'],arm='B',source=shared.ARMS['B'],fixture=frozen['arms']['B']['fixture']), 'candidate identity differs')
    native=value['issued_at']+BUDGETS['native'];execution=native+BUDGETS['backend'];cleanup=execution+BUDGETS['cleanup']
    require(value['native_deadline']==native and value['execution_deadline']==execution and value['cleanup_deadline']==cleanup and now<native,'candidate deadlines changed')
    ready=bound(value['preflight'])
    require(ready['state']=='PASS' and ready['device']==device and ready['plan_sha256']==shared.sha(root/'plan.json')
            and 0<=value['issued_at']-ready['at']<=300,'candidate preflight foreign/stale')
    return value




def verify_transport(out):
    requests=list(out.rglob('*.request.json'));require(requests,'missing backend requests')
    for path in requests:
        request=shared.read(path);prefix=path.name.removesuffix('.request.json')
        raw=shared.read(path.with_name(prefix+'.response.raw.json'))
        published=path.with_name(prefix+'.response.json');receipt=shared.read(path.with_name(prefix+'.transport.json'))
        timing=raw['transport'];stages=timing['stages']
        require(raw['request']==request['request'] and stages and stages[0]['name']=='count','foreign transport evidence')
        require(path.stat().st_mtime<=timing['request_read_at']<=stages[0]['started_at'],'request timing reversed')
        previous=timing['request_read_at']
        for stage in stages:
            require(previous<=stage['started_at']<=stage['finished_at'],'transport stage timing reversed')
            previous=stage['finished_at']
        require(previous<=timing['publication_started_at']<=published.stat().st_mtime<=receipt['persistence_finished_at']<request['deadline'],
                'backend persistence late or incomplete')


def claim_candidate(root, plan, value):
    """One candidate attempt across fresh continuation directories; outside consumed evidence."""
    original=Path(plan['original']);path=original.with_name(original.name+'-candidate-claim.json')
    shared.save(path,{'kind':KIND,'arm':'B','root':str(root),'plan_sha256':shared.sha(root/'plan.json'),
                      'admission_sha256':shared.sha(root/'admission.json'),'identity':value['identity'],'at':time.time()},exclusive=True)
    return path


def cell(args):
    require(args.arm=='B','only candidate B is admitted')
    root=args.root.resolve();plan=verify(root);value=admission(root,plan,args.device);original=Path(plan['original'])
    require(not (original/'cells/B').exists() and not (original/'admissions/B.json').exists(),'candidate consumed in original root')
    require(not (root/'cells/B').exists(),'candidate continuation already consumed')
    claim_candidate(root,plan,value)
    frozen=shared.read(original/'plan.json');build=builds.verify_archived_build(original,'B',frozen)
    return driver.execute_cell(args,frozen,BUDGETS,'navigation-ttl',value,root/'admission.json',build,
                               build_receipt=original/'B/build-result.json',verify_source=verify,verify_transport=verify_transport)


def main():
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest='stage',required=True)
    p=sub.add_parser('prepare');p.add_argument('--root',type=Path,required=True);p.add_argument('--original',type=Path,required=True);p.add_argument('--backend',type=Path,required=True)
    p=sub.add_parser('cell');p.add_argument('--root',type=Path,required=True);p.add_argument('--arm',choices=['B'],required=True);p.add_argument('--device',required=True)
    p=sub.add_parser('verify');p.add_argument('--root',type=Path,required=True)
    args=parser.parse_args()
    if args.stage=='prepare':prepare(args)
    elif args.stage=='verify':verify(args.root.resolve());print('VERIFIED')
    else:return cell(args)
    return 0
if __name__=='__main__':raise SystemExit(main())
