#!/usr/bin/env python3
"""Fresh, source-bound full RUM module builds and finite XCTest collection."""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import signal
import sys
import tarfile
import time
import re
from urllib.parse import urlsplit, parse_qs
import build
from contract import require

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'automatic-coverage'))
import human_processes

shared = build.shared
HERE = Path(__file__).resolve().parent
DEFINITION = shared.REPO/'DatadogRUM/MultiSceneSupport/Results/EXP-225-rum-suite-definition.json'
PROJECT = 'Datadog/Datadog.xcodeproj/project.pbxproj'
HELPERS = [Path(__file__), HERE/'build.py', HERE/'contract.py', Path(shared.__file__),
           HERE/'../acceptance/acceptance_common.py', HERE/'test_rum_suite.py', Path(human_processes.__file__)]


def inventory(root):
    result = {}
    for p in sorted(root.rglob('*')):
        if '.git' in p.relative_to(root).parts: continue
        if p.is_symlink():
            require(p.resolve().is_relative_to(root.resolve()), 'external input symlink')
            result[str(p.relative_to(root))] = {'link': os.readlink(p)}
        elif p.is_file(): result[str(p.relative_to(root))] = shared.sha(p)
    return result


def helpers(): return {str(p.resolve()): shared.sha(p) for p in HELPERS}


def package_artifact_registry(root):
    state=shared.read(root/'SourcePackages/workspace-state.json')
    result={}
    for item in state['object']['artifacts']:
        path=Path(item['path']);require(path.is_relative_to(root/'SourcePackages/artifacts') and path.exists(), 'artifact resolves outside isolated cache')
        key=item['targetName'];require(key not in result,'duplicate artifact registration')
        result[key]=str(path.relative_to(root/'SourcePackages'))
    require(result,'empty binary artifact registry')
    return result


def relocate_artifact_registry(root, prior):
    path=root/'SourcePackages/workspace-state.json';state=shared.read(path)
    shared.save(root/'package-state-before-relocation.json',state,exclusive=True)
    for item in state['object']['artifacts']:
        old=Path(item['path']);base=prior/'DerivedData/SourcePackages'
        require(old.is_relative_to(base/'artifacts'), 'unexpected cached artifact root')
        item['path']=str(root/'SourcePackages'/old.relative_to(base))
    shared.save(path,state)
    return package_artifact_registry(root)


