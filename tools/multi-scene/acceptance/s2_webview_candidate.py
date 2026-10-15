#!/usr/bin/env python3
"""Candidate-only S2 WebView continuation; consumed baseline artifacts stay read-only."""
import argparse
import json
import math
import re
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
BUDGETS={'native':900,'marker_backend':180,'human_fold':300,'backend':300,'cleanup':120}
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



def native_budget_contract(client, budgets):
    """Validate launch arguments against the exact source already compiled into the app."""
    path=Path(client)/'App.swift';source=path.read_text()
    native=re.findall(r'budgetSeconds <= ([0-9_]+)',source)
    phases=re.findall(r'let maximum: Double = kind == "human-fold" \? ([0-9]+) : ([0-9]+)',source)
    require(len(native)==1 and len(phases)==1,'compiled native budget limits not identified')
    limits={'native':int(native[0].replace('_','')),'human_fold':int(phases[0][0]),'marker_backend':int(phases[0][1])}
    for name,maximum in limits.items():
        value=budgets.get(name)
        require(type(value) in (int,float) and math.isfinite(value) and 0<value<=maximum,'launch budget exceeds compiled fixture: '+name)
    return {'source':reference(path),'maximum_seconds':limits,'launch_seconds':{name:budgets[name] for name in limits}}


def stopped_budget_attempt(previous, original, baseline):
    """Only the preserved 300-versus-180 mismatch permits this one host correction."""
    previous=Path(previous);out=previous/'cells/B';plan=shared.read(previous/'plan.json')
    legacy=dict(BUDGETS,marker_backend=300)
    require(plan['kind']==KIND and plan['original']==str(original) and plan['budgets']==legacy
            and plan['baseline']==baseline,'not the original stopped budget attempt')
    bound(plan['original_plan'],original/'plan.json');bound(plan['candidate_build'],original/'B/build-result.json')
    require(shared.tree(previous/'helpers')==plan['helpers'],'stopped helper snapshot changed')
    summary=shared.read(out/'summary.json')
    require(all(summary.get(k)==v for k,v in {'state':'INVALID','scenario':'UNQUALIFIED','evidence':'INCOMPLETE','cleanup':'PASS',
            'reason':'invalid terminal identity/state'}.items()) and summary['plan_sha256']==shared.sha(previous/'plan.json'),
            'different stopped candidate outcome')
    require(all(shared.sha(out/name)==value for name,value in summary['artifacts'].items()),'stopped artifacts changed')
    admission=bound(summary['admission'],previous/'admission.json')
    require(admission['budgets']==legacy and admission['identity']==summary['identity']
            and admission['candidate_build']==plan['candidate_build'] and admission['baseline']==baseline,'stopped admission changed')
    review=shared.read(previous/'review.json');controls=shared.read(previous/'controls.json')
    require(review['state']=='PASS' and review['reviewer']==REVIEWER and review['plan_sha256']==shared.sha(previous/'plan.json')
            and admission['review_sha256']==shared.sha(previous/'review.json') and review['controls_sha256']==shared.sha(previous/'controls.json')
            and controls['state']=='PASS' and controls['helpers']==plan['helpers'],'stopped review changed')
    identity=summary['identity'];frozen=shared.read(original/'plan.json')
    require(identity['source']==shared.ARMS['B'] and identity['fixture']==frozen['arms']['B']['fixture']
            and summary['build_sha256']==shared.sha(original/'B/build-result.json'),'stopped source/product differs')
    document=shared.read(out/'evidence.json');terminal=shared.read(out/'native-terminal.json');records=document['records']
    require(terminal['state']=='INVALID' and terminal['identity']==identity and document['identity']==identity
            and terminal['evidence_sha256']==shared.sha(out/'evidence.json') and document['persistence_failure'] is False
            and document['closed_sequence']==document['durable_sequence']==terminal['closed_sequence']==len(records),
            'stopped native seal differs')
    require([r['sequence'] for r in records]==list(range(1,len(records)+1))
            and records[-3]['kind']=='behavior-complete' and records[-2]['kind']=='failure'
            and records[-2]['reason']=='invalid("phase-budget")' and records[-1]['kind']=='terminal'
            and records[-1]['state']=='INVALID' and not any(r['kind'] in ['failure','host-request-issued'] for r in records[:-2]),
            'failure is not the post-behavior budget mismatch')
    argv=shared.read(out/'launch.json')['argv']
    require(argv.count('--marker-budget-seconds')==1 and argv[argv.index('--marker-budget-seconds')+1]=='300',
            'wrong stopped launch argument')
    claim=original.with_name(original.name+'-candidate-claim.json');claimed=shared.read(claim)
    require(claimed['root']==str(previous) and claimed['plan_sha256']==shared.sha(previous/'plan.json')
            and claimed['admission_sha256']==shared.sha(previous/'admission.json') and claimed['identity']==identity,
            'stopped candidate claim differs')
    require(summary['cleanup_details']['finished_at']<summary['cleanup_details']['deadline']<=summary['cleanup_deadline']
            and not summary['cleanup_details']['errors'],'stopped cleanup incomplete or late')
    return {'root':str(previous),'inputs':shared.tree(previous),'summary':reference(out/'summary.json'),'claim':reference(claim),'identity':identity}


