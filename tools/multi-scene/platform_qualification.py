"""One parameterized finite platform build and actual-output qualification path."""
from pathlib import Path
import platform_context as context
import platform_library as library
import copy
import ast, hashlib, json, os, plistlib, runpy, shlex, struct, subprocess, sys, time, uuid


def ref(path):
    path = Path(path)
    return {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def validate_plan(plan):
    if not __debug__:raise ValueError('qualification requires enabled checks')
    assert plan.get('native_admitted',False) is False and plan.get('gates_closed',[])==[]
    assert plan['attempt_limit'] == 1 and plan['architecture'].startswith('arm64 only')
    assert plan['compile_budget_seconds_per_command'] == 660 and plan['cleanup_seconds_per_command'] == 90
    assert plan['operational_window_cutoff'] == plan['created_at'] + 7200
    assert plan['required_frameworks'] == ['DatadogInternal', 'DatadogCore', 'DatadogRUM']
    assert plan['schemes'] == ['DatadogCore', 'DatadogRUM'] and len(plan['commands']) == 2
    profile=context.PLATFORMS[plan['platform']]
    root, cwd = Path(plan['output_root']), Path(plan['cwd'])
    for scheme, command in zip(plan['schemes'], plan['commands']):
        assert command[:2] == ['/Applications/Xcode_27.1.app/Contents/Developer/usr/bin/xcodebuild', 'build']
        for flag, value in [('-workspace', str(cwd / 'Datadog.xcworkspace')), ('-scheme', scheme),
                            ('-configuration', 'Debug'), ('-sdk', profile['sdk']), ('-destination', 'generic/platform='+profile['destination']),
                            ('-derivedDataPath', str(root / 'derived-data')), ('-resultBundlePath', str(root / (scheme + '.xcresult')))]:
            assert command.count(flag) == 1 and command[command.index(flag) + 1] == value
        assert all(x in command for x in ['CODE_SIGNING_ALLOWED=NO', 'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES',
                                         '-disableAutomaticPackageResolution', '-onlyUsePackageVersionsFromResolvedFile', '-skipPackageUpdates'])
        expected = ['/Applications/Xcode_27.1.app/Contents/Developer/usr/bin/xcodebuild', 'build', '-workspace', str(cwd / 'Datadog.xcworkspace'), '-scheme', scheme, '-configuration', 'Debug', '-sdk', profile['sdk'], '-destination', 'generic/platform='+profile['destination'], '-derivedDataPath', str(root / 'derived-data'), '-clonedSourcePackagesDirPath', plan['package_cache_root'], '-disableAutomaticPackageResolution', '-onlyUsePackageVersionsFromResolvedFile', '-skipPackageUpdates', '-resultBundlePath', str(root / (scheme + '.xcresult')), 'CODE_SIGNING_ALLOWED=NO', 'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES']
        assert command == expected, 'unexpected command or build override'
    assert plan['tests_run'] == plan['builds_run'] == plan['device_actions'] == 0
    return True


def validate_source_binding(plan, freeze):
    assert len(plan['source_head']) == 40 and plan['source_head'] == freeze['head'], 'selected source head does not match frozen source'
    return True


PARAMETER_REUSE_POLICY=dict(schema_version=1,scope='DESIGN_REVIEW_ELIGIBILITY_ONLY_NO_NATIVE_ADMISSION',
    parameters=['output_root','created_at','operational_window_cutoff','command_output_paths'],
    source_change_requires_review=True,code_change_requires_review=True,scope_change_requires_review=True,
    same_attempt_deadline_extension=False)


def parameter_identity(plan):
    validate_plan(plan)
    normalized=copy.deepcopy(plan);root=Path(plan['output_root'])
    for name in ('created_at','operational_window_cutoff','output_root'):normalized.pop(name)
    for scheme,command in zip(plan['schemes'],normalized['commands']):
        command[command.index('-derivedDataPath')+1]='<fresh-output>/derived-data'
        command[command.index('-resultBundlePath')+1]='<fresh-output>/'+scheme+'.xcresult'
    return normalized


def require_proposal_review(inputs,plan_ref,review_ref,plan,executor):
    """Reuse only a review that explicitly permits these unchanged parameters.

    This grants no command, attempt or deadline. Normal owning admission, fresh
    output, source, lane and operational reservations still apply in main.
    """
    review=inputs.json(review_ref)
    assert review['verdict']=='PASS_PLATFORM_BUILD_PROPOSAL_ONLY' and review['executor']==executor and review['controls']==plan['controls']
    assert review.get('reviewer')=='/root/rum_runtime_reviewer', 'independent designated review required'
    if review['definition']==plan_ref:return review
    assert review.get('parameter_reuse_policy')==PARAMETER_REUSE_POLICY, 'review did not approve parameter reuse'
    previous=inputs.json(review['definition'])
    assert parameter_identity(previous)==parameter_identity(plan), 'consequential plan/code/source/policy change requires review'
    old_root,new_root=Path(previous['output_root']),Path(plan['output_root'])
    assert old_root.is_absolute() and new_root.is_absolute() and old_root!=new_root and old_root.parent==new_root.parent, 'foreign or consumed output scope'
    assert new_root.resolve()==new_root and not new_root.exists(), 'fresh owned output required'
    assert plan['created_at']>=previous['created_at'], 'restored run clock'
    return review


def require_reservation(cutoff, seconds, now):
    assert now + seconds < cutoff, 'original platform reservation insufficient'


def issued_deadlines(started, budget, cleanup_budget, overall_cutoff):
    assert budget == 660 and cleanup_budget == 90
    deadline = started + budget
    cutoff = deadline + cleanup_budget
    assert cutoff <= overall_cutoff, 'child cleanup exceeds original platform cutoff'
    return started, deadline, cutoff


def process_for_cutoff(transport_raw, host):
    tree = ast.parse(transport_raw)
    fn = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'process']
    assert len(fn) == 1
    fn = fn[0]
    assert [ast.unparse(n) for n in fn.body[:3]] == ['started = time.time()', 'deadline = started + budget', 'cutoff = deadline + cleanup_budget']
    fn.name = 'platform_process'
    fn.args.args.append(ast.arg(arg='overall_cutoff'))
    fn.body[:3] = ast.parse('started, deadline, cutoff = issued_deadlines(time.time(), budget, cleanup_budget, overall_cutoff)').body
    module = ast.fix_missing_locations(ast.Module(body=[fn], type_ignores=[]))
    namespace = dict(host, issued_deadlines=issued_deadlines)
    exec(compile(module, '<reviewed transport with original lane cutoff>', 'exec'), namespace)
    return namespace['platform_process']


