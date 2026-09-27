#!/usr/bin/env python3
"""Fresh, finite host stage reusing the original Resource/Trace compiler artifacts."""
import argparse
import ast
import contextlib
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import runpy
import sys
import time
import traceback
import uuid
from acceptance_common import require
import resource_fold_reuse as reuse
import resource_fold_runtime_variant as variant
import s2_hosting_workflow as shared
import resource_fold_scope as scoped
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'automatic-coverage'))
import human_operator as operator

STAGE='human-observed-resource-fold'
CELLS=['A-automatic','A-registered','B-automatic','B-registered']
CELL=2400;CLEANUP=300;POSE=240;NATIVE_CLEANUP_RESERVE=60
TOTAL=4*(CELL+CLEANUP)+600;EXECUTION=TOTAL-CLEANUP
GENERATED=['cell.py','fold_host.py','fold_oracle.py','connector.js']
OWNER=shared.REPO/'DatadogRUM/MultiSceneSupport/Results/EXP-221-duo-fold.json'


def ref(path):return {'path':str(path),'sha256':shared.sha(path)}
def bound(value):
    path=Path(value['path']);require(path.is_file() and not path.is_symlink() and shared.sha(path)==value['sha256'],'bound runtime asset changed');return path

def save(path,value):
    path=Path(path);require(not path.is_symlink(),'symlinked runtime destination')
    temporary=path.with_name(path.name+'.writing-'+str(uuid.uuid4()))
    try:
        with temporary.open('x') as stream:json.dump(value,stream,indent=2);stream.write('\n');stream.flush();os.fsync(stream.fileno())
        os.link(temporary,path)
    finally:
        if temporary.exists():temporary.unlink()


def contract(definition):
    keys=['gates','cells','builds','native_launches','retries','original_root','source_revisions',
          'original_inputs','reused_builds','budgets_seconds','runtime_stage']
    return {key:definition[key] for key in keys}


def validate_contract(value):
    require(value['cells']==CELLS and value['builds']==0 and value['native_launches']==4 and value['retries']==0,'finite cell inventory changed')
    require(value['budgets_seconds']=={'cell':CELL,'native_after_startup':600,'human_fold':POSE,'cleanup':CLEANUP,
            'human_input_max':180,'post_input_transport_reserve':60},'source/host phase budgets differ')
    stage=value['runtime_stage']
    require(stage['stage']==STAGE and stage['build_limit']==0 and stage['cell_limit']==4 and stage['retry_limit']==0
            and stage['total_seconds']==TOTAL and stage['execution_seconds']==EXECUTION
            and stage['ledger_seconds']=={'four_cells_including_cleanup':10800,'between_cell_reserve':600},'runtime stage reservation differs')


def helper_closure():
    folder=Path(__file__).parent;pending=[Path(__file__).resolve()];found={}
    while pending:
        path=pending.pop();name=str(path.relative_to(shared.REPO))
        if name in found:continue
        found[name]=shared.sha(path)
        for node in ast.walk(ast.parse(path.read_bytes())):
            modules=[n.name for n in node.names] if isinstance(node,ast.Import) else [node.module] if isinstance(node,ast.ImportFrom) and node.module else []
            for module in modules:
                candidate=folder/(module.split('.')[0]+'.py')
                if candidate.is_file():pending.append(candidate.resolve())
    # Generated code imports these helpers even though the generator uses text anchors.
    for name in ['resource_fold_human.py','s2_webview_runtime.py','s2_webview_contract.py','app_journey_inventory.py','app_journey_transport.py','acceptance_common.py']:
        path=folder/name;found[str(path.relative_to(shared.REPO))]=shared.sha(path)
    path=folder/'resource_fold_gather.js';found[str(path.relative_to(shared.REPO))]=shared.sha(path)
    path=Path(operator.__file__);found[str(path.relative_to(shared.REPO))]=shared.sha(path)
    return found


