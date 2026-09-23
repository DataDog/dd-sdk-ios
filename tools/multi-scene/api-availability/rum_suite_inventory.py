#!/usr/bin/env python3
"""Reconcile a source-bound discovery placeholder without repeating passed tests."""
import argparse
import json
import os
from pathlib import Path
import time
import rum_suite_execution as execution

original=execution.original
shared=execution.shared
require=execution.require
HERE=Path(__file__).resolve().parent
DEFINITION=shared.REPO/'DatadogRUM/MultiSceneSupport/Results/EXP-225-rum-inventory-continuation.json'
PLACEHOLDER='DatadogRUMTests/DDXCSkippedTestCase'


def helpers():
    return {**execution.helpers(),**{str(p):shared.sha(p) for p in [Path(__file__).resolve(),HERE/'test_rum_suite_inventory.py']}}


def classify(value):
    raw=original.enumerate_inventory(value)
    placeholders=[item for item in raw if item==PLACEHOLDER]
    selected=[item for item in raw if item!=PLACEHOLDER]
    require(selected and all(len(item.split('/'))==3 and item.endswith(')') for item in selected),
            'unknown class-only or malformed executable entry')
    return dict(raw_count=len(raw),identifiers=selected,non_cases=placeholders)


def verify(root):
    definition=shared.read(root/'definition.json');prior=Path(definition['prior_root'])
    require(shared.sha(root/'definition.json')==shared.sha(DEFINITION),'inventory definition changed')
    for key in ['source_helper','original_27_summary','original_selection','original_stage_stop','prior_definition','original_enumeration']:
        reference=definition[key];require(shared.sha(reference['path'])==reference['sha256'],'bound evidence changed: '+key)
    prior_definition,built=execution.reviewed(prior)
    require(prior_definition['source']==definition['source'],'source mismatch')
    require(not (prior/'runtime-17.5').exists(),'17.5 already attempted')
    return definition,prior_definition,built


def timely_receipt(folder,name,deadline):
    receipt=shared.read(folder/(name+'-receipt.json'))
    proof=receipt.get('quiescence') or {}
    require(receipt['returncode']==0 and receipt['failure'] is None and receipt['cleanup_failure'] is None and
            receipt['finished_at']<deadline and proof.get('state')=='PASS' and proof.get('remaining')==[] and
            proof.get('group')==receipt['pid'],'unqualified command receipt: '+name)
    require(receipt['log_sha256']==shared.sha(folder/(name+'.log')),'changed raw command output: '+name)


def assess27(root):
    definition,_,_=verify(root);folder=Path(definition['prior_root'])/'runtime-27.0'
    prior=shared.read(folder/'summary.json');admission=shared.read(folder/'execution-admission.json')
    require(prior['overall']=='INVALID' and prior['failure']=='ValueError: executed case inventory mismatch' and
            prior['cleanup']=='PASS' and prior['finished_at']<prior['cleanup_deadline'],'different original failure/cleanup')
    current=original.inventory(folder);current.pop('summary.json')
    require(current==prior['artifacts'],'original runtime evidence changed')
    for name in ['execute','result-summary','result-tests']:timely_receipt(folder,name,admission['deadline'])
    discovery=shared.read(definition['original_enumeration']['path']);selection=classify(discovery)
    require(selection['non_cases']==[PLACEHOLDER],'different discovery discrepancy')
    require(original.enumerate_inventory(discovery)==shared.read(definition['original_selection']['path'])['identifiers'],
            'original selected inventory differs')
    tree=json.loads((folder/'result-tests.log').read_text());summary=json.loads((folder/'result-summary.log').read_text())
    _,invocations=original.result_inventory(tree)
    original.result_environment(summary,tree,prior['expected_result_device'],invocations)
    qualified=original.assess(selection['identifiers'],tree,summary,[])
    return dict(state='PASS_OFFLINE_RECONCILIATION',source=definition['source'],original_verdict='INVALID_UNCHANGED',
                original_summary=definition['original_27_summary'],raw_enumeration=definition['original_enumeration'],
                source_helper=definition['source_helper'],selection=selection,qualified=qualified,cleanup='PASS',
                new_native_executions=0,new_builds=0)