def product_members(helper, root, targets, platform):
    profile=context.PLATFORMS[platform]
    result=[]
    for target in targets:
        base=root/'derived-data/Build/Products'/profile['products']/(target+'.framework')
        assert base.is_dir() and not base.is_symlink()
        if not profile['versioned']:assert not any(p.is_symlink() for p in base.rglob('*')), 'unexpected flat framework symlink'
        binary,info=(base/target).resolve(),(base/('Resources/Info.plist' if profile['versioned'] else 'Info.plist')).resolve()
        assert binary.is_file() and info.is_file() and binary.is_relative_to(base.resolve()) and info.is_relative_to(base.resolve()), 'framework escaped owned output'
        metadata=plistlib.loads(info.read_bytes())
        assert metadata['CFBundleExecutable']==target and metadata['CFBundlePackageType']=='FMWK'
        assert struct.unpack('<II',binary.read_bytes()[:8])==(0xfeedfacf,0x100000c)
        result.append({'path':str(base),'executable_path':str(binary),'info_plist_path':str(info),'members':helper['members'](base)})
    return result


def own_controller_group(api=os):
    pid = api.getpid()
    if api.getpgrp() != pid:
        api.setsid()
    assert api.getpgrp() == pid, 'controller group ownership not established'
    return {'pid': pid, 'pgid': pid}


def workers(raw):
    names = {'xcodebuild', 'swift-frontend', 'clang', 'xctest', 'xctest-runner'}
    rows = [line.split(None, 2) for line in raw.decode().splitlines()[1:]]
    return [row for row in rows if len(row) == 3 and Path(row[2]).name in names]