def prepare(root):
    definition = shared.read(DEFINITION); require(shared.read(root/'definition.json') == definition, 'definition copy differs'); prior = Path(definition['previous_unit_artifact'])
    require(not (root/'workspace').exists(), 'preparation already consumed')
    protected = build.protected()
    require(protected == shared.read(root/'protected-before.json'), 'protected workspace changed')
    paths = ['Datadog', 'Datadog.xcworkspace', 'TestUtilities', 'xcconfigs', 'tools/lint', 'Makefile', 'Package.swift', 'Cartfile', 'Cartfile.resolved']
    modules = ['DatadogCore','DatadogInternal','DatadogRUM','DatadogLogs','DatadogTrace','DatadogCrashReporting',
               'DatadogWebViewTracking','DatadogSessionReplay','DatadogFlags','DatadogProfiling']
    names = shared.capture(['git','ls-tree','-r','--name-only',definition['source']]).stdout.decode().splitlines()
    for module in modules:
        for part in ['Sources','Private','Resources','Tests']:
            path = module+'/'+part
            if any(n.startswith(path+'/') for n in names): paths.append(path)
    workspace = root/'workspace'; workspace.mkdir()
    with (root/'source.tar').open('xb') as stream:
        subprocess.run(['git','archive',definition['source'],'--',*paths],cwd=shared.REPO,stdout=stream,check=True,timeout=60)
    with tarfile.open(root/'source.tar') as tar:
        require(all((m.isfile() or m.isdir()) and not m.name.startswith('/') and '..' not in Path(m.name).parts for m in tar), 'unsafe archive member')
        require(not any('Datadog.local.xcconfig' in m.name for m in tar), 'credential path in archive')
        tar.extractall(workspace,filter='data')
    # This local project input is copied, never edited or committed on the user's behalf.
    project_hash = shared.sha(shared.REPO/PROJECT)
    require(project_hash == shared.read(prior/'sources-02.json')[PROJECT], 'target membership project differs')
    shutil.copy2(shared.REPO/PROJECT,workspace/PROJECT)
    # The existing project links this declared binary dependency outside SwiftPM.
    carthage=shared.REPO/'Carthage/Build'
    require((workspace/'Cartfile.resolved').read_bytes()==(shared.REPO/'Cartfile.resolved').read_bytes(), 'Carthage pin differs from selected source')
    require(shared.read(carthage/'.OpenTelemetryApi.version')['commitish']=='2.5.0', 'cached Carthage version differs')
    require('OpenTelemetryApi.json" "2.5.0"' in (workspace/'Cartfile.resolved').read_text(), 'declared Carthage pin differs')
    require(set(re.findall(r'path = \.\./Carthage/Build/([^;]+);', (workspace/PROJECT).read_text()))=={'OpenTelemetryApi.xcframework'}, 'unqualified binary framework reference')
    (workspace/'Carthage/Build').mkdir(parents=True)
    for name in ['OpenTelemetryApi.xcframework','.OpenTelemetryApi.version']:
        shared.command(['/bin/cp','-cR',str(carthage/name),str(workspace/'Carthage/Build'/name)],root,'copy-'+name.replace('.','-'),deadline=time.time()+180)
    require(inventory(workspace/'Carthage/Build')==inventory(carthage), 'copied Carthage artifacts differ')
    shared.command(['/bin/cp','-cR',str(prior/'DerivedData/SourcePackages'),str(root/'SourcePackages')],root,'copy-dependencies',deadline=time.time()+180)
    artifact_registry=relocate_artifact_registry(root,prior)
    dependencies = inventory(root/'SourcePackages/checkouts')
    artifacts = inventory(root/'SourcePackages/artifacts')
    revisions = {p.name: shared.capture(['git','rev-parse','HEAD'],cwd=p).stdout.decode().strip() for p in (root/'SourcePackages/checkouts').iterdir()}
    prior_members = shared.read(prior/'compiler-members.json')
    expected = {Path(p).stem: sorted(str(Path(s).relative_to(shared.REPO)) for s in rows) for p,rows in prior_members.items()}
    require(len(expected['DatadogRUMTests']) == 76, 'prior complete RUM source inventory changed')
    require(all((workspace/p).is_file() for paths in expected.values() for p in paths), 'frozen source member missing')
    shared.save(root/'inputs.json',dict(definition=shared.sha(DEFINITION),source=definition['source'],archive=shared.sha(root/'source.tar'),
                workspace=inventory(workspace),project_overlay=project_hash,dependencies=dependencies,artifacts=artifacts,
                dependency_revisions=revisions,artifact_registry=artifact_registry,expected_compiler_members=expected,helpers=helpers(),protected=protected),exclusive=True)
    verify_inputs(root)
    print(json.dumps(dict(state='PREPARED',root=str(root))),flush=True)


def verify_inputs(root):
    plan = shared.read(root/'inputs.json')
    require(plan['definition'] == shared.sha(DEFINITION) and plan['helpers'] == helpers(), 'definition/helper changed')
    require(plan['protected'] == build.protected(), 'protected files changed')
    require(plan['archive'] == shared.sha(root/'source.tar'), 'source archive changed')
    current = inventory(root/'workspace')
    # Xcode may write per-user UI state; it is excluded only outside compiler/build inputs.
    current = {p:h for p,h in current.items() if '/xcuserdata/' not in p}
    expected = {p:h for p,h in plan['workspace'].items() if '/xcuserdata/' not in p}
    require(current == expected, 'workspace input changed')
    require(inventory(root/'SourcePackages/checkouts') == plan['dependencies'], 'dependency source changed')
    require(inventory(root/'SourcePackages/artifacts') == plan['artifacts'], 'dependency binary artifact changed')
    require(package_artifact_registry(root)==plan['artifact_registry'],'dependency artifact registration changed')
    for name, revision in plan['dependency_revisions'].items():
        require(shared.capture(['git','rev-parse','HEAD'],cwd=root/'SourcePackages/checkouts'/name).stdout.decode().strip() == revision, 'dependency revision changed')
    return plan


