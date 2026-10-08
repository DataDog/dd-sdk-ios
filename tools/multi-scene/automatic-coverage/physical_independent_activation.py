"""Complete unissued physical producer and serial parent interface; no model authority."""
import copy,hashlib,importlib.abc,importlib.util,json,math,os,subprocess,sys,time,uuid
from pathlib import Path
OWNER='/root/s2_split_input_owner'
PROFILE='P2_PHYSICAL_UIKIT_INDEPENDENT_CAPTURE_END_THEN_HUMAN_V1'
A=Path(__file__).resolve().parent
M=Path(__file__).resolve().parents[3]
MAIN=M/'DatadogRUM/MultiSceneSupport/Results/execution-improvements-20261004.json'
HELPER_PROFILE='PHYSICAL_INDEPENDENT_MAIN_SOURCE_V1'
LEGACY_NAMES_SHA='d9820b89b228a649ea560b8ae1caed3c47646db4e57ec21a9bfe3c5f2a1534dd'
OVERRIDES={
 'tools/multi-scene/interactive-transitions/physical_activation.py':'tools/multi-scene/automatic-coverage/physical_independent_activation.py',
 'tools/multi-scene/interactive-transitions/physical_runtime.py':'tools/multi-scene/automatic-coverage/physical_independent_runtime.py',
 'tools/multi-scene/interactive-transitions/physical_local.py':'tools/multi-scene/automatic-coverage/physical_independent_local.py',
 'tools/multi-scene/interactive-transitions/physical_session.py':'tools/multi-scene/automatic-coverage/physical_independent_session.py',
 'tools/multi-scene/interactive-transitions/physical_independent_adapter.py':'tools/multi-scene/automatic-coverage/physical_independent_adapter.py',
 'tools/multi-scene/automatic-coverage/human_contract.py':'tools/multi-scene/automatic-coverage/physical_independent_oracle.py'}
SELECTED=None
def require(v,m):
    if not v:raise ValueError(m)
def encoded(v):return (json.dumps(v,indent=2,sort_keys=True)+'\n').encode()
def ref(p):
    p=Path(p);require(p.is_absolute() and p.is_file() and not any(q.is_symlink() for q in [p,*p.parents]),'redirected/missing evidence')
    return dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest())
def read(r):require(ref(r['path'])==r,'changed evidence');return json.loads(Path(r['path']).read_bytes())
def save(p,v):
    p=Path(p);require(p.parent.is_dir() and not p.is_symlink(),'unprepared publication');p.open('xb').write(encoded(v))
def select(selection):
    global SELECTED
    require(SELECTED is None or SELECTED==selection,'physical source selection already fixed')
    ledger=read(selection)
    require(ledger['kind']=='UNISSUED_PHYSICAL_SELECTED_SOURCE_LEDGER' and ledger['helper_profile']==HELPER_PROFILE,'wrong explicit helper profile')
    members=ledger['members'];paths=ledger['member_paths']
    require(hashlib.sha256(encoded(sorted(members))).hexdigest()==LEGACY_NAMES_SHA and set(paths)==set(members),'different legacy79 contract')
    require(paths=={name:OVERRIDES.get(name,name) for name in members},'foreign physical member routing')
    for name,digest in members.items():
        source=M/paths[name]
        require(source.resolve().is_relative_to(M) and ref(source)['sha256']==digest,'changed selected source: '+name)
    require(ledger['runtime_source']==ref(__file__) and ledger['dispatch']==ref(A/'physical_independent_dispatch.mjs'),'foreign profile entry')
    require(ledger['adapter_sources']==dict(adapter=ref(M/OVERRIDES['tools/multi-scene/interactive-transitions/physical_independent_adapter.py']),
            selected_oracle=ref(M/OVERRIDES['tools/multi-scene/automatic-coverage/human_contract.py']),
            supported=ref(M/'tools/multi-scene/automatic-coverage/human_supported_session.py')),'foreign physical adapter selection')
    SELECTED=copy.deepcopy(selection)
    return members