def qualify_saved_outputs(inputs,helper,plan,outcomes,*,other_parser=None):
    """One read-only grader for native completion and later saved-output replay.

    Failures retain their phase/target. An unavailable input prevents its dependent
    assertion but does not suppress independent command, product or result checks.
    Original operational clocks are checked as saved values, never reissued.
    """
    root=Path(plan['output_root']);cwd=Path(plan['cwd']);platform=plan['platform']
    expected=inputs.json(plan['expected_source_lists']);targets=plan['required_frameworks']
    report=dict(state='INCOMPLETE',issues=[],outcomes=outcomes,source_lists=[],compiler_drivers={},other_compilations=[],
                library_context=[],products=[],results={},native_runs_added=0,gates_closed=[])
    def inspect(phase,target,fn):
        try:return fn()
        except (AssertionError,ValueError,OSError,KeyError,TypeError,IndexError,struct.error) as error:
            report['issues'].append(dict(phase=phase,target=target,detail=str(error) or type(error).__name__))
    if len(outcomes)!=len(plan['commands']):report['issues'].append(dict(phase='outcome',target=None,detail='command outcome count differs'))
    lines=[]
    for i,binding in enumerate(outcomes):
        value=inspect('outcome',i,lambda:inputs.json(binding))
        if value is None:continue
        def outcome():
            start=inputs.json(value['start'])
            assert i<len(plan['commands']) and value['command']==start['command']==plan['commands'][i], 'saved command differs'
            assert value['pid']==value['pgid']==start['pid']==start['pgid'], 'saved process group differs'
            assert value['deadline']==start['started_at']+660==start['deadline'], 'saved command clock differs'
            assert value['cleanup_cutoff']==value['deadline']+90==start['cleanup_cutoff']<=plan['operational_window_cutoff'], 'saved cleanup clock differs'
            assert value['returncode']==0 and value['exception_type'] is None, 'native command did not succeed'
            assert value['cleanup']['owned_group_absent'] and value['cleanup']['completed_at']<value['cleanup_cutoff'], 'owned build cleanup unqualified'
            return True
        inspect('outcome',i,outcome)
        raw=inspect('stdout',i,lambda:inputs.read(value['stdout']))
        if raw is not None:lines.extend(raw.decode(errors='replace').splitlines())
        inspect('stderr',i,lambda:inputs.read(value['stderr']))
    for target in targets:
        rows=inspect('source-inventory',target,lambda:helper['file_inventory'](root,cwd,{target:expected['lists'][target]}))
        if rows is not None:
            report['source_lists'].extend(rows)
            for row in rows:inspect('source-response',target,lambda:inputs.read(row['list']))
    compiler=context.scan_compilers(lines,targets,report['source_lists'],platform,read_bytes=lambda p:inputs.read(inputs.capture(Path(p))))
    report['compiler_drivers']=compiler['rows']
    report['issues'].extend(dict(phase='compiler',target=None,detail=detail) for detail in compiler['issues'])
    if other_parser is None:
        raw=inputs.read(plan['source_context_helper']);tree=ast.parse(raw)
        functions=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='other_compilation'];assert len(functions)==1
        body=ast.get_source_segment(raw.decode(),functions[0]).replace('Debug-iphonesimulator',context.PLATFORMS[platform]['products'])
        ns=dict(helper);exec(compile(body,'<parameterized other-compilation path>','exec'),ns);other_parser=ns['other_compilation']
    for target in targets:
        rows=inspect('other-inventory',target,lambda:other_parser(root,cwd,lines,{target:expected['other_sources'][target]},inputs=inputs,require_versions=True))
        if rows is not None:report['other_compilations'].extend(rows)
        rows=inspect('product',target,lambda:product_members(helper,root,[target],platform))
        if rows is not None:report['products'].extend(rows)
    linked=library.library_report(inputs,root,cwd,report['compiler_drivers'],report['source_lists'],report['other_compilations'],
                                  report['products'],lines,platform,targets)
    report['library_context']=linked['rows'];report['issues'].extend(linked['issues'])
    for scheme in plan['schemes']:
        def result():
            path=root/(scheme+'.xcresult');assert path.is_dir() and not path.is_symlink(), 'result bundle missing or redirected'
            members=helper['members'](path);assert members, 'result bundle has no saved members'
            return members
        members=inspect('result',scheme,result)
        if members is not None:report['results'][scheme]=members
    if not report['issues']:report['state']='PASS_SAVED_COMPILATION_CONTEXT_ONLY'
    return report