def verify_workspace(root):
    plan=shared.read(Path(root)/'runtime-plan.json')
    if 'semantic_scope' in plan:
        scoped.validate(shared.read(bound(plan['semantic_scope'])),plan['contract'])
        require(scoped.protected()==plan['protected'],'protected user workspace changed')
    else:require(shared.protected()==plan['protected'],'protected workspace changed')


def verify_runtime(root, expected_sha=None, deep=False):
    root=Path(root).resolve();plan=shared.read(root/'runtime-plan.json')
    require(not (root/'runtime-plan.json').is_symlink() and (expected_sha is None or shared.sha(root/'runtime-plan.json')==expected_sha),'runtime plan changed')
    require(plan['stage']==STAGE and plan['root']==str(root),'foreign runtime plan')
    validate_contract(plan['contract'])
    require(contract(shared.read(OWNER)['human_preparation'])==plan['contract'],'human execution contract changed')
    require(shared.tree(root/'helpers')==plan['helpers'] and all(shared.sha(shared.REPO/name)==sha for name,sha in plan['helpers'].items()),'runtime helpers changed')
    require(shared.tree(root/'generated')==plan['generated'],'generated runner changed')
    verify_workspace(root)
    origin=Path(plan['contract']['original_root']);matrix=origin/'matrix'
    require(all(shared.sha(origin/name)==sha for name,sha in plan['contract']['original_inputs'].items()),'original fold inputs changed')
    manifest=shared.read(bound(plan['original_manifest']))
    require(all(shared.sha(row['path'])==row['sha256'] for row in manifest.values()),'original helper changed')
    for key in ['build_reuse','proof_review','preparation']:bound(plan[key])
    for value in plan['contract']['reused_builds'].values():bound(value)
    if deep:
        scope=shared.read(bound(plan['semantic_scope'])) if 'semantic_scope' in plan else None
        actual=reuse.verify(scope);record=shared.read(plan['build_reuse']['path'])
        require(actual['arms']==record['arms'] and actual['original_plan_sha256']==record['original_plan_sha256']
                and actual['original_helpers_sha256']==record['original_helpers_sha256'],'full compiler/product reuse changed')
    return plan


def prepare(args):
    root=args.runtime_root.resolve();require(not root.exists(),'runtime root already consumed')
    definition=shared.read(OWNER)['human_preparation']
    require(definition['native_admitted'] is False and definition['cells']==CELLS and definition['builds']==0
            and definition['retries']==0,'unadmitted human matrix')
    source=Path(definition['original_root']);reuse_record=shared.read(bound(definition['build_reuse']))
    require(reuse_record['state']=='QUALIFIED_REUSE_ONLY','unqualified build reuse')
    proof=shared.read(bound(definition['review']));require(proof['state']=='CONDITIONAL_PASS_OFFLINE_PREPARATION'
            and proof['reviewer']=='/root/c06_runtime_plan','human proof not reviewed')
    scope_path=getattr(args,'scope_definition',None)
    scope=shared.read(scope_path) if scope_path else None
    if scope is not None:scoped.validate(scope,definition)
    root.mkdir(parents=True);(root/'generated').mkdir();(root/'cells').mkdir();(root/'operator').mkdir()
    operator.publish(root/'operator',{'instruction':'Waiting for reviewed Resource/Trace admission and fresh readiness.'})
    helpers=helper_closure();shared.freeze_helpers(root,helpers)
    for name in GENERATED:
        original=source/'host'/name
        (root/'generated'/name).write_bytes(variant.render(name,original.read_bytes(),definition['original_inputs']['host/'+name],semantic=scope is not None))
    if scope is not None:
        original=shared.read(source/'matrix/helper-manifest.json')['oracle']
        (root/'generated/scoped_oracle.py').write_bytes(scoped.render_oracle(bound({'path':original['path'],'sha256':original['sha256']}).read_bytes(),original['sha256']))
    plan={'schema_version':1,'stage':STAGE,'root':str(root),'prepared_at':time.time(),'contract':contract(definition),
          'original_manifest':ref(source/'matrix/helper-manifest.json'),'build_reuse':definition['build_reuse'],
          'proof_review':definition['review'],'preparation':definition['preparation'],'helpers':helpers,
          'generated':shared.tree(root/'generated'),'protected':scoped.protected() if scope is not None else shared.protected(),'native_admitted':False}
    if scope is not None:plan['semantic_scope']=ref(scope_path)
    save(root/'runtime-plan.json',plan);verify_runtime(root)
    print(json.dumps({'state':'PREPARED_RUNTIME_ONLY','root':str(root),'plan_sha256':shared.sha(root/'runtime-plan.json'),'native_launches':0,'additional_builds':0}))