def prepare(root):
    require(not (root/'plan.json').exists(),'preparation consumed')
    assessment=assess27(root)
    shared.save(root/'offline-27.json',assessment,exclusive=True)
    shared.save(root/'plan.json',dict(definition=shared.sha(DEFINITION),helpers=helpers(),
                assessment_sha256=shared.sha(root/'offline-27.json')),exclusive=True)
    print(json.dumps(dict(state=assessment['state'],cases=assessment['qualified']['cases'],
                         executions=assessment['qualified']['executions'])),flush=True)


def reviewed(root):
    definition,prior,built=verify(root);plan=shared.read(root/'plan.json')
    require(plan['definition']==shared.sha(DEFINITION) and plan['helpers']==helpers() and
            plan['assessment_sha256']==shared.sha(root/'offline-27.json'),'stale inventory preparation')
    require(assess27(root)==shared.read(root/'offline-27.json'),'offline assessment changed')
    review=shared.read(root/'review.json');controls=shared.read(root/'controls.json')
    require(review['state']==controls['state']=='PASS' and review['reviewer']=='/root/c06_runtime_plan' and
            review['plan_sha256']==controls['plan_sha256']==shared.sha(root/'plan.json') and
            review['controls_sha256']==shared.sha(root/'controls.json') and controls['helpers']==helpers(),'unqualified review/controls')
    return definition,prior,built


