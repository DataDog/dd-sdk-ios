"""Opt-in profile binding controls only; every subprocess/device/network effect refused."""
import ast,copy,hashlib,importlib.util,json,os,sys,time,types
from pathlib import Path
from unittest.mock import patch
def blocked(event,args):
    if event in ('subprocess.Popen','os.system','os.exec','os.posix_spawn','socket.connect','socket.bind'):
        raise AssertionError('source-profile control forbids effect: '+event)
sys.addaudithook(blocked)
sys.dont_write_bytecode=True
case=sys.argv[1];ledger_ref=dict(path=sys.argv[2],sha256=sys.argv[3])
P=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('physical_activation',P/'physical_independent_activation.py')
c=importlib.util.module_from_spec(spec);sys.modules[spec.name]=c;spec.loader.exec_module(c)
def reject(call,reason):
    try:call()
    except ValueError as error:
        assert reason in str(error),(reason,str(error));return str(error)
    raise AssertionError('missing refusal')
if case=='missing-explicit-profile':
    reason=reject(c.imports,'explicit physical source selection required')
elif case=='foreign-routing':
    reason=reject(lambda:c.select(ledger_ref),'foreign physical member routing')
elif case=='member-hash-drift':
    reason=reject(lambda:c.select(ledger_ref),'changed selected source')
elif case=='foreign-preloaded-alias':
    c.select(ledger_ref)
    sys.modules['physical_runtime']=types.SimpleNamespace(__file__=str(c.M/'tools/multi-scene/interactive-transitions/physical_runtime.py'))
    reason=reject(c.imports,'foreign preloaded alias')
elif case in ('exact-main-layout','parent-child-explicit-selection'):
    c.select(ledger_ref);c.imports()
    import physical_runtime as worker,physical_local as local,physical_session as session
    import s2_hosting_workflow as shared
    import accessibility_capture as accessibility
    assert c.M==P.parents[2] and shared.REPO==c.M
    assert Path(worker.__file__)==P/'physical_independent_runtime.py'
    assert Path(local.__file__)==P/'physical_independent_local.py'
    assert Path(session.__file__)==P/'physical_independent_session.py'
    assert len(c.helper_members())==79 and c.selected_reference()==ledger_ref
    assert c.member_path(local.ORACLE)==P/'physical_independent_oracle.py'
    assert c.ref(c.member_path(local.ORACLE))['sha256']=='7d95fc93319cc8f0d46b59767b8ae135da57b4c218e380d1459d0195645209bf'
    assert Path(accessibility.__file__)==c.M/'tools/multi-scene/interactive-transitions/accessibility_capture.py'
    if case=='exact-main-layout':
        driver=types.SimpleNamespace(capture_contract=None,shared_capture=types.SimpleNamespace(oracle=None),journey=types.SimpleNamespace(h=None),human_fold=types.SimpleNamespace(h=None))
        runner=types.SimpleNamespace(canonical=c,original=types.SimpleNamespace(driver=driver,human_contract=None),backend=types.SimpleNamespace(common=types.SimpleNamespace(capture=None)))
        selected=local.activate(None,None,runner)
        assert Path(selected.__file__)==P/'physical_independent_oracle.py' and driver.capture_contract is selected
        # Current common generator interface is unchanged; its returned Swift source
        # has changed and remains uncompiled/unqualified, not a grading oracle.
        original=json.loads((c.M/'control-inputs.json').read_text())
        old=ast.parse(Path(original['accessibility_capture']['path']).read_bytes())
        new=ast.parse(Path(accessibility.__file__).read_bytes())
        for name in ['original_function','render_human']:
            a=next(n for n in old.body if isinstance(n,ast.FunctionDef) and n.name==name)
            b=next(n for n in new.body if isinstance(n,ast.FunctionDef) and n.name==name)
            assert ast.dump(a,include_attributes=False)==ast.dump(b,include_attributes=False)
        old_shared=Path(original['s2_hosting_workflow']['path']).read_text()
        assert old_shared.replace("REPO = Path('/Users/valentin.pertuisot/work/dd-sdk-ios') # Original protected workspace; helper paths remain private.","REPO = Path(__file__).resolve().parents[3]")==Path(shared.__file__).read_text()
    else:
        plan=json.loads((c.M/'control-inputs.json').read_text())['modeled_plan']
        now=time.time();plan['independent_capture']=dict(clocks=dict(native_deadline=now+2,execution_deadline=now+3,cleanup_deadline=now+4))
        admission=dict(execution_deadline=now+3,cleanup_deadline=now+4)
        root=c.M/'modeled-output';root.mkdir()
        seen=[]
        def supervise(argv,*unused):
            seen.append(argv);return 1
        with patch.object(worker,'reviewed',return_value=plan),patch.object(worker,'admit',return_value=(plan['cells'][0],admission)),patch.object(worker,'qualify',return_value=False),patch.object(session.operator,'publish'),patch.object(session.supervisor,'supervise',side_effect=supervise):
            assert session.run(types.SimpleNamespace(root=root,key=plan['cells'][0]['id']))==1
        assert len(seen)==1
        assert seen[0][2:7]==[str(P/'physical_independent_runtime.py'),'--source-selection',ledger_ref['path'],ledger_ref['sha256'],'cell']
        # Consume the same actual command-line selection in a clean cloned argv;
        # source selection cannot silently change within the originating process.
        original_argv=sys.argv[:]
        try:
            sys.argv=seen[0][2:]
            c.consume_selection_arguments()
            assert sys.argv[1]=='cell' and c.selected_reference()==ledger_ref
        finally:sys.argv=original_argv
        root.rmdir()
    reason='explicit profile selects new members and exact ledger'
else:raise AssertionError('unknown source control')
print(json.dumps(dict(control=case,state='PASS',pid=os.getpid(),pgid=os.getpgrp(),reason=reason,device_constructed=0,tool_calls=0,models='Only parent argv control uses synthetic plan/reservation and mocked grading/supervisor; no physical authority.')),flush=True)
