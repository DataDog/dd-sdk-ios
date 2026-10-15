#!/usr/bin/env python3
"""Execute the unrun RUM suite using immutable, already qualified products."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time
import rum_suite as original

shared=original.shared
require=original.require
HERE=Path(__file__).resolve().parent
DEFINITION=shared.REPO/'DatadogRUM/MultiSceneSupport/Results/EXP-225-rum-suite-continuation.json'


def helpers():
    return {**original.helpers(),**{str(p):shared.sha(p) for p in [Path(__file__).resolve(),HERE/'test_rum_suite_execution.py']}}


def verify(root):
    plan=shared.read(root/'plan.json');definition=shared.read(root/'definition.json')
    require(plan['definition']==shared.sha(DEFINITION)==shared.sha(root/'definition.json'),'continuation definition changed')
    require(plan['helpers']==helpers(),'continuation helpers changed')
    source=Path(definition['build_root'])
    for name in ['original_definition','inputs','built','original_review','original_invalid','original_stage_stop','later_quiescence']:
        item=definition[name];require(shared.sha(item['path'])==item['sha256'],'original evidence changed: '+name)
    require(original.reviewed(source)['source']==definition['source'],'compiled source changed')
    built=original.verify_build(source)
    for relative,fingerprint in plan['original_receipts'].items():
        require(shared.sha(source/relative)==fingerprint,'original receipt changed: '+relative)
    return definition,built


def prepare(root):
    require(not (root/'plan.json').exists(),'continuation already prepared')
    definition=shared.read(root/'definition.json');source=Path(definition['build_root'])
    require(shared.sha(DEFINITION)==shared.sha(root/'definition.json'),'definition copy differs')
    original.reviewed(source);original.verify_build(source)
    previous=shared.read(source/'runtime-27.0/summary.json')
    require(previous['scenario']=='NOT_EXECUTED' and previous['overall']=='INVALID' and previous['cleanup']=='PASS',
            'only unexecuted methods are admitted')
    require(not (source/'runtime-27.0/execution-admission.json').exists() and not (source/'runtime-17.5').exists(),
            'original execution already admitted')
    receipt_paths=[*source.glob('*.json'),*(source/'runtime-27.0').rglob('*.json')]
    receipts={str(p.relative_to(source)):shared.sha(p) for p in receipt_paths}
    shared.save(root/'plan.json',dict(definition=shared.sha(DEFINITION),helpers=helpers(),original_receipts=receipts),exclusive=True)
    verify(root)
    print(json.dumps(dict(state='PREPARED_WITHOUT_REBUILD',root=str(root))),flush=True)


def reviewed(root):
    definition,built=verify(root);review=shared.read(root/'review.json');controls=shared.read(root/'controls.json')
    require(review['state']==controls['state']=='PASS' and review['reviewer']=='/root/c06_runtime_plan' and
            review['plan_sha256']==controls['plan_sha256']==shared.sha(root/'plan.json') and
            review['controls_sha256']==shared.sha(root/'controls.json') and controls['helpers']==helpers(),
            'unqualified continuation review/controls')
    return definition,built


def stage(root):
    definition,_=reviewed(root);now=time.time()
    require(not any((root/('runtime-'+r)).exists() for r in ['27.0','17.5']),'runtime already consumed')
    shared.save(root/'stage.json',dict(started_at=now,deadline=now+definition['budgets_seconds']['stage'],
                plan_sha256=shared.sha(root/'plan.json'),review_sha256=shared.sha(root/'review.json')),exclusive=True)


def inventory(group,folder,index,deadline):
    """The reader has its own group; retain its actual output even on failure."""
    started=time.time();stdout=stderr='';failure=None;code=None
    try:
        require(started<deadline,'process inventory after cleanup deadline')
        result=subprocess.run(['/bin/ps','-axo','pid=,pgid='],capture_output=True,text=True,start_new_session=True,
                              timeout=min(15,deadline-started),check=True)
        stdout=result.stdout;stderr=result.stderr;code=result.returncode
        require(time.time()<deadline,'late process inventory')
        rows=[line.split() for line in stdout.splitlines()]
        require(rows and all(len(r)==2 and all(n.isdigit() for n in r) for r in rows),'malformed process inventory')
        require(len({int(r[0]) for r in rows})==len(rows),'duplicate process inventory')
        return sorted(int(pid) for pid,pgid in rows if int(pgid)==group)
    except BaseException as error:
        failure=type(error).__name__+': '+str(error)
        stdout=getattr(error,'stdout',None) or stdout;stderr=getattr(error,'stderr',None) or stderr
        code=getattr(error,'returncode',code)
        raise
    finally:
        name='inventory-'+str(index)
        for suffix,value in [('stdout',stdout),('stderr',stderr)]:
            with (folder/(name+'.'+suffix)).open('xb') as stream:
                stream.write(value if isinstance(value,bytes) else value.encode())
        shared.save(folder/(name+'.json'),dict(started_at=started,finished_at=time.time(),deadline=deadline,
                    returncode=code,failure=failure,stdout_sha256=shared.sha(folder/(name+'.stdout')),
                    stderr_sha256=shared.sha(folder/(name+'.stderr'))),exclusive=True)


def quiesce(group,folder,deadline):
    require(group>1 and group!=os.getpgrp(),'refuse unrelated/current process group')
    folder.mkdir();index=0;started=time.time();signals=[]
    def read():
        nonlocal index
        index+=1;return inventory(group,folder,index,deadline)
    before=current=read()
    for sig,seconds in [(signal.SIGTERM,1),(signal.SIGKILL,2)]:
        if not current:break
        require(time.time()<deadline,'no budget to reap owned workers')
        try:os.killpg(group,sig);signals.append(int(sig))
        except ProcessLookupError:pass
        limit=min(deadline,time.time()+seconds)
        current=read()
        while current and time.time()<limit:
            time.sleep(min(.05,max(0,limit-time.time())));current=read()
    finished=time.time()
    return dict(state='PASS' if not current and finished<deadline else 'INVALID',group=group,before=before,
                remaining=current,started_at=started,finished_at=finished,deadline=deadline,signals=signals,inventories=index)


def ensure_quiescent(workers,folder,deadline):
    """Separate restoration proof cannot repair an earlier command verdict."""
    for worker in workers:
        if worker.get('quiescence',{}).get('state')=='PASS':continue
        proof=quiesce(worker['pid'],folder/(worker['name']+'-restoration-quiescence'),deadline)
        shared.save(folder/(worker['name']+'-restoration.json'),proof,exclusive=True)
        require(proof['state']=='PASS','defer simulator teardown while native workers are unproven')


def command(argv,folder,name,*,deadline,cleanup_limit,cwd=None,workers=None):
    started=time.time();cleanup_deadline=min(cleanup_limit,deadline+30);process=None;failure=cleanup_failure=None;proof=None
    log=folder/(name+'.log');worker=None
    try:
        require(started<deadline<cleanup_deadline,'command lacks its fixed execution/cleanup reservation')
        with log.open('x') as stream:
            process=subprocess.Popen(argv,cwd=cwd,env=shared.environment(),stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
            worker=dict(pid=process.pid,name=name)
            if workers is not None:workers.append(worker)
            process.wait(timeout=max(.001,deadline-time.time()))
        require(process.returncode==0 and time.time()<deadline,name+' failed or late')
    except BaseException as error:
        failure=type(error).__name__+': '+str(error)
        raise
    finally:
        try:
            if process is not None:
                for sig in [signal.SIGTERM,signal.SIGKILL]:
                    if process.poll() is not None:break
                    try:os.killpg(process.pid,sig)
                    except ProcessLookupError:pass
                    try:process.wait(timeout=min(1,max(.001,cleanup_deadline-time.time())))
                    except subprocess.TimeoutExpired:pass
                proof=quiesce(process.pid,folder/(name+'-quiescence'),cleanup_deadline)
                require(process.poll() is not None and proof['state']=='PASS','owned command group remains or cleanup is late')
                worker['quiescence']=proof
        except Exception as error:cleanup_failure=type(error).__name__+': '+str(error)
        shared.save(folder/(name+'-receipt.json'),dict(argv=argv,started_at=started,finished_at=time.time(),deadline=deadline,
                    cleanup_deadline=cleanup_deadline,failure=failure,cleanup_failure=cleanup_failure,quiescence=proof,
                    pid=process.pid if process else None,returncode=process.returncode if process else None,
                    log_sha256=shared.sha(log) if log.exists() else None),exclusive=True)
        require(cleanup_failure is None,cleanup_failure)


def enumeration_reuse(source,expected_device):
    folder=source/'runtime-27.0';receipt=shared.read(folder/'enumerate-receipt.json')
    require(receipt['returncode']==0 and receipt['failure'] is None and receipt['finished_at']<receipt['deadline'],
            'enumeration command failed or returned late')
    require(shared.read(folder/'environment.json')['expected_result_device']==expected_device,'enumeration runtime changed')
    later=shared.read(source/'later-quiescence.json')
    require(later['state']=='PASS' and later['remaining']==[] and receipt['pid'] in later['groups'],
            'original enumeration workers remain unqualified')
    return original.enumerate_inventory(shared.read(folder/'enumeration.json'))


def collect_results(folder,deadline,call):
    """Read this attempt's evidence only after timely, proven native quiescence."""
    receipt=shared.read(folder/'execute-receipt.json')
    admission=shared.read(folder/'execution-admission.json');bundle=folder/'result.xcresult'
    require(receipt['cleanup_failure'] is None and (receipt.get('quiescence') or {}).get('state')=='PASS',
            'result extraction requires proven native quiescence')
    require(receipt['returncode'] is not None and receipt['returncode']>=0 and
            receipt['finished_at']<deadline and time.time()<deadline,'result extraction after interrupted/late execution')
    require(admission['deadline']==deadline and admission['result_bundle']==str(bundle) and
            bundle.is_dir() and not bundle.is_symlink() and bundle.resolve().parent==folder.resolve(),
            'missing/foreign result bundle')
    require(bundle.stat().st_birthtime>=admission['at'],'result bundle predates this execution')
    for part in ['summary','tests']:
        call(['xcrun','xcresulttool','get','test-results',part,'--path',str(folder/'result.xcresult')],'result-'+part,deadline)