def replay_saved(receipt_path,receipt_hash,output):
    """Replay existing receipt bytes; no process, build, deadline or verdict rewrite."""
    saved_ref=dict(path=receipt_path,sha256=receipt_hash)
    saved=json.loads(Path(receipt_path).read_bytes());assert ref(receipt_path)==saved_ref
    plan_ref=saved['definition'];plan=json.loads(Path(plan_ref['path']).read_bytes());assert ref(plan_ref['path'])==plan_ref
    raw=Path(plan['transport']['path']).read_bytes();assert ref(plan['transport']['path'])==plan['transport']
    host=dict(__name__='bound_saved_transport',__file__=plan['transport']['path']);exec(compile(raw,plan['transport']['path'],'exec'),host)
    inputs=host['Inputs']();inputs.bytes=inputs.read;inputs.read_path=lambda p:inputs.read(inputs.capture(p))
    inputs.json(saved_ref);inputs.json(plan_ref);inputs.read(plan['transport'])
    if 'platform' not in plan:
        sdks={command[command.index('-sdk')+1] for command in plan['commands']}
        profiles=[name for name,profile in context.PLATFORMS.items() if sdks=={profile['sdk']}]
        assert len(profiles)==1, 'original platform commands are ambiguous'
        plan=dict(plan,platform=profiles[0])
    def references(value):
        if isinstance(value,dict):
            if set(('path','sha256'))<=set(value):
                # Relative entries are scoped source/product members, compared
                # against the original complete inventories below.
                if Path(value['path']).is_absolute():inputs.read(value)
            else:
                for child in value.values():references(child)
        elif isinstance(value,list):
            for child in value:references(child)
    references(saved)
    for path in (Path(__file__),Path(context.__file__),Path(library.__file__)):inputs.capture(path.resolve())
    helper=dict(__name__='bound_saved_context',__file__=plan['source_context_helper']['path'])
    exec(compile(inputs.read(plan['source_context_helper']),plan['source_context_helper']['path'],'exec'),helper)
    freeze=inputs.json(plan['source_freeze']);validate_source_binding(plan,freeze)
    source=dict(__name__='bound_saved_source');exec(compile(inputs.read(plan['source_verifier']),plan['source_verifier']['path'],'exec'),source)
    source['verify'](Path(plan['cwd']),plan['source_head'],freeze)
    outcomes=saved.get('outcomes',saved.get('native_outcomes',[]))
    report=qualify_saved_outputs(inputs,helper,plan,outcomes)
    for name in ('source_lists','other_compilations','products','results'):
        if name in saved and report[name]!=saved[name]:report['issues'].append(dict(phase='original-inventory',target=name,detail='saved inventory differs from original capture'))
    if report['issues']:report['state']='INCOMPLETE'
    inputs.join();source['verify'](Path(plan['cwd']),plan['source_head'],freeze)
    report.update(original_receipt=saved_ref,definition=plan_ref,consumer=ref(Path(__file__).resolve()),created_at=time.time(),
                  scope='Read-only saved-output replay; no original verdict changes, new native run or release credit')
    host['publish'](Path(output),report,inputs.join)
    print(json.dumps(dict(state=report['state'],issues=report['issues'],receipt=ref(output),native_runs_added=0,gates_closed=[])),flush=True)
    return 0 if not report['issues'] else 1


def release_commands(plan,root,inputs,process,before,after,outcomes):
    """A failed transport may publish its outcome before raising. Retain it."""
    for i,command in enumerate(plan['commands']):
        before(i)
        try:outcome=process(i,command)
        except BaseException:
            path=root/('build-'+str(i)+'-outcome.json')
            if path.is_file() and not path.is_symlink():outcomes.append(inputs.capture(path))
            raise
        outcomes.append(outcome);after(i)


def stopped_saved_evidence(inputs,helper,plan,outcomes):
    try:return qualify_saved_outputs(inputs,helper,plan,outcomes)
    except BaseException as error:
        return dict(state='INCOMPLETE',issues=[dict(phase='saved-consumer',target=None,detail=type(error).__name__+': '+str(error))],
                    outcomes=outcomes,native_runs_added=0,gates_closed=[])