def run17(root):
    definition,prior,built=reviewed(root);folder=root/'runtime-17.5'
    require(not folder.exists() and not (root/'stage.json').exists(),'native attempt consumed')
    budgets=definition['budgets_seconds'];started=time.time();cleanup_limit=started+budgets['runtime_reservation']
    shared.save(root/'stage.json',dict(started_at=started,deadline=started+budgets['stage'],
                plan_sha256=shared.sha(root/'plan.json')),exclusive=True)
    folder.mkdir();spec=next(e for e in prior['environments'] if e['runtime']=='17.5');workers=[];owned=False;initial=None
    result=dict(runtime='17.5',source=definition['source'],scenario='NOT_EXECUTED',evidence='INCOMPLETE',
                cleanup='NOT_STARTED',overall='INVALID',started_at=started,cleanup_limit=cleanup_limit)
    def call(argv,name,deadline):
        return execution.command(argv,folder,name,deadline=deadline,cleanup_limit=cleanup_limit,workers=workers)
    try:
        call(['xcrun','simctl','list','devices','available','--json'],'devices',time.time()+30)
        devices=json.loads((folder/'devices.log').read_text())
        rows=[(r,d) for r,ds in devices['devices'].items() for d in ds if d['udid']==spec['device']]
        require(len(rows)==1 and rows[0][0].endswith('iOS-17-5'),'runtime changed')
        runtime,device=rows[0];initial=device['state']
        require(initial=='Shutdown' and device['name']==spec['name'] and device['deviceTypeIdentifier']==spec['device_type'] and
                device['isAvailable'],'original simulator state/model changed')
        call(['xcrun','simctl','list','runtimes','--json'],'runtimes',time.time()+30)
        rows=[r for r in json.loads((folder/'runtimes.log').read_text())['runtimes'] if r['identifier']==runtime and r['isAvailable']]
        require(len(rows)==1 and rows[0]['version']=='17.5','runtime build absent')
        expected=dict(architecture='arm64',deviceId=spec['device'],deviceName=spec['name'],modelName=spec['result_model'],
                      osBuildNumber=rows[0]['buildversion'],osVersion='17.5',platform='iOS Simulator')
        shared.save(folder/'environment.json',dict(device=device,runtime=rows[0],expected=expected),exclusive=True)
        boot=time.time()+budgets['boot'];owned=True
        call(['xcrun','simctl','boot',spec['device']],'boot',min(time.time()+60,boot))
        call(['xcrun','simctl','bootstatus',spec['device'],'-b'],'bootstatus',min(time.time()+120,boot))
        base=['xcodebuild','test-without-building','-xctestrun',built['test_run'],'-destination','platform=iOS Simulator,id='+spec['device'],
              '-parallel-testing-enabled','NO','-enableCodeCoverage','NO']
        call(base+['-enumerate-tests','-test-enumeration-style','flat','-test-enumeration-format','json',
                   '-test-enumeration-output-path',str(folder/'enumeration.json')],'enumerate',time.time()+budgets['enumeration'])
        selection=classify(shared.read(folder/'enumeration.json'))
        require(selection['identifiers']==shared.read(root/'offline-27.json')['selection']['identifiers'],
                'executable inventory differs from same compiled27 target')
        shared.save(folder/'selection.json',selection,exclusive=True);verify(root)
        deadline=min(time.time()+budgets['execution'],cleanup_limit-budgets['cleanup']-30)
        require(time.time()<deadline and not os.path.lexists(folder/'result.xcresult'),'no execution budget or stale result')
        shared.save(folder/'execution-admission.json',dict(at=time.time(),deadline=deadline,
                    result_bundle=str(folder/'result.xcresult'),selection_sha256=shared.sha(folder/'selection.json')),exclusive=True)
        result['scenario']='INCOMPLETE'
        try:call(base+['-resultBundlePath',str(folder/'result.xcresult'),'-collect-test-diagnostics','never'],'execute',deadline)
        except Exception as error:result['execution_failure']=str(error)
        execution.collect_results(folder,deadline,call)
        tree=json.loads((folder/'result-tests.log').read_text());summary=json.loads((folder/'result-summary.log').read_text())
        cases,invocations=original.result_inventory(tree);original.result_environment(summary,tree,expected,invocations)
        require(sorted(cases)==selection['identifiers'],'executed case inventory mismatch')
        result.update(evidence='PASS',scenario='FAIL')
        result.update(original.assess(selection['identifiers'],tree,summary,prior['allowed_skips']['17.5']))
        require('execution_failure' not in result and time.time()<deadline,'failed or late XCTest/assertions')
        result['scenario']='PASS'
    except Exception as error:result['failure']=type(error).__name__+': '+str(error)
    finally:
        cleanup=min(cleanup_limit,time.time()+budgets['cleanup']);result['cleanup_deadline']=cleanup
        try:
            execution.ensure_quiescent(workers,folder,cleanup-30)
            if owned:call(['xcrun','simctl','shutdown',spec['device']],'shutdown',cleanup-30)
            call(['xcrun','simctl','list','devices','available','--json'],'restored',cleanup-30)
            states=[d['state'] for ds in json.loads((folder/'restored.log').read_text())['devices'].values() for d in ds if d['udid']==spec['device']]
            require(initial is not None and states==[initial],'original simulator state not restored')
            verify(root);require(time.time()<cleanup,'late cleanup');result['cleanup']='PASS'
        except Exception as error:result.update(cleanup='INVALID',cleanup_failure=str(error))
        if all(result[k]=='PASS' for k in ['scenario','evidence','cleanup']):result['overall']='PASS'
        result['finished_at']=time.time();result['artifacts']=original.inventory(folder)
        shared.save(folder/'summary.json',result,exclusive=True)
        print(json.dumps({k:v for k,v in result.items() if k not in ['artifacts','parameter_multiplicities']}),flush=True)
    return result['overall']=='PASS'


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['prepare','17.5']);parser.add_argument('--root',type=Path,required=True)
    args=parser.parse_args()
    if args.action=='prepare':prepare(args.root.resolve())
    else:raise SystemExit(0 if run17(args.root.resolve()) else 1)