def reviewed(root):
    root=Path(root);review=shared.read(root/'runtime-review.json');controls=shared.read(root/'runtime-controls.json')
    require(review['state']=='PASS' and review['reviewer']=='/root/c06_runtime_plan'
            and review['plan_sha256']==controls['plan_sha256']==shared.sha(root/'runtime-plan.json')
            and review['controls_sha256']==shared.sha(root/'runtime-controls.json') and controls['state']=='PASS','runtime review/controls not bound')
    return {'review':ref(root/'runtime-review.json'),'controls':ref(root/'runtime-controls.json')}


def issue_stage(args):
    root=args.runtime_root.resolve();plan=verify_runtime(root,args.plan_sha256,deep=True);proof=reviewed(root)
    require(not list((root/'cells').iterdir()),'cell preceded new stage')
    now=time.time();receipt={'stage':STAGE,'stage_id':str(uuid.uuid4()),'root':str(root),'plan_sha256':args.plan_sha256,
        'issued_at':now,'execution_deadline':now+EXECUTION,'cleanup_deadline':now+TOTAL,'cells':CELLS,'build_limit':0,'retry_limit':0,**proof}
    save(root/'stage-admission.json',receipt);print(json.dumps({'stage':STAGE,'sha256':shared.sha(root/'stage-admission.json'),
        'execution_deadline':receipt['execution_deadline'],'cleanup_deadline':receipt['cleanup_deadline']}))


def validate_stage(root, fingerprint):
    root=Path(root);path=root/'stage-admission.json';require(not path.is_symlink() and shared.sha(path)==fingerprint,'stage receipt changed')
    d=shared.read(path);require(d['stage']==STAGE and d['root']==str(root.resolve()) and d['cells']==CELLS
        and d['build_limit']==0 and d['retry_limit']==0,'foreign stage')
    require(d['execution_deadline']==d['issued_at']+EXECUTION and d['cleanup_deadline']==d['issued_at']+TOTAL,'stage deadline changed')
    require(str(uuid.UUID(d['stage_id']))==d['stage_id'],'invalid stage ID')
    require(d['plan_sha256']==shared.sha(root/'runtime-plan.json'),'stage plan differs')
    require(reviewed(root)=={key:d[key] for key in ['review','controls']},'stage review changed')
    return d


