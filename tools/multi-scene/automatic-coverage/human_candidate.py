"""One opt-in candidate sitting with separately typed, immutable baseline references."""
import argparse
import json
from pathlib import Path
import shutil
import time
import human_sessions as sessions

KIND='S2_CANDIDATE_CONTINUATION'
CELL=dict(build='candidate-27.1',device='duo',framework='UIKit',layout='stack',multiple_scenes=False)
OWNER='DatadogRUM/MultiSceneSupport/Results/S2-coverage-home-collection-20260928.json'
FIELDS=['original_build_root','products','observer_refresh','build_plan_sha256','build_receipts','scope','measurement','helpers']


def check(condition,message,runner):runner.require(condition,'candidate continuation: '+message)


def nested_references(value,s):
    if isinstance(value,dict):
        if set(value)=={'path','sha256'}:
            p=Path(value['path'])
            s.require(p.is_absolute() and not p.is_symlink() and p.is_file() and s.sha(p)==value['sha256'],'changed baseline reference')
        else:
            for child in value.values():nested_references(child,s)
    elif isinstance(value,list):
        for child in value:nested_references(child,s)


def unchanged_cell(out,row,runner):
    check(not out.is_symlink(),'symlinked historical cell',runner)
    actual=runner.shared.tree(out);actual.pop('summary.json')
    check(actual==row['artifacts'],'historical raw artifact inventory changed',runner)


def history(summary_ref,base,runner):
    """Check frozen historical inputs, without binding them to today's observer."""
    s=runner.shared;row=sessions.read_reference(summary_ref,s);out=Path(summary_ref['path']).parent;runtime=out.parent.parent
    plan=s.read(runtime/'runtime-plan.json')
    check(s.sha(runtime/'runtime-plan.json')==row['runtime_plan_sha256'] and plan['build_plan_sha256']==base['build_plan_sha256']
        and plan['scope']==base['scope'] and plan['measurement']==base['measurement'],'historical source or contract differs',runner)
    check(s.tree(runtime/'helpers')==plan['helpers'],'historical helper snapshot changed',runner)
    sessions.reviewed(runtime.parent,plan,runner);stage=sessions.stage_receipts(runtime.parent,plan,runner)
    check(stage['stage_id']==row['stage_id'],'historical stage differs',runner)
    unchanged_cell(out,row,runner)
    refresh=sessions.read_reference(plan['observer_refresh'],s);build_key=row['identity']['cell']['build'];arm=refresh['arms'][build_key]
    frozen=Path(plan['observer_refresh']['path']).parent/build_key;built=s.read(frozen/'build-result.json')
    check(arm['revision']==row['identity']['source'] and s.tree(frozen/'sdk')==arm['sdk'] and s.tree(frozen/'client')==arm['client']
        and built['compiler']==runner.build.compiled(frozen,arm),'historical source/compiler changed',runner)
    product=plan['products'][build_key+'-UIKit-single']
    check(s.product(product['path'],bundle=product['bundle'])==product['product'],'historical product changed',runner)
    return row,out,runtime,plan,stage