def main(plan_path, plan_hash, review_path, review_hash):
    r = Path(__file__).resolve().parent.parent
    plan_ref = {'path': plan_path, 'sha256': plan_hash}
    review_ref = {'path': review_path, 'sha256': review_hash}
    # Read each authority once; import only the exact reviewed transport definitions.
    plan_bytes = Path(plan_path).read_bytes(); assert hashlib.sha256(plan_bytes).hexdigest() == plan_hash
    plan = json.loads(plan_bytes); validate_plan(plan)
    assert plan['context_helper']==ref(Path(context.__file__)) and plan['library_helper']==ref(Path(library.__file__))
    platform=plan['platform'];profile=context.PLATFORMS[platform]
    transport = plan['transport']; transport_raw = Path(transport['path']).read_bytes()
    assert hashlib.sha256(transport_raw).hexdigest() == transport['sha256']
    host = {'__name__': 'bound_transport', '__file__': transport['path']}
    exec(compile(transport_raw, transport['path'], 'exec'), host)
    inputs = host['Inputs'](); inputs.bytes = inputs.read; inputs.read_path=lambda p:inputs.read(inputs.capture(p))
    assert inputs.read(transport) == transport_raw
    assert inputs.json(plan_ref) == plan
    executor = inputs.capture(Path(__file__).resolve())
    review=require_proposal_review(inputs,plan_ref,review_ref,plan,executor)
    inputs.json(plan['controls'])
    source_review = inputs.json(plan['platform_source_review']); assert source_review['verdict'] == 'PASS_SOURCE_REVIEW_ONLY'
    inputs.read(plan['platform_source_assessment']); inputs.read(plan['xcode_mcp_metadata'])
    inputs.read(plan['transport_review']); inputs.read(plan['transport_controls'])
    inputs.read(plan['source_context_helper_review']); inputs.read(plan['dependency_join_review']); inputs.read(plan['library_helper']); inputs.read(plan['context_helper']); inputs.json(plan['sdk_settings'])
    helper = {'__name__': 'bound_source_context', '__file__': plan['source_context_helper']['path']}
    helper_raw = inputs.read(plan['source_context_helper'])
    exec(compile(helper_raw, plan['source_context_helper']['path'], 'exec'), helper)
    source_module = {'__name__': 'source_verifier'}
    exec(compile(inputs.read(plan['source_verifier']), plan['source_verifier']['path'], 'exec'), source_module)
    freeze = inputs.json(plan['source_freeze']); validate_source_binding(plan, freeze); inputs.read(plan['source_verifier_controls'])
    expected = inputs.json(plan['expected_source_lists']); assert expected['source_freeze'] == plan['source_freeze']
    inputs.read(plan['local_pin_guard_controls'])
    adapter_raw = inputs.read(plan['dependency_join_adapter']); tree = ast.parse(adapter_raw)
    fn = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'verify_dependencies']; assert len(fn) == 1
    class PinnedGuardModules:
        def run_path(self, path):
            assert path == plan['local_pin_guard']['path']
            raw = inputs.read(plan['local_pin_guard'])
            module = {'__name__': 'bound_local_pin_guard', '__file__': path}
            exec(compile(raw, path, 'exec'), module)
            return module
    deps = {'Path': Path, 'json': json, 'runpy': PinnedGuardModules(), 'hashlib': hashlib, 'os': os}
    exec(compile(ast.Module(body=fn, type_ignores=[]), plan['dependency_join_adapter']['path'], 'exec'), deps)
    assert inputs.json(plan['cache'])['cache_root'] == plan['package_cache_root']
    cutoff = plan['operational_window_cutoff']; root = Path(plan['output_root']); cwd = Path(plan['cwd'])
    def join():
        assert time.time() < cutoff, 'original platform lane cutoff'
        inputs.join(); source_module['verify'](cwd, plan['source_head'], freeze)
        deps['verify_dependencies'](inputs, helper, plan)
    require_reservation(cutoff, plan['whole_lane_reservation'], time.time())
    platform_process = process_for_cutoff(transport_raw, host)
    join()
    assert not any(os.path.lexists(p) for p in (cwd / 'xcconfigs').glob('*.local.xcconfig')), 'ignored local build configuration requires separate disposition'
    assert not os.path.lexists(root)
    controller_identity = own_controller_group(); root.mkdir()
    os.chdir(cwd)
    env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode_27.1.app/Contents/Developer')
    assert env.get('XCODE_XCCONFIG_FILE') is None
    owner = Path(plan['owner_path']); key = plan['owner_key']
    def progress(state, **fields):
        value = json.loads(owner.read_bytes()); slot = value['platform_build_preparation'][key]
        assert slot['definition'] == plan_ref and slot['review'] == review_ref and slot['executor'] == executor
        value['platform_build_preparation'][key] = dict(slot, state=state, controller_pid=os.getpid(), controller_pgid=os.getpgrp(), **fields)
        tmp = owner.with_name(owner.name + '.' + uuid.uuid4().hex + '.tmp')
        with tmp.open('x') as f:
            f.write(json.dumps(value, indent=2) + '\n'); f.flush(); os.fsync(f.fileno())
        os.replace(tmp, owner)
        assert json.loads(owner.read_bytes())['platform_build_preparation'][key] == value['platform_build_preparation'][key]
    progress('PLATFORM_BUILD_CONTROLLER_REGISTERED_NO_COMMAND_RELEASED')
    probe = root / ('.publication-' + uuid.uuid4().hex)
    host['publish'](probe, {'probe': True}, join); probe.unlink(); host['sync_directory'](root)
    native = []
    try:
        raw = subprocess.check_output(['/bin/ps', '-axo', 'pid,pgid,comm'], timeout=10)
        assert not workers(raw)
        free = os.statvfs(root); assert free.f_bavail * free.f_frsize >= plan['minimum_free_bytes']
        preflight = host['publish'](root / 'preflight.json', {'state': 'PASS_PLATFORM_OUTPUT_BINDING_PREFLIGHT',
            'definition': plan_ref, 'review': review_ref, 'executor': executor,
            'controller_pid': os.getpid(), 'controller_pgid': os.getpgrp(), 'processes': raw.decode(),
            'free_bytes': free.f_bavail * free.f_frsize, 'created_at': time.time(), 'gates_closed': []}, join)
        inputs.json(preflight)
        def before(i):
            assert not workers(subprocess.check_output(['/bin/ps', '-axo', 'pid,pgid,comm'], timeout=10))
            join(); progress('PLATFORM_BUILD_COMMAND_READY', command_index=i, outcomes=native)
            require_reservation(cutoff, 752, time.time())
        release_commands(plan,root,inputs,lambda i,command:platform_process(root,i,command,660,90,inputs,join,env,cutoff),before,
                         lambda i:progress('PLATFORM_BUILD_COMMAND_RETURNED',command_index=i,outcomes=native),native)
        saved=qualify_saved_outputs(inputs,helper,plan,native)
        def final_join():
            join(); assert qualify_saved_outputs(inputs,helper,plan,native)==saved, 'saved output changed during publication'
        state=('PLATFORM_BUILDS_RETURNED_REQUIRE_INDEPENDENT_ACTUAL_CONTEXT_REVIEW' if not saved['issues']
               else 'PLATFORM_COMMANDS_RETURNED_SAVED_EVIDENCE_INCOMPLETE')
        receipt=host['publish'](root/'receipt.json',dict(saved,state=state,saved_context_state=saved['state'],schema_version=1,
            definition=plan_ref,review=review_ref,executor=executor,preflight=preflight,
            source_freeze=plan['source_freeze'],source_head=plan['source_head'],created_at=time.time(),tests_run=0,device_actions=0),final_join)
        progress(state,receipt=receipt,outcomes=native)
        print(json.dumps(dict(state=state,receipt=receipt,issues=saved['issues'],gates_closed=[])),flush=True)
        return 0 if not saved['issues'] else 1
    except BaseException as error:
        saved=stopped_saved_evidence(inputs,helper,plan,native)
        stop = host['publish'](root / 'build-stop.json', {'state': 'STOPPED_PLATFORM_BUILD_OR_EVIDENCE_NOT_QUALIFIED',
            'failure_type': type(error).__name__, 'definition': plan_ref, 'review': review_ref,
            'outcomes': native, 'saved_evidence':saved,'created_at': time.time(), 'gates_closed': []})
        progress('STOPPED_PLATFORM_BUILD_OR_EVIDENCE_NOT_QUALIFIED', stop=stop, outcomes=native)
        raise


if __name__ == '__main__':
    if sys.argv[1]=='replay':raise SystemExit(replay_saved(*sys.argv[2:]))
    raise SystemExit(main(*sys.argv[1:]))