def reserve(root,arm,mode,device,stage_sha,now=None):
    root=Path(root);now=time.time() if now is None else now;stage=validate_stage(root,stage_sha);name=arm+'-'+mode
    require(name in CELLS,'unknown cell');require(stage['issued_at']<=now and now+CELL<=stage['execution_deadline']
        and now+CELL+CLEANUP<=stage['cleanup_deadline'],'insufficient original stage budget')
    for earlier in CELLS[:CELLS.index(name)]:
        path=root/'cells'/earlier/'summary.json';require(path.is_file(),'earlier cell missing')
        result=shared.read(path);prior=shared.read(path.parent.with_name(earlier+'-admission.json'))
        require(result.get('runtime_plan_sha256')==stage['plan_sha256'] and result.get('runtime_stage_sha256')==stage_sha
            and result.get('runtime_admission_sha256')==shared.sha(path.parent.with_name(earlier+'-admission.json'))
            and all(result.get('identity',{}).get(key)==prior[key] for key in ['run_id','nonce','arm','mode'])
            and result.get('finished_at',float('inf'))<prior['cleanup_deadline'],'foreign/late earlier result')
        require(result.get('state') in ['PASS','BASELINE_E01_OBSERVATION']
            and result.get('evidence_verdict')=='PASS' and result.get('cleanup_verdict')=='PASS'
            and result.get('cleanup',{}).get('errors')==[],'earlier failed cell stops this path')
    output=root/'cells'/name;path=output.with_name(name+'-admission.json')
    require(not os.path.lexists(output) and not os.path.lexists(path),'cell already consumed')
    plan=shared.read(root/'runtime-plan.json');matrix=Path(plan['contract']['original_root'])/'matrix'
    d={'stage':STAGE,'stage_admission_sha256':stage_sha,'runtime_root':str(root.resolve()),'plan_sha256':shared.sha(root/'runtime-plan.json'),
       'matrix':str(matrix),'output':str(output.resolve()),'arm':arm,'mode':mode,'device':device,
       'helper_manifest_sha256':shared.sha(matrix/'helper-manifest.json'),'build_qualification_sha256':plan['contract']['reused_builds'][arm]['sha256'],
       'run_id':str(uuid.uuid4()),'nonce':str(uuid.uuid4()),'issued_at':now,'execution_deadline':now+CELL,'cleanup_deadline':now+CELL+CLEANUP}
    save(path,d);return path,d


def admit(args):
    root=args.runtime_root.resolve();path=args.output.with_name(args.output.name+'-admission.json')
    require(not path.is_symlink() and shared.sha(path)==args.admission_sha256,'cell admission changed');d=shared.read(path)
    stage=validate_stage(root,d['stage_admission_sha256']);now=time.time();plan=shared.read(root/'runtime-plan.json')
    for key,wanted in {'stage':STAGE,'runtime_root':str(root),'plan_sha256':shared.sha(root/'runtime-plan.json'),
        'matrix':str(args.root.resolve()),'output':str(args.output.resolve()),'arm':args.arm,'mode':args.mode,
        'device':args.device,'helper_manifest_sha256':args.helper_manifest_sha256,
        'build_qualification_sha256':plan['contract']['reused_builds'][args.arm]['sha256']}.items():require(d.get(key)==wanted,'wrong cell binding: '+key)
    require(args.output.parent.resolve()==root/'cells' and args.output.name==args.arm+'-'+args.mode
            and not args.output.parent.is_symlink() and not os.path.lexists(args.output) and args.purpose=='acceptance','consumed/foreign native output')
    require(stage['issued_at']<=d['issued_at']<=now<d['issued_at']+60,'stale cell admission')
    require(d['execution_deadline']==d['issued_at']+CELL and d['cleanup_deadline']==d['execution_deadline']+CLEANUP
            and d['execution_deadline']<=stage['execution_deadline'] and d['cleanup_deadline']<=stage['cleanup_deadline'],'cell deadline changed')
    require(str(uuid.UUID(d['run_id']))==d['run_id'] and str(uuid.UUID(d['nonce']))==d['nonce'] and d['run_id']!=d['nonce'],'invalid run identity')
    return d


def cleanup_allowed(cell,phase='pose'):
    cell=Path(cell).resolve();root=cell.parent.parent
    require(phase in ['pose','native'] and cell.parent==root/'cells' and cell.name in CELLS,'foreign human cleanup')
    require(not list(cell.rglob('input-lease.json')),'unexpected automated input worker lease')
    # The only input observation is synchronous in this cell process. No input worker is dispatched.
    marker=cell/('cleanup-begun.json' if phase=='pose' else 'native-cleanup-begun.json')
    save(marker,{'status':'ALLOWED','phase':phase,'automated_input_workers':0,'worker_quiescent':True,'at':time.time()})
    return True