def selected_reference():
    require(SELECTED is not None,'explicit physical source selection required')
    return copy.deepcopy(SELECTED)
def member_path(name):
    ledger=read(selected_reference())
    require(name in ledger['members'],'unknown selected member')
    return M/ledger['member_paths'][name]
def helper_members():return select(selected_reference())
class FrozenImports(importlib.abc.MetaPathFinder):
    def __init__(self,members):
        self.members=members;self.names={Path(n).stem:member_path(n) for n in members if n.endswith('.py')}
    def find_spec(self,fullname,path=None,target=None):
        if '.' not in fullname and fullname in self.names:
            source=self.names[fullname];name=next(n for n in self.members if n.endswith('.py') and Path(n).stem==fullname)
            require(ref(source)['sha256']==self.members[name],'import hash changed')
            return importlib.util.spec_from_file_location(fullname,source)
def imports():
    members=helper_members();stems=[Path(n).stem for n in members if n.endswith('.py')]
    require(len(stems)==len(set(stems)), 'ambiguous profile module aliases')
    for name,module in list(sys.modules.items()):
        f=getattr(module,'__file__',None)
        if f and name in stems:
            logical=next(n for n in members if n.endswith('.py') and Path(n).stem==name)
            require(Path(f).resolve()==member_path(logical) and ref(f)['sha256']==members[logical],'foreign preloaded alias: '+name)
    if 'physical_activation' not in sys.modules:sys.modules['physical_activation']=sys.modules[__name__]
    if not any(isinstance(f,FrozenImports) for f in sys.meta_path):sys.meta_path.insert(0,FrozenImports(members))
    return members
def consume_selection_arguments():
    require(len(sys.argv)>=4 and sys.argv[1]=='--source-selection','child explicit source selection required')
    select(dict(path=sys.argv[2],sha256=sys.argv[3]))
    del sys.argv[1:4]
    imports()