def run(root,runtime):
    definition,built=reviewed(root);admission=shared.read(root/'stage.json');source=Path(definition['build_root'])
    require(admission['plan_sha256']==shared.sha(root/'plan.json') and admission['review_sha256']==shared.sha(root/'review.json'),
            'stage binding changed')
    if runtime=='17.5':require(shared.read(root/'runtime-27.0/summary.json')['overall']=='PASS','previous runtime did not qualify')
    folder=root/('runtime-'+runtime);require(not folder.exists(),'runtime attempt already consumed')
    spec=next(e for e in definition['environments'] if e['runtime']==runtime);budgets=definition['budgets_seconds']
    started=time.time();require(started+budgets['runtime_reservation']<admission['deadline'],'full runtime reservation does not fit')
    cleanup_limit=started+budgets['runtime_reservation'];folder.mkdir()
    result=dict(runtime=runtime,device=spec['device'],source=definition['source'],scenario='NOT_EXECUTED',evidence='INCOMPLETE',
                cleanup='NOT_STARTED',overall='INVALID',started_at=started,plan_sha256=shared.sha(root/'plan.json'),cleanup_limit=cleanup_limit)
    original_state=None;owned=False;workers=[]
    def call(argv,name,deadline):
        return command(argv,folder,name,deadline=deadline,cleanup_limit=cleanup_limit,workers=workers)
    try:
        call(['xcrun','simctl','list','devices','available','--json'],'devices',time.time()+30)
        state=json.loads((folder/'devices.log').read_text())
        matches=[(r,d) for r,ds in state['devices'].items() for d in ds if d['udid']==spec['device']]
        require(len(matches)==1 and matches[0][0].endswith('iOS-'+runtime.replace('.','-')),'runtime absent/changed')
        device=matches[0][1]
        require(device['name']==spec['name'] and device['deviceTypeIdentifier']==spec['device_type'] and device['isAvailable'],
                'defined device model/name changed')
        call(['xcrun','simctl','list','runtimes','--json'],'runtimes',time.time()+30)
        runtimes=json.loads((folder/'runtimes.log').read_text())
        values=[r for r in runtimes['runtimes'] if r['identifier']==matches[0][0] and r['isAvailable']]
        require(len(values)==1 and values[0]['version']==runtime,'runtime version changed')
        expected=dict(architecture='arm64',deviceId=spec['device'],deviceName=spec['name'],modelName=spec['result_model'],
                      osBuildNumber=values[0]['buildversion'],osVersion=runtime,platform='iOS Simulator')
        original_state=device['state'];require(original_state=='Shutdown','selected simulator must initially be Shutdown')
        result.update(original_state=original_state,expected_result_device=expected)
        shared.save(folder/'admission.json',dict(**result,built_sha256=shared.sha(source/'built.json'),stage_deadline=admission['deadline']),exclusive=True)
        boot_deadline=time.time()+budgets['boot_per_runtime']
        owned=True;call(['xcrun','simctl','boot',spec['device']],'boot',min(time.time()+60,boot_deadline))
        call(['xcrun','simctl','bootstatus',spec['device'],'-b'],'bootstatus',min(time.time()+120,boot_deadline))
        base=['xcodebuild','test-without-building','-xctestrun',built['test_run'],'-destination','platform=iOS Simulator,id='+spec['device'],
              '-parallel-testing-enabled','NO','-enableCodeCoverage','NO']
        if runtime=='27.0':
            selected=enumeration_reuse(source,expected)
            shared.save(folder/'enumeration-reuse.json',dict(path=str(source/'runtime-27.0/enumeration.json'),
                sha256=shared.sha(source/'runtime-27.0/enumeration.json'),count=len(selected),original_verdict='INVALID_UNCHANGED'),exclusive=True)
        else:
            call(base+['-enumerate-tests','-test-enumeration-style','flat','-test-enumeration-format','json',
                       '-test-enumeration-output-path',str(folder/'enumeration.json')],'enumerate',time.time()+budgets['enumeration_per_runtime'])
            selected=original.enumerate_inventory(shared.read(folder/'enumeration.json'))
        require(set(original.PARAMETER_ARGUMENTS)<=set(selected),'source parameterized case omitted')
        shared.save(folder/'selection.json',dict(identifiers=selected,count=len(selected),allowed_skips=definition['allowed_skips'][runtime]),exclusive=True)
        verify(root)
        execution=min(time.time()+budgets['execution_per_runtime'],cleanup_limit-budgets['cleanup_per_runtime']-30)
        require(time.time()<execution,'no execution budget remains')
        result['execution_deadline']=execution
        require(not os.path.lexists(folder/'result.xcresult'),'result bundle already exists before execution')
        shared.save(folder/'execution-admission.json',dict(at=time.time(),deadline=execution,selection=shared.sha(folder/'selection.json'),
                    result_bundle=str(folder/'result.xcresult')),exclusive=True)
        result['scenario']='INCOMPLETE'
        try:call(base+['-resultBundlePath',str(folder/'result.xcresult'),'-collect-test-diagnostics','never'],'execute',execution)
        except Exception as error:result['execution_failure']=str(error)
        collect_results(folder,execution,call)
        summary=json.loads((folder/'result-summary.log').read_text());tree=json.loads((folder/'result-tests.log').read_text())
        cases,invocations=original.result_inventory(tree);original.result_environment(summary,tree,expected,invocations)
        require(sorted(cases)==selected,'executed case inventory mismatch');result.update(evidence='PASS',scenario='FAIL')
        result.update(original.assess(selected,tree,summary,definition['allowed_skips'][runtime]))
        require('execution_failure' not in result and time.time()<execution,'nonzero or late XCTest command/assertions')
        result['scenario']='PASS'
    except Exception as error:result['failure']=type(error).__name__+': '+str(error)
    finally:
        cleanup=min(cleanup_limit,time.time()+budgets['cleanup_per_runtime']);result['cleanup_deadline']=cleanup
        try:
            ensure_quiescent(workers,folder,cleanup-30)
            if owned:call(['xcrun','simctl','shutdown',spec['device']],'shutdown',cleanup-30)
            call(['xcrun','simctl','list','devices','available','--json'],'restored',cleanup-30)
            state=json.loads((folder/'restored.log').read_text())
            actual=[d['state'] for ds in state['devices'].values() for d in ds if d['udid']==spec['device']]
            require(original_state is not None and actual==[original_state],'original simulator state not restored')
            verify(root);require(time.time()<cleanup,'late restoration proof');result['cleanup']='PASS'
        except Exception as error:result.update(cleanup='INVALID',cleanup_failure=str(error))
        if all(result[k]=='PASS' for k in ['scenario','evidence','cleanup']):result['overall']='PASS'
        result['finished_at']=time.time();result['artifacts']=original.inventory(folder)
        shared.save(folder/'summary.json',result,exclusive=True)
        print(json.dumps({k:v for k,v in result.items() if k not in ['artifacts','parameter_multiplicities']}),flush=True)
    return result['overall']=='PASS'


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['prepare','stage','27.0','17.5','verify'])
    parser.add_argument('--root',type=Path,required=True);args=parser.parse_args();root=args.root.resolve()
    if args.action=='prepare':prepare(root)
    elif args.action=='stage':stage(root)
    elif args.action=='verify':verify(root)
    else:raise SystemExit(0 if run(root,args.action) else 1)