class Tee:
    def __init__(self,console,artifact,sink=None):self.console=console;self.artifact=artifact;self.sink=sink;self.pending=''
    def write(self,text):
        self.artifact.write(text);self.artifact.flush()
        if self.sink:
            self.pending+=text
            while '\n' in self.pending:
                line,self.pending=self.pending.split('\n',1)
                try:message=json.loads(line)
                except ValueError:continue
                if isinstance(message,dict):self.sink(message)
        return self.console.write(text)
    def flush(self):self.artifact.flush();self.console.flush()


def cell(args):
    root=args.runtime_root.resolve();plan=verify_runtime(root,args.plan_sha256,deep=True)
    name=args.arm+'-'+args.mode
    readiness=shared.read(root/('operator-ready-'+name+'.json'))
    operator.ready(root/'operator',readiness,root/'runtime-plan.json',device=args.device,mode=name)
    origin=Path(plan['contract']['original_root']);matrix=origin/'matrix'
    prefix=root/'cells'/(args.arm+'-'+args.mode);receipt={'started_at':time.time(),'exit_code':1}
    with prefix.with_suffix('.driver.stdout.log').open('x') as out,prefix.with_suffix('.driver.stderr.log').open('x') as err:
        with contextlib.redirect_stdout(Tee(sys.stdout,out,lambda value:operator.forward(root/'operator',value,context='Resource/Trace '+name))),contextlib.redirect_stderr(Tee(sys.stderr,err)):
            try:
                path,admission=reserve(root,args.arm,args.mode,args.device,args.stage_sha256)
                receipt.update(admission=ref(path),plan_sha256=args.plan_sha256)
                sys.path.insert(0,str(origin/'host'));sys.path.insert(0,str(root/'generated'))
                sys.modules['resource_fold_runtime']=sys.modules[__name__]
                oracle=shared.read(matrix/'helper-manifest.json')['oracle']['path']
                sys.argv=[str(root/'generated/cell.py'),'--runtime-root',str(root),'--root',str(matrix),
                    '--helper-manifest-sha256',admission['helper_manifest_sha256'],'--oracle',oracle,'--output',str(prefix),
                    '--arm',args.arm,'--mode',args.mode,'--device',args.device,'--purpose','acceptance','--admission-sha256',shared.sha(path)]
                runpy.run_path(sys.argv[0],run_name='__main__');receipt['exit_code']=0
            except SystemExit as error:receipt['exit_code']=error.code if isinstance(error.code,int) else 1
            except BaseException as error:receipt['failure']=str(error);traceback.print_exc()
            finally:
                receipt['finished_at']=time.time();save(prefix.with_suffix('.driver-receipt.json'),receipt)
                operator.publish(root/'operator',{'instruction':'This Resource/Trace cell has stopped. Do not repeat input; evidence and cleanup are being assessed.'})
    return receipt['exit_code']


def transport_error(args):
    path=args.request;request=shared.read(path);require(path.name==request['request_id']+'.request.json','wrong backend request')
    save(path.with_name(request['request_id']+'.transport-error.json'),{'request':request,'error':args.message,'at':time.time()})
    response=path.with_name(request['request_id']+'.response.json')
    if not os.path.lexists(response):save(response,{'request':request,'error':args.message})


def main():
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest='operation',required=True)
    for name in ['prepare','verify','stage','cell']:
        item=sub.add_parser(name);item.add_argument('--runtime-root',type=Path,required=True)
        if name=='prepare':item.add_argument('--scope-definition',type=Path)
        if name!='prepare':item.add_argument('--plan-sha256',required=True)
        if name=='cell':
            for key in ['arm','mode','device','stage-sha256']:item.add_argument('--'+key,required=True)
    item=sub.add_parser('transport-error');item.add_argument('--request',type=Path,required=True);item.add_argument('--message',required=True)
    args=parser.parse_args()
    if args.operation=='verify':verify_runtime(args.runtime_root,args.plan_sha256);print('VERIFIED_RUNTIME_ONLY');return 0
    return {'prepare':prepare,'stage':issue_stage,'cell':cell,'transport-error':transport_error}[args.operation](args) or 0
if __name__=='__main__':raise SystemExit(main())