def reviewed(root):
    plan=verify_inputs(root); review=shared.read(root/'review.json')
    require(review['state']=='PASS' and review['inputs_sha256']==shared.sha(root/'inputs.json')
            and review['helpers']==helpers(), 'missing or stale scoped review')
    return plan


def command(argv, folder, name, *, deadline, cwd=None):
    started=time.time(); failure=None; process=None; quiescence=None
    cleanup_deadline=deadline+10
    log=folder/(name+'.log')
    try:
        require(started<deadline,'command after fixed deadline')
        with log.open('x') as stream:
            process=subprocess.Popen(argv,cwd=cwd,env=shared.environment(),stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
            process.wait(timeout=max(.001,deadline-time.time()))
        require(process.returncode==0 and time.time()<deadline,name+' failed or late')
    except BaseException as error:
        failure=type(error).__name__+': '+str(error)
        raise
    finally:
        cleanup_failure=None
        try:
            if process is not None:
                for sig in [signal.SIGTERM,signal.SIGKILL]:
                    if process.poll() is not None:break
                    try:os.killpg(process.pid,sig)
                    except ProcessLookupError:pass
                    try:process.wait(timeout=min(1,max(.001,cleanup_deadline-time.time())))
                    except subprocess.TimeoutExpired:pass
                quiescence=human_processes.quiesce(process.pid,cleanup_deadline)
                require(process.poll() is not None and quiescence['state']=='PASS','owned command group remains or cleanup is late')
        except Exception as error:cleanup_failure=type(error).__name__+': '+str(error)
        shared.save(folder/(name+'-receipt.json'),dict(argv=argv,started_at=started,finished_at=time.time(),deadline=deadline,
                    cleanup_deadline=cleanup_deadline,failure=failure,cleanup_failure=cleanup_failure,
                    pid=process.pid if process else None,returncode=process.returncode if process else None,quiescence=quiescence,
                    log_sha256=shared.sha(log) if log.exists() else None),exclusive=True)
        require(cleanup_failure is None,cleanup_failure)


def stage(root):
    reviewed(root)
    value=shared.read(root/'stage-admission.json')
    require(value['inputs_sha256']==shared.sha(root/'inputs.json') and value['review_sha256']==shared.sha(root/'review.json'), 'stage input/review changed')
    require(time.time()<value['execution_deadline'],'closed stage deadline')
    return value


def build_tests(root):
    require(not any((root/name).exists() for name in ['stage-admission.json','build-admission.json','built.json']), 'build attempt already consumed')
    plan = reviewed(root); definition = shared.read(DEFINITION); now=time.time()
    shared.save(root/'stage-admission.json',dict(started_at=now,execution_deadline=now+definition['budgets_seconds']['stage'],
                inputs_sha256=shared.sha(root/'inputs.json'),review_sha256=shared.sha(root/'review.json')),exclusive=True)
    deadline = min(stage(root)['execution_deadline'],time.time()+definition['budgets_seconds']['build'])
    shared.save(root/'build-admission.json',dict(at=time.time(),deadline=deadline,inputs=shared.sha(root/'inputs.json')),exclusive=True)
    command(['xcodebuild','build-for-testing','-workspace','Datadog.xcworkspace','-scheme','DatadogRUM',
                    '-destination','platform=iOS Simulator,id='+definition['environments'][0]['device'],
                    '-derivedDataPath',str(root/'DerivedData'),'-clonedSourcePackagesDirPath',str(root/'SourcePackages'),
                    '-disableAutomaticPackageResolution','-skipPackageUpdates','-onlyUsePackageVersionsFromResolvedFile','CODE_SIGNING_ALLOWED=NO',
                    'COMPILER_INDEX_STORE_ENABLE=NO'],root,'build',deadline=deadline,cwd=root/'workspace')
    lists = {}; actual = {}
    for p in (root/'DerivedData/Build/Intermediates.noindex').rglob('*.SwiftFileList'):
        require(p.parent.name == 'arm64', 'unexpected architecture')
        rows = {s:shared.sha(s) for s in shlex.split(p.read_text())}
        lists[str(p)] = dict(sha256=shared.sha(p),members=rows)
        require(p.stem not in actual, 'duplicate compiler target')
        actual[p.stem] = sorted(str(Path(s).relative_to(root/'workspace')) for s in rows)
    require(actual == plan['expected_compiler_members'], 'complete compiler membership differs')
    clang = {}
    for line in (root/'build.log').read_text().splitlines():
        if 'clang ' not in line or ' -c ' not in line or ' -o ' not in line: continue
        args=shlex.split(line); source=Path(args[args.index('-c')+1]); output=Path(args[args.index('-o')+1])
        generated=source.is_relative_to(root/'DerivedData/Build/Intermediates.noindex') and source.parent.name=='DerivedSources' and (source.name.endswith('_vers.c') or source.name=='resource_bundle_accessor.m')
        require(source.is_relative_to(root/'workspace') or source.is_relative_to(root/'SourcePackages') or generated, 'foreign C/ObjC input')
        clang[str(output)] = dict(source=str(source),sha256=shared.sha(source),object_sha256=shared.sha(output))
    require(clang, 'C/Objective-C evidence missing')
    required_private={'DatadogCore/Private/ObjcAppLaunchHandler.m','DatadogCore/Private/ObjcExceptionHandler.m','DatadogRUM/Private/DDForwardingProxyBase.m'}
    require(required_private <= {str(Path(v['source']).relative_to(root/'workspace')) for v in clang.values() if Path(v['source']).is_relative_to(root/'workspace')}, 'private C/ObjC compiler membership missing')
    test_runs=list((root/'DerivedData/Build/Products').glob('*.xctestrun'));require(len(test_runs)==1, 'ambiguous test bundle')
    settings=plistlib.loads(test_runs[0].read_bytes())
    require(set(settings)-{'__xctestrun_metadata__'} == {'DatadogRUMTests'}, 'foreign target')
    require(not settings['DatadogRUMTests'].get('OnlyTestIdentifiers') and not settings['DatadogRUMTests'].get('SkipTestIdentifiers'), 'filtered test bundle')
    require(settings['DatadogRUMTests']['TestHostPath']=='__PLATFORMS__/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest' and not settings['DatadogRUMTests'].get('IsAppHostedTestBundle') and not settings['DatadogRUMTests'].get('IsUITestBundle'), 'unexpected installed app/runner host')
    products=inventory(root/'DerivedData/Build/Products')
    shared.save(root/'built.json',dict(inputs=shared.sha(root/'inputs.json'),compiler=lists,clang=clang,products=products,
                test_run=str(test_runs[0]),configuration='Debug',architecture='arm64',completed_at=time.time()),exclusive=True)
    verify_build(root)
    require(time.time()<deadline, 'late build qualification')
    print(json.dumps(dict(state='BUILT',compiler_lists=len(lists),clang_objects=len(clang))),flush=True)


def verify_build(root):
    verify_inputs(root); built=shared.read(root/'built.json')
    require(built['inputs'] == shared.sha(root/'inputs.json'), 'build input binding changed')
    require(inventory(root/'DerivedData/Build/Products') == built['products'], 'built products changed')
    for p,v in built['compiler'].items():
        require(shared.sha(p)==v['sha256'] and {s:shared.sha(s) for s in shlex.split(Path(p).read_text())}==v['members'], 'compiler inputs changed')
    for p,v in built['clang'].items():require(shared.sha(p)==v['object_sha256'] and shared.sha(v['source'])==v['sha256'], 'C/ObjC input/object changed')
    return built


def enumerate_inventory(value):
    require(value.get('errors') == [] and len(value.get('values',[])) == 1, 'enumeration incomplete')
    target=value['values'][0]
    enabled=[v['identifier'] for v in target['enabledTests']]
    disabled=[v['identifier'] for v in target.get('disabledTests',[])]
    require(enabled and len(enabled)==len(set(enabled)) and not disabled, 'missing/duplicate/disabled test')
    require(all(v.startswith('DatadogRUMTests/') for v in enabled), 'foreign test target')
    return sorted(enabled)


PARAMETER_ARGUMENTS = {
    'DatadogRUMTests/UIKitExtensionsTests/expectedControlTypesInAlerts(numberOfActionButtons:numberOfTextFields:)': [f'{a}, {b}' for a in range(1,6) for b in range(3)],
    'DatadogRUMTests/UIKitExtensionsTests/expectedControlTypesInAlertsSwiftUI(numberOfActionButtons:numberOfTextFields:)': [f'{a}, {b}' for a in range(1,6) for b in range(3)],
    'DatadogRUMTests/UIKitExtensionsTests/expectedControlTypesInConfirmationDialogsSwiftUI(numberOfActionButtons:)': [str(a) for a in range(1,6)],
    'DatadogRUMTests/UIKitExtensionsTests/expectedControlTypesInDeprecatedActionSheetsSwiftUI(numberOfActionButtons:)': [str(a) for a in range(1,6)],
}


def result_inventory(value):
    cases={}; invocations=[]
    def walk(node, target=None):
        if node['nodeType']=='Unit test bundle':
            target=node['name'];require(target=='DatadogRUMTests','foreign result target')
        if node['nodeType']=='Test Case':
            require(target=='DatadogRUMTests','test case has no target')
            identifier=target+'/'+node['nodeIdentifier']
            require(identifier not in cases, 'duplicate case result')
            cases[identifier]=node['result']
            children=node.get('children',[])
            if children:
                require(identifier in PARAMETER_ARGUMENTS, 'unexpected parameterized case')
                require(all(c['nodeType']=='Arguments' and not c.get('children') for c in children), 'unexpected parameterized shape')
                hashes=[]
                require(sorted(c['name'] for c in children)==sorted(PARAMETER_ARGUMENTS[identifier]), 'missing or duplicate parameter argument')
                for child in children:
                    url=urlsplit(child['nodeIdentifierURL']);values=parse_qs(url.query)
                    require(url.path.endswith('/'+identifier) and set(values)=={'args'} and len(values['args'])==1
                            and re.fullmatch('[a-f0-9]{64}',values['args'][0]),'missing or foreign argument identity')
                    hashes.append(values['args'][0]);invocations.append((identifier,values['args'][0],child['result']))
                require(len(hashes)==len(set(hashes)),'duplicate parameter execution')
            else:
                require(identifier not in PARAMETER_ARGUMENTS, 'missing parameterized executions')
                invocations.append((identifier,None,node['result']))
        else:
            require(node['nodeType'] in ['Test Plan','Unit test bundle','Test Suite'], 'unknown result node')
            for child in node.get('children',[]):walk(child,target)
    for node in value['testNodes']:walk(node)
    require(cases and invocations,'empty test result')
    return cases,invocations


def assess(selected, tree, summary, allowed_skips):
    cases,invocations=result_inventory(tree)
    require(sorted(cases)==selected,'executed case inventory mismatch')
    expected={key:len(PARAMETER_ARGUMENTS.get(key,[None])) for key in selected}
    require(dict(Counter(v[0] for v in invocations))==expected,'execution multiplicity mismatch')
    skipped=sorted(k for k,v in cases.items() if v=='Skipped')
    require(skipped==allowed_skips and sorted(v[0] for v in invocations if v[2]=='Skipped')==allowed_skips, 'unexpected OS skip inventory')
    require(all(v in ['Passed','Skipped'] for v in cases.values()) and all(v[2] in ['Passed','Skipped'] for v in invocations), 'test assertion failure')
    require(summary['totalTestCount']==len(cases) and summary['passedTests']==len(cases)-len(skipped)
            and summary['skippedTests']==len(skipped) and summary['failedTests']==0 and summary['expectedFailures']==0
            and summary['result']=='Passed' and not summary.get('testFailures'), 'nonzero/unfinalized XCTest summary')
    require(not summary.get('runtimeWarnings'), 'unclassified runtime warning')
    return dict(cases=len(cases),executions=len(invocations),skipped=skipped,parameter_multiplicities=expected)


def result_environment(summary, tree, expected, invocations):
    rows=summary.get('devicesAndConfigurations',[])
    require(len(rows)==1 and rows[0]['device']==expected and tree.get('devices')==[expected], 'result runtime/device mismatch')
    config={'configurationId':'1','configurationName':'Test Scheme Action'}
    require(rows[0]['testPlanConfiguration']==config and tree.get('testPlanConfigurations')==[config], 'result test configuration mismatch')
    counts=Counter(v[2] for v in invocations)
    require(rows[0]['passedTests']==counts.get('Passed',0) and rows[0]['skippedTests']==counts.get('Skipped',0)
            and rows[0]['failedTests']==counts.get('Failed',0) and rows[0]['expectedFailures']==0, 'per-device invocation count mismatch')


def run_tests(root, runtime):
    definition=shared.read(DEFINITION); built=verify_build(root)
    spec=next(e for e in definition['environments'] if e['runtime']==runtime)
    folder=root/('runtime-'+runtime);folder.mkdir()
    result=dict(runtime=runtime,device=spec['device'],source=definition['source'],scenario='NOT_EXECUTED',evidence='INCOMPLETE',cleanup='NOT_STARTED',overall='INVALID')
    state=json.loads(shared.capture(['xcrun','simctl','list','devices','available','--json']).stdout)
    matches=[(r,d) for r,ds in state['devices'].items() for d in ds if d['udid']==spec['device']]
    require(len(matches)==1 and matches[0][0].endswith('iOS-'+runtime.replace('.','-')), 'runtime absent/changed')
    device=matches[0][1]
    require(device['name']==spec['name'] and device['deviceTypeIdentifier']==spec['device_type'] and device['isAvailable'], 'defined device model/name changed')
    runtimes=json.loads(shared.capture(['xcrun','simctl','list','runtimes','--json']).stdout)
    runtime_rows=[r for r in runtimes['runtimes'] if r['identifier']==matches[0][0] and r['isAvailable']]
    require(len(runtime_rows)==1 and runtime_rows[0]['version']==runtime,'runtime version changed')
    expected_device=dict(architecture='arm64',deviceId=spec['device'],deviceName=spec['name'],modelName=spec['result_model'],
                         osBuildNumber=runtime_rows[0]['buildversion'],osVersion=runtime,platform='iOS Simulator')
    result['original_state']=device['state'];result['expected_result_device']=expected_device
    shared.save(folder/'environment.json',dict(simctl_device=device,simctl_runtime=runtime_rows[0],expected_result_device=expected_device),exclusive=True)
    require(result['original_state']=='Shutdown','selected simulator must be initially shut down for isolated hostless cleanup')
    stage_deadline=stage(root)['execution_deadline']
    budgets=definition['budgets_seconds']
    require(time.time()+180+budgets['enumeration_per_runtime']+budgets['execution_per_runtime']+budgets['cleanup_per_runtime']<stage_deadline, 'insufficient stage budget for complete runtime reservation')
    cleanup_limit=min(stage_deadline,time.time()+180+budgets['enumeration_per_runtime']+budgets['execution_per_runtime']+budgets['cleanup_per_runtime'])
    base=['xcodebuild','test-without-building','-xctestrun',built['test_run'],'-destination','platform=iOS Simulator,id='+spec['device'],
          '-parallel-testing-enabled','NO','-enableCodeCoverage','NO']
    shared.save(folder/'admission.json',dict(**result,at=time.time(),built_sha256=shared.sha(root/'built.json'),budgets=definition['budgets_seconds'],stage_deadline=stage_deadline,cleanup_limit=cleanup_limit),exclusive=True)
    try:
        if result['original_state']=='Shutdown':
            command(['xcrun','simctl','boot',spec['device']],folder,'boot',deadline=min(stage_deadline,time.time()+60))
            command(['xcrun','simctl','bootstatus',spec['device'],'-b'],folder,'bootstatus',deadline=min(stage_deadline,time.time()+120))
        enumeration_deadline=min(stage_deadline,time.time()+definition['budgets_seconds']['enumeration_per_runtime'])
        command(base+['-enumerate-tests','-test-enumeration-style','flat','-test-enumeration-format','json',
                            '-test-enumeration-output-path',str(folder/'enumeration.json')],folder,'enumerate',deadline=enumeration_deadline)
        selected=enumerate_inventory(shared.read(folder/'enumeration.json'))
        shared.save(folder/'selection.json',dict(identifiers=selected,count=len(selected),allowed_skips=definition['allowed_skips'][runtime],
                    scope='Full DatadogRUMTests including RUM-side Replay continuity; no Session Replay test target'),exclusive=True)
        require(set(PARAMETER_ARGUMENTS)<=set(selected), 'parameterized source case omitted')
        verify_build(root)
        execution_deadline=min(stage_deadline,time.time()+definition['budgets_seconds']['execution_per_runtime'])
        result['execution_deadline']=execution_deadline
        shared.save(folder/'execution-admission.json',dict(at=time.time(),deadline=execution_deadline,selection=shared.sha(folder/'selection.json')),exclusive=True)
        result['scenario']='INCOMPLETE'
        try:
            command(base+['-resultBundlePath',str(folder/'result.xcresult'),'-collect-test-diagnostics','never'],folder,'execute',deadline=execution_deadline)
        except Exception as error: result['execution_failure']=str(error)
        for part in ['summary','tests']:
            command(['xcrun','xcresulttool','get','test-results',part,'--path',str(folder/'result.xcresult')],folder,'result-'+part,deadline=execution_deadline)
        summary=json.loads((folder/'result-summary.log').read_text());tree=json.loads((folder/'result-tests.log').read_text())
        cases,invocations=result_inventory(tree)
        result_environment(summary,tree,expected_device,invocations)
        require(sorted(cases)==selected,'executed case inventory mismatch')
        result['evidence']='PASS';result['scenario']='FAIL'
        result.update(assess(selected,tree,summary,definition['allowed_skips'][runtime]),evidence='PASS')
        require('execution_failure' not in result, 'nonzero/unfinalized XCTest command')
        result['scenario']='PASS'
        require(time.time()<execution_deadline,'late final assertions')
    except Exception as error: result['failure']=type(error).__name__+': '+str(error)
    finally:
        cleanup_deadline=min(cleanup_limit,time.time()+definition['budgets_seconds']['cleanup_per_runtime'])
        result['cleanup_deadline']=cleanup_deadline
        try:
            if result['original_state']=='Shutdown':command(['xcrun','simctl','shutdown',spec['device']],folder,'shutdown',deadline=cleanup_deadline-10)
            state=json.loads(shared.capture(['xcrun','simctl','list','devices','available','--json']).stdout)
            restored=[d['state'] for ds in state['devices'].values() for d in ds if d['udid']==spec['device']]
            require(restored==[result['original_state']],'original simulator state not restored')
            verify_build(root)
            require(time.time()<cleanup_deadline,'late cleanup verification')
            result['cleanup']='PASS'
        except Exception as error:result['cleanup']='FAILED';result['cleanup_failure']=str(error)
        if all(result[k]=='PASS' for k in ['scenario','evidence','cleanup']):result['overall']='PASS'
        result['finished_at']=time.time();result['artifacts']=inventory(folder);shared.save(folder/'summary.json',result,exclusive=True)
    print(json.dumps({k:v for k,v in result.items() if k not in ['artifacts','parameter_multiplicities']}),flush=True)
    return result['overall']=='PASS'


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['prepare','build','27.0','17.5']);parser.add_argument('--root',type=Path,required=True)
    args=parser.parse_args();root=args.root.resolve()
    if args.action=='prepare':prepare(root)
    elif args.action=='build':build_tests(root)
    else:
        if args.action=='17.5':require(shared.read(root/'runtime-27.0/summary.json')['overall']=='PASS','previous runtime did not qualify')
        raise SystemExit(0 if run_tests(root,args.action) else 1)