def values(inputs):
    plan=read(inputs['plan']);review=read(inputs['review']);context=copy.deepcopy(inputs['context']);root=Path(inputs['root'])
    require(root.is_absolute() and not any(p.is_symlink() for p in [root,*root.parents]),'foreign runtime root')
    require(plan['static_anchor'] is not None,'unbound static launch anchor')
    require(plan['operation_profile']==PROFILE and plan['native_launches']==0 and plan['gate_closures']==[],'wrong physical scope')
    require(review['state']=='PASS' and review['findings']==[] and review['plan_sha256']==inputs['plan']['sha256'] and review['verdict']=='PASS_P2_PHYSICAL_RUNTIME_COMPOSITION_ONLY','missing physical composition review')
    select(plan['source_ledger']);imports();import reviewer_assignment
    reviewer_assignment.require_reviewer(review,inputs['plan']['sha256'],root)
    require(review['source_ledger']==plan['source_ledger'],'review source selection differs')
    ledger=read(plan['source_ledger']);require(ledger['members']==helper_members(),'different helper closure')
    require(context['owner']==OWNER and str(uuid.UUID(context['run_id']))==context['run_id'] and str(uuid.UUID(context['nonce']))==context['nonce'] and context['plan_sha256']==inputs['plan']['sha256'],'foreign canonical identity')
    require(all(type(context[k]) in (int,float) and math.isfinite(context[k]) for k in ['issued_at','execution_deadline','cleanup_deadline']),'invalid clocks')
    require(context['execution_deadline']-context['issued_at']==5400 and context['cleanup_deadline']-context['execution_deadline']==600,'different full reservation')
    require(context['device']==plan['device'] and context['udid']==plan['udid'] and context['source']=='c9faed816a1d4828d7d8c4b64acae01119425889' and context['bundle']==plan['bundle'],'different physical identity')
    pre=read(inputs['preflight']);awake=read(inputs['awake']);env=read(inputs['environment']);consent=read(inputs['launch_consent']);page=read(inputs['page'])
    require(pre['state']=='PASS' and pre['plan_sha256']==inputs['plan']['sha256'] and pre['device']==plan['device'] and pre['udid']==plan['udid'] and pre['required_os']==plan['required_os'] and pre['physical_setup']==plan['physical_setup'],'foreign current physical preflight')
    require(pre['expected_main_head']==inputs['expected_main_head'] and pre['source_ledger']==plan['source_ledger'] and pre['product_manifest']==plan['product_manifest'],'wrong root source/product/head guard')
    require(0<=context['issued_at']-pre['at']<180,'stale root preflight')
    for k in ['physical_access','initial_home','protected','current_metadata','lane_quiescence','awake_process','page_process']:read(pre[k])
    cutoff=awake.get('operational_cutoff',awake.get('operational_cutoff_epoch'));require(type(cutoff) in (int,float) and math.isfinite(cutoff) and context['cleanup_deadline']<cutoff,'actual awake grant does not fit full reservation')
    require(env['awake_authority']==inputs['awake'] and env['page']==inputs['page'] and env['preflight']==inputs['preflight'],'foreign environment')
    require(page['seconds']==7200 and type(page['started_at']) in (int,float) and context['cleanup_deadline']<page['started_at']+page['seconds'],'page full reservation does not fit')
    require(env['roles']['page']['pid']==page['pid'] and env['roles']['awake']==awake['process'],'foreign live roles')
    require(set(env['roles'])=={'page','awake'} and all(set(role)=={'pid','group','start','command'} and type(role['pid']) is int and type(role['group']) is int and role['pid']>0 and role['group']>0 and all(isinstance(role[k],str) and role[k] for k in ['start','command']) for role in env['roles'].values()),'incomplete actual process roles')
    import physical_independent_adapter as adapter
    adapter.launch_consent(inputs['plan']['sha256'],plan['static_anchor']['sha256'],consent,context['issued_at'])
    require(pre['launch_consent']==inputs['launch_consent'] and pre['page']==inputs['page'],'foreign actual consent/page guard')
    product=read(plan['product_manifest']);require(product==pre['product'],'actual complete product proof differs')
    require(product['bundle']==plan['bundle'] and product['file_count']==len(product['files']),'foreign product manifest')
    require({str(p.relative_to(Path(product['app']))) for p in Path(product['app']).rglob('*') if p.is_file()}==set(product['files']),'different complete product inventory')
    for name,digest in product['files'].items():
        require(ref(Path(product['app'])/name)['sha256']==digest,'product member changed')
    definition=dict(kind='P2_PHYSICAL_INDEPENDENT_CAPTURE_HUMAN_DEFINITION',operation_profile=PROFILE,root=str(root),plan=inputs['plan'],review=inputs['review'],context=context,source_ledger=plan['source_ledger'],offline_model_no_native_authority=False)
    configuration=dict(kind='P2_WORKSPACE_OWNER_CONFIGURATION',nominal_kind_adapter='Existing exact root selector data boundary only; device operation is physical UIKit.',operation_profile=PROFILE,definition=dict(path=str(root/'definition.json'),sha256=hashlib.sha256(encoded(definition)).hexdigest()),root=str(root),plan=inputs['plan'],review=inputs['review'],context=context,source_ledger=plan['source_ledger'],offline_model_no_native_authority=False,preflight=inputs['preflight'],awake=inputs['awake'],environment=inputs['environment'],launch_consent=inputs['launch_consent'],page=inputs['page'],expected_main_head=inputs['expected_main_head'],runtime_source=ref(__file__),dispatch=ref(A/'physical_independent_dispatch.mjs'),entry_source=(A/'physical_independent_dispatch.mjs').read_text())
    projected=runtime_plan(configuration)
    configuration['runtime_plan']=dict(path=str(root/'plan.json'),sha256=hashlib.sha256(encoded(projected)).hexdigest())
    return definition,configuration
def validate(configuration):
    keys=['root','plan','review','context','preflight','awake','environment','launch_consent','page','expected_main_head'];d,c=values({k:configuration[k] for k in keys})
    require(read(configuration['definition'])==d and configuration==c,'whole physical configuration differs');bound_runtime_plan(configuration);return read(configuration['plan'])