def reference_inputs(plan,base,runner):
    s=runner.shared;native=sessions.read_reference(plan['accepted_baseline_reference'],s)
    offline=sessions.read_reference(plan['offline_comparison_reference'],s)
    nested_references(native,s);nested_references(offline,s)
    check(native['state']=='ONE_OF_TWELVE_CELLS_QUALIFIED' and native['cell']==dict(CELL,build='baseline-26.5')
        and all(native[k]=='PASS' for k in ['scenario','evidence','cleanup']),'wrong accepted reference',runner)
    check(offline['state']=='OFFLINE_PARITY_ASSESSMENT' and offline['original_verdict']==offline['original_cleanup']=='INVALID'
        and offline['original_failure_unchanged'] is True and offline['gates_closed']==[],'offline evidence is not native acceptance',runner)
    check(native['source']==offline['source']==s.ARMS['A'] and native['run_id']!=offline['run_id'],'baseline source/run differs',runner)
    row,out,runtime,old,stage=history(native['summary'],base,runner)
    check(old['previous'] is None and old['inherited']=={} and old['matrix']==[native['cell']],'accepted reference is not the first exact cell',runner)
    accepted=sessions.cells(runtime.parent,old,stage,runner);complete=sessions.read_reference(native['session_complete'],s)
    check(complete['state']=='COMPLETE_SITTING' and complete['accepted']==accepted
        and complete['stage_sha256']==s.sha(runtime/'native-admission.json') and complete['comparison_sha256']==native['comparison']['sha256'],
        'accepted sitting completion changed',runner)
    a=sessions.read_reference(native['local_result'],s)
    failed,failed_out,failed_runtime,failed_plan,failed_stage=history(offline['original_summary'],base,runner)
    check(failed['state']==failed['cleanup']=='INVALID' and failed['identity']['cell']==dict(CELL,build='baseline-27.1')
        and failed['identity']['run_id']==offline['run_id'],'original failure was relabeled',runner)
    raw=Path(offline['source_prefix']['path']).read_bytes()
    rows=runner.capture.local_event_collection.terminal_rows(raw,run_id=offline['run_id'],prefix=raw)
    check(rows is not None and len(rows)==offline['assessed_rows']==329 and rows[-1]['sequence']==offline['native_home_geometry_sequence'],
        'offline prefix is incomplete or includes restoration',runner)
    b=sessions.read_reference(offline['local_inventory'],s)
    check(offline['comparison_baseline']==native['local_result'] and b['run_id']==offline['run_id']
        and b['cell']==['baseline-27.1','duo','UIKit','stack'] and a['run_id']==native['run_id'], 'reference inventory identity differs',runner)
    check(a['view_count']==b['view_count']==11 and a['automatic_action_count']==b['automatic_action_count']==25
        and a['missing_action_phases']==b['missing_action_phases'] and len(b['missing_action_phases'])==4,'reviewed finite inventory changed',runner)
    check(all(not value[k] for value in [a,b] for k in ['duplicate_action_ids','unknown_action_owners','unassigned_actions','errors']),
        'reference ownership anomaly',runner)
    check({f:runner.analyze.compare(a,b,f) for f in ['views','actions']}==offline['comparisons'],'reviewed offline parity changed',runner)
    restored=sessions.read_reference(offline['separate_restoration'],s)
    check(restored['state']=='PASS' and restored['original_verdict']==restored['original_cleanup']=='INVALID'
        and restored['original_artifacts_unchanged'] is True,'separate restoration proof changed',runner)
    key=runner.cell_key(CELL);check(key in failed_stage['session_claims'],'old candidate claim absent',runner)
    check(not (failed_runtime/'cells'/key).exists() and not list(failed_runtime.glob(key+'-driver*'))
        and not (failed_runtime/'session-complete.json').exists(),'old candidate already attempted or failure relabeled',runner)
    for old_runtime in [runtime,failed_runtime]:
        check(not s.process(s.read(old_runtime/'session-run.json')['pid']),'historical runner still active',runner)
    return {'ACCEPTED_BASELINE_26_5':a,'OFFLINE_COMPARISON_27_1':b}