def prepare(args):
    root=args.root.resolve();original=args.original.resolve();backend=args.backend.resolve()
    require(not root.exists(),'continuation output already exists')
    require(not (original/'cells/B').exists() and not (original/'admissions/B.json').exists(),'candidate already consumed')
    plan=verify_original(original);baseline=baseline_qualification(original,backend,plan)
    previous=getattr(args,'previous_candidate',None)
    repair=stopped_budget_attempt(previous.resolve(),original,baseline) if previous else None
    claim=original.with_name(original.name+('-candidate-budget-repair-claim.json' if repair else '-candidate-claim.json'))
    require(not claim.exists(),'candidate attempt already consumed')
    native_limits=native_budget_contract(original/'B/client',BUDGETS)
    root.mkdir(parents=True);(root/'cells').mkdir()
    value={'schema_version':1,'kind':KIND,'arm':'B','scenario':'navigation-ttl','created_at':time.time(),'original':str(original),'backend':str(backend),
           'original_inputs':original_inputs(original,backend),'original_plan':reference(original/'plan.json'),'baseline':baseline,
           'candidate_build':reference(original/'B/build-result.json'),'protected':shared.protected(),'budgets':BUDGETS,
           'helpers':{name:shared.sha(shared.REPO/name) for name in HELPERS},'additional_builds':0,'additional_baselines':0,
           'native_budget_contract':native_limits,'budget_repair':repair}
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
    require(not (original/'cells/B').exists() and not (original/'admissions/B.json').exists(),'candidate consumed in original root')
    require(native_budget_contract(original/'B/client',plan['budgets'])==plan['native_budget_contract'],'compiled budget contract changed')
    if plan.get('budget_repair'):
        require(stopped_budget_attempt(Path(plan['budget_repair']['root']),original,plan['baseline'])==plan['budget_repair'],'stopped budget evidence changed')
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
        if plan.get('budget_repair'):require(identity[key]!=plan['budget_repair']['identity'][key],'reused stopped candidate identity')
    frozen=shared.read(Path(plan['original'])/'plan.json')
    require(identity==dict(run_id=identity['run_id'],nonce=identity['nonce'],arm='B',source=shared.ARMS['B'],fixture=frozen['arms']['B']['fixture']), 'candidate identity differs')
    native=value['issued_at']+BUDGETS['native'];execution=native+BUDGETS['backend'];cleanup=execution+BUDGETS['cleanup']
    require(value['native_deadline']==native and value['execution_deadline']==execution and value['cleanup_deadline']==cleanup and now<native,'candidate deadlines changed')
    ready=bound(value['preflight'])
    require(Path(value['preflight']['path']).parent==root,'preflight outside candidate root')
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
    original=Path(plan['original']);suffix='-candidate-budget-repair-claim.json' if plan.get('budget_repair') else '-candidate-claim.json'
    path=original.with_name(original.name+suffix)
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
    p=sub.add_parser('prepare');p.add_argument('--root',type=Path,required=True);p.add_argument('--original',type=Path,required=True);p.add_argument('--backend',type=Path,required=True);p.add_argument('--previous-candidate',type=Path)
    p=sub.add_parser('cell');p.add_argument('--root',type=Path,required=True);p.add_argument('--arm',choices=['B'],required=True);p.add_argument('--device',required=True)
    p=sub.add_parser('verify');p.add_argument('--root',type=Path,required=True)
    args=parser.parse_args()
    if args.stage=='prepare':prepare(args)
    elif args.stage=='verify':verify(args.root.resolve());print('VERIFIED')
    else:return cell(args)
    return 0
if __name__=='__main__':raise SystemExit(main())