def admission(c):return dict(plan_sha256=c['plan']['sha256'],review_sha256=c['review']['sha256'],issued_at=c['context']['issued_at'],first_cell_deadline=c['context']['issued_at']+1050,execution_deadline=c['context']['execution_deadline'],cleanup_deadline=c['context']['cleanup_deadline'],preflight_sha256=c['preflight']['sha256'],operator_sha256=c['launch_consent']['sha256'],device=c['context']['device'])
def runtime_plan(c):
    p=copy.deepcopy(read(c['plan'])['physical_plan']);ledger=read(c['source_ledger']);p.update(helpers=helper_members(),native_seconds=5250,backend_seconds=150,cleanup_seconds=600,pair_seconds=6000,canonical_context=c['context'],canonical_admission=admission(c))
    p['independent_capture']=dict(scope='CLI_OWNED_APP_SHORT_SUPPORTED_CAPTURE_END_BEFORE_READY',sources=ledger['adapter_sources'],runtime_plan_sha256=c['plan']['sha256'],root_released=True,page_invited=False,owner=OWNER,transport_seconds=240,product_manifest=read(c['plan'])['product_manifest'],static_anchor_sha256=read(c['plan'])['static_anchor']['sha256'],launch_consent=c['launch_consent'],page_directory=str(Path(c['root'])/'operator'),stage=dict(runtime_plan_sha256=c['plan']['sha256'],page=read(c['page'])),clocks=dict(native_deadline=c['context']['execution_deadline']-150,execution_deadline=c['context']['execution_deadline'],cleanup_deadline=c['context']['cleanup_deadline']))
    return p
def bound_runtime_plan(c):
    expected=runtime_plan(c);wanted=dict(path=str(Path(c['root'])/'plan.json'),sha256=hashlib.sha256(encoded(expected)).hexdigest())
    require(c['runtime_plan']==wanted,'foreign runtime plan reference')
    actual=read(c['runtime_plan']);require(actual==expected,'serialized runtime plan differs');return actual
def build(inputs):
    d,c=values(inputs);root=Path(c['root']);require(root.is_dir() and not any((root/n).exists() for n in ['definition.json','configuration.json','native-admission.json','plan.json']),'authority path consumed')
    for name,v in [('plan.json',runtime_plan(c)),('definition.json',d),('configuration.json',c),('native-admission.json',admission(c))]:save(root/name,v)
    require(validate(read(ref(root/'configuration.json'))), 'serialized physical configuration refused')
    return dict(configuration=ref(root/'configuration.json'),definition=ref(root/'definition.json'),admission=ref(root/'native-admission.json'),runtime_plan=ref(root/'plan.json'),native_calls=0,parent_released=False)
def check_selection(c,release,configuration_ref):
    require(release['kind']=='ROOT_EXCLUSIVE_PHYSICAL_HUMAN_RELEASE' and release['configuration']==configuration_ref and release['context']==c['context'] and ref(MAIN)==release['owning_record'],'foreign exclusive root handoff')
    parameter=read(release['parameter_review'])
    imports();import reviewer_assignment
    reviewer_assignment.require_reviewer(parameter,c['plan']['sha256'],Path(c['root']))
    require(parameter['state']=='PASS' and parameter['findings']==[] and parameter['verdict']=='PASS_P2_PHYSICAL_HUMAN_ISSUED_PARAMETERS_ONLY' and parameter['configuration']==configuration_ref and parameter['context']==c['context'] and parameter['source_review']==c['review'],'foreign or incomplete issued parameter review')
    selected=json.loads(MAIN.read_bytes())['p2']['workspace_alternative'];wanted=dict(root=c['root'],plan=c['plan'],definition=c['definition'],review=c['review'],native_admitted=True,execution=None)
    require(all(selected.get(k)==v for k,v in wanted.items()) and selected.get('native_admitted') is True and selected.get('execution') is None,'actual MAIN selection/readback absent')