def verify(root,plan,runner):
    s=runner.shared;source=Path(plan['source_runtime_root']);base=runner.verify(source)
    check(plan['kind']==KIND and base['kind']==runner.S2_KIND and plan['source_runtime']==sessions.reference(source/'runtime/runtime-plan.json',s),
        'source preparation changed',runner)
    check(plan['matrix']==plan['universe']==[CELL] and plan['inherited']=={} and plan['previous'] is None
        and plan['release_acceptance'] is False and plan['native_cells_credited']==0 and plan['gates_closed']==[],
        'expanded cell or inherited acceptance',runner)
    check(all(plan[k]==base[k] for k in FIELDS) and s.tree(root/'runtime/helpers')==plan['helpers'],'current product/helper binding changed',runner)
    check(plan['contract']==dict(base['contract'],stage_execution_seconds=sessions.budget([CELL],base['contract'],runner)),'clocks changed',runner)
    series=sessions.read_reference(plan['series'],s)
    expected={k:plan[k] for k in ['source_runtime','accepted_baseline_reference','offline_comparison_reference','home_qualification','home_provenance','helpers','universe']}
    check(series==dict(expected,kind=KIND,native_attempts_per_cell=1),'series or reference classes changed',runner)
    home=sessions.read_reference(plan['home_qualification'],s)
    nested_references(plan['home_provenance'],s)
    provenance={k:sessions.read_reference(value,s) for k,value in plan['home_provenance'].items()}
    check(set(provenance)=={'definition','review','admission','post_exit'} and provenance['review']['state']=='PASS'
        and provenance['review']['reviewer']=='/root/c06_runtime_plan'
        and provenance['admission']['definition_sha256']==provenance['review']['definition_sha256']==plan['home_provenance']['definition']['sha256']
        and provenance['admission']['identity']==home['identity'] and provenance['post_exit']['result']==plan['home_qualification']
        and provenance['definition']['refresh']==base['observer_refresh'],'Home qualification provenance changed',runner)
    check(all(home[k]=='PASS' for k in ['state','scenario','evidence','cleanup']) and home['release_acceptance'] is False
        and home['native_cells_credited']==0,'Home mechanism unqualified or credited as coverage',runner)
    q=Path(plan['home_qualification']['path']).parent.parent;definition=provenance['definition']
    for name,digest in home['artifacts'].items():
        check(s.sha(q/'out'/name)==digest,'Home qualification artifact changed',runner)
    for name in ['HumanObservation.swift','human_variant.py','human_home.py','human_capture.py']:
        path='tools/multi-scene/automatic-coverage/'+name
        check(s.sha(s.REPO/path)==definition['helpers'].get(path, s.read(Path(base['observer_refresh']['path']))['observer_sha256'] if name=='HumanObservation.swift' else None),
            'qualified Home mechanism changed',runner)
    check(s.read(q/'post-exit.json')['processes_absent'] is True,'Home qualification has active workers',runner)
    reference_inputs(plan,base,runner)
    return plan


def prepare(args,runner):
    s=runner.shared;source=args.original.resolve();base=runner.verify(source);root=args.root.resolve()
    check(base['kind']==runner.S2_KIND and not root.exists() and not args.series.exists(),'new candidate preparation/series required',runner)
    refs=dict(accepted_baseline_reference=sessions.reference(args.accepted,s),offline_comparison_reference=sessions.reference(args.offline,s),home_qualification=sessions.reference(args.home,s))
    qualification=args.home.resolve().parent.parent
    refs['home_provenance']={name:sessions.reference(qualification/(name.replace('_','-')+'.json'),s) for name in ['definition','review','admission','post_exit']}
    folder=root/'runtime';folder.mkdir(parents=True)
    for name in ['cells','operator']:(folder/name).mkdir()
    shutil.copytree(source/'runtime/helpers',folder/'helpers');args.series.mkdir();(args.series/'claims').mkdir()
    plan={**{k:base[k] for k in FIELDS},**refs, 'kind':KIND,'prepared_at':time.time(),'source_runtime_root':str(source),
        'source_runtime':sessions.reference(source/'runtime/runtime-plan.json',s),'matrix':[CELL],'universe':[CELL],'inherited':{},'previous':None,
        'contract':dict(base['contract'],stage_execution_seconds=sessions.budget([CELL],base['contract'],runner)),
        'release_acceptance':False,'native_cells_credited':0,'gates_closed':[], 'publication':runner.transport.publication_preflight(folder)}
    values={k:plan[k] for k in ['source_runtime','accepted_baseline_reference','offline_comparison_reference','home_qualification','home_provenance','helpers','universe']}
    s.save(args.series/'series.json',dict(values,kind=KIND,native_attempts_per_cell=1),exclusive=True);plan['series']=sessions.reference(args.series/'series.json',s)
    runner.human_operator.publish(folder/'operator',{'instruction':'Waiting for reviewed candidate-only admission and fresh readiness.'})
    s.save(folder/'runtime-plan.json',plan,exclusive=True);verify(root,plan,runner)
    print(json.dumps(dict(state='CANDIDATE_PREPARED_NOT_ADMITTED',root=str(root),plan_sha256=s.sha(folder/'runtime-plan.json'),native_launches=0)))


def ready(root,plan,operator,runner):
    s=runner.shared;folder=root/'runtime';owner=s.read(s.REPO/OWNER)['continuation_preparation']
    check(owner['series']==plan['series'] and owner['plan']==sessions.reference(folder/'runtime-plan.json',s),'missing owning-record authority',runner)
    check(not (folder/'session-run.json').exists() and not (folder/'candidate-complete.json').exists() and not list((folder/'cells').iterdir()),'candidate already consumed',runner)
    runner.human_operator.ready(folder/'operator',dict(operator,plan_sha256=operator['runtime_plan_sha256']),folder/'runtime-plan.json',device=operator['device'],mode='coverage')


def comparison(folder,plan,stage,runner):
    s=runner.shared;references=reference_inputs(plan,runner.verify(Path(plan['source_runtime_root'])),runner)
    attempted=runner.prior_cells(folder,plan,stage);comparisons=[]
    if attempted:
        current=s.read(folder/'cells'/runner.cell_key(CELL)/'local-result.json')
        check(current['run_id'] not in {v['run_id'] for v in references.values()},'restored reference run',runner)
        for kind,value in references.items():
            for family in ['views','actions']:
                comparisons.append(dict(reference_class=kind,family=family,**runner.analyze.compare(value,current,family)))
    differences=[v for v in comparisons if v['status'] in ['REVIEW_REQUIRED','DIFFERENCE_REQUIRES_CLASSIFICATION']]
    return dict(state='REVIEW_REQUIRED' if differences else 'CANDIDATE_COMPARISON_CAPTURED' if attempted else 'CANDIDATE_NOT_RUN',
        runtime_plan_sha256=stage['runtime_plan_sha256'],stage_id=stage['stage_id'],qualified_cells=len(attempted),required_cells=1,
        reference_classes=list(references),comparisons=comparisons,source_differences=len(differences),
        release_acceptance=False,native_cells_credited=0,gates_closed=[],updated_at=time.time())


def finish(root,plan,stage,runner):
    s=runner.shared;folder=root/'runtime';native=sessions.cells(root,plan,stage,runner);result=comparison(folder,plan,stage,runner)
    check(set(native)=={runner.cell_key(CELL)} and not result['source_differences'] and time.time()<=stage['cleanup_deadline'],'candidate incomplete or requires classification',runner)
    s.save(folder/'comparison.json',result)
    s.save(folder/'candidate-complete.json',dict(state='CANDIDATE_CAPTURE_COMPLETE',finished_at=time.time(),candidate=native,
        comparison_sha256=s.sha(folder/'comparison.json'),stage_sha256=s.sha(folder/'native-admission.json'),
        accepted_baseline_reference=plan['accepted_baseline_reference'],offline_comparison_reference=plan['offline_comparison_reference'],
        release_acceptance=False,native_cells_credited=0,gates_closed=[]),exclusive=True)


if __name__=='__main__':
    import human_runtime as runner
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--original',type=Path,required=True)
    for name in ['series','accepted','offline','home']:p.add_argument('--'+name,type=Path,required=True)
    prepare(p.parse_args(),runner)