def execute(configuration_ref,release_ref):
    c=read(configuration_ref);validate(c);check_selection(c,read(release_ref),configuration_ref);ctx=c['context']
    require(ctx['issued_at']<=time.time()<ctx['execution_deadline']-150,'original physical native clock expired')
    require(subprocess.run(['git','-C',str(M),'rev-parse','HEAD'],capture_output=True,check=True,text=True).stdout.strip()==c['expected_main_head'],'current documentation HEAD changed')
    require(selected_reference()==c['source_ledger'],'parent selected ledger differs');imports();import physical_session
    from types import SimpleNamespace
    plan=bound_runtime_plan(c);key=plan['cells'][0]['id'];require(not (Path(c['root'])/'cells'/key).exists(),'cell already consumed')
    return physical_session.run(SimpleNamespace(root=Path(c['root']),key=key))
def dispatch_request(configuration_ref,release_ref,path,check_time=True):
    c=read(configuration_ref);validate(c);check_selection(c,read(release_ref),configuration_ref);p=Path(path).resolve();plan=read(c['plan']);key=plan['physical_plan']['cells'][0]['id'];folder=Path(c['root'])/'cells'/key/'lifecycle/session'
    require(p.name=='request.json' and p.parent.parent==folder and p.parent.name in ['start','capture','end'],'foreign physical request path')
    imports();import physical_independent_adapter as adapter;import human_supported_session as supported
    request=supported.validate_request(supported.read(p));binding=request['binding'];ctx=c['context']
    wanted=dict(owner=OWNER,device=ctx['device'],udid=ctx['udid'],bundle=ctx['bundle'],run_id=ctx['run_id'],product_sha256=plan['product_manifest']['sha256'],plan_sha256=c['plan']['sha256'],layout='stack')
    require(all(binding.get(k)==v for k,v in wanted.items()),'foreign physical dispatch binding')
    cutoff=ctx['cleanup_deadline'] if request['phase']=='end' else ctx['execution_deadline']-150
    require(request['issued_at']<=request['deadline']<=min(cutoff,request['issued_at']+240),'foreign request cutoff')
    if check_time:require(request['issued_at']<=time.time()<request['deadline'],'request deadline expired')
    if request['phase']!='start':
        s,raw=adapter._PHYSICAL_VALIDATE_RESPONSE(folder/'start/request.json',now=supported.read(folder/'start/response.json')['published_at'])
        require(request['session_key']==adapter.physical_start_value(s,raw) and request['start_response_sha256']==supported.sha(folder/'start/response.json') and all(binding[k]==v for k,v in s['binding'].items()),'foreign physical Start custody')
        if request['phase']=='capture':
            verified=supported.read(p.parents[3]/'installed-code-verified.json');require(binding['pid']==verified['process_id'] and verified['run_id']==ctx['run_id'],'different actual installed PID/run')
    return request,ref(p)
def publish(configuration_ref,release_ref,path,raw_ref,started,finished):
    request,r=dispatch_request(configuration_ref,release_ref,path,False);raw=read(raw_ref)
    require(request['issued_at']<=started<=finished<=time.time(),'foreign actual clocks')
    import human_supported_session as supported
    return supported.publish_response(path,raw,owner=OWNER,started_at=started,finished_at=finished,published_at=time.time())
if __name__=='__main__':
    c=dict(path=sys.argv[2],sha256=sys.argv[3]);r=dict(path=sys.argv[4],sha256=sys.argv[5])
    if sys.argv[1]=='execute':raise SystemExit(execute(c,r))
    elif sys.argv[1]=='request':
        q,reference=dispatch_request(c,r,sys.argv[6]);print(json.dumps(dict(request=q,reference=reference)))
    elif sys.argv[1]=='publish':print(json.dumps(dict(response=publish(c,r,sys.argv[6],dict(path=sys.argv[7],sha256=sys.argv[8]),float(sys.argv[9]),float(sys.argv[10])))))
    else:raise ValueError('unknown physical dispatch operation')
