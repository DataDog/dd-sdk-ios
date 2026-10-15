"""One human-paced H16 cell using the existing capture, backend and cleanup lane."""
import json
from pathlib import Path
import re
import time
import uuid
from acceptance_common import require, unique
from app_journey_inventory import identifier
import hosting_contract
import hosting_paced_contract as oracle
import s2_hosting_workflow as shared
import s2_hosting_paced_workflow as workflow
import s2_webview_driver as transport
import s2_webview_runtime as geometry


def pending_ready(document, seen):
    rows=document['records'];ready=[r for r in rows if r['kind']=='human-ready']
    require([r['phase'] for r in ready]==oracle.PHASES[:len(ready)] and len(ready)<=4,'repeated/reordered readiness')
    require(len({r['request_id'] for r in ready})==len(ready),'reused ready identity')
    inputs=[r for r in rows if r['kind']=='human-input']
    require(not any(r['kind']=='human-input-rejected' for r in rows),'native input rejected')
    consumed={r['request_id'] for r in inputs}
    require(len(consumed)==len(inputs) and consumed<={r['request_id'] for r in ready},'foreign or reused consumed readiness')
    pending=[r for r in ready if r['request_id'] not in consumed and r['request_id'] not in seen]
    require(len(pending)<=1,'multiple live controls')
    if not pending:return None
    row=pending[0];index=oracle.PHASES.index(row['phase']);identifier(row['request_id'])
    before=[r for r in rows if r['sequence']<row['sequence']]
    require([r['name'] for r in before if r['kind']=='swiftui-appear']==hosting_contract.NAMES[:index+1]
            and [r['name'] for r in before if r['kind']=='swiftui-disappear']==hosting_contract.NAMES[:index], 'readiness precedes lifecycle')
    boundary=unique([r for r in before if r['kind']=='boundary' and r['phase']==hosting_contract.PHASES[index]],'ready owner boundary')
    require(row['control']=='hosting.'+row['phase'] and row['controller']==boundary['controller']
            and boundary['controller_attached'] is True,'readiness owner detached or foreign')
    scene=unique([r for r in before if r['kind']=='scene-connected'],'source-owned scene')
    inventory=boundary['inventory'];require(len(inventory)==1 and inventory[0]['id']==scene['scene']
        and inventory[0]['activation']==0,'ready scene inactive or foreign')
    windows=inventory[0]['windows'];owned=unique([w for w in windows if w['owned']],'source-owned window')
    require(owned['id']==row['window']==scene['window'] and owned['key'] is True and owned['hidden'] is False
        and owned['alpha']>0 and owned['root']==scene['navigation'] and owned['root_is_navigation'] is True
        and all(w['id']==owned['id'] or (w['key'] is False and not w['contains_fixture_controller']) for w in windows),
        'ready window lost key/root/content ownership')
    require(type(row['issued_ns']) is int and type(row['deadline_ns']) is int
            and row['issued_ns']<=row['monotonic_ns']<row['deadline_ns']
            and 0<row['deadline_ns']-row['issued_ns']<=180_000_000_000,'invalid native step deadline')
    return row


def preserve_ready(documents, out, identity, device, initial, ready, native_deadline):
    folder=out/'input'/ready['phase'];folder.mkdir()
    raw=(documents/'evidence.json').read_bytes();document=json.loads(raw)
    require(document['identity']==identity and ready in document['records'],'readiness changed before capture')
    (folder/'before-evidence.json').write_bytes(raw)
    # Host clocks are used only for host work. Native input enforces its original uptime deadline.
    deadline=min(native_deadline,time.time()+180)
    shared.save(folder/'admission.json',{'deadline':deadline,'request_id':ready['request_id'],
        'ready_sequence':ready['sequence'],'native_deadline_ns':ready['deadline_ns'],'identity':identity},exclusive=True)
    actual=transport.display(device,folder,'display',deadline)
    active=geometry.active_display(json.loads(actual),device)
    require(geometry.display_signature(active)==geometry.display_signature(geometry.active_display(json.loads(initial),device)), 'hosting display changed')
    shared.command(['xcrun','devicectl','device','capture','screenshot','--device',device,'--display-unique-id',active['uniqueId'],
        '--destination',str(folder/'ready.png')],folder,'screenshot',deadline=min(deadline,time.time()+30))
    after_raw=(documents/'evidence.json').read_bytes();after=json.loads(after_raw);(folder/'after-evidence.json').write_bytes(after_raw)
    require(after['identity']==identity and ready in after['records'],'ready observation replaced')
    consumed=any(r['kind']=='human-input' and r['request_id']==ready['request_id'] for r in after['records'])
    require(time.time()<deadline,'readiness capture late')
    shared.save(folder/'receipt.json',{'state':'CAPTURED','identity':identity,'request_id':ready['request_id'],
        'native_ready_sequence':ready['sequence'],'before_sha256':shared.sha(folder/'before-evidence.json'),
        'after_sha256':shared.sha(folder/'after-evidence.json'),'screenshot_sha256':shared.sha(folder/'ready.png'),
        'already_consumed':consumed,'finished_at':time.time(),'deadline':deadline},exclusive=True)
    if not consumed:
        require(not (documents/'terminal.json').exists() and pending_ready(after,set())==ready,'control no longer ready after capture')
        print(json.dumps({'human_input':{'kind':'hosting','phase':ready['phase'],'request_id':ready['request_id'],
            'title':ready['title'],'screenshot':str(folder/'ready.png'),'device':device,'deadline':deadline,
            'instruction':'Tap '+ready['title']+' once in the selected S2 Hosting app; the next prompt follows observed lifecycle readiness.'}}),flush=True)


def terminal_document(raw, terminal, identity):
    require(terminal.get('state')=='PASS' and terminal.get('identity')==identity,'invalid native terminal')
    document=json.loads(raw);oracle.local(document,identity);return document


def cell(args):
    root=args.root.resolve();plan=workflow.verify(root);build=workflow.verify_build(root);review=workflow.runtime_binding.reviewed(root)
    admission=shared.read(root/'native-admission.json')
    require(args.arm=='B' and admission['state']=='ADMITTED' and admission['cells']==['B-manual']
            and admission['plan_sha256']==shared.sha(root/'plan.json') and admission['build_sha256']==shared.sha(root/'build-result.json')
            and admission['runtime_review_sha256']==review,'paced native run not admitted')
    fixture_review=shared.read(root/'paced-fixture-review.json')
    require(fixture_review['state']=='PASS' and fixture_review['reviewer']=='/root/c06_runtime_plan'
            and fixture_review['plan_sha256']==shared.sha(root/'plan.json')
            and fixture_review['controls_sha256']==shared.sha(root/'paced-controls.json'),'fixture review missing/stale')
    require(all(shared.sha(shared.REPO/name)==value for name,value in fixture_review['source_sha256'].items()),'reviewed fixture changed')
    out=root/'cells/B-manual';require(not out.exists(),'paced cell already consumed')
    device=shared.devices(args.device);original=shared.apps(args.device);require(shared.BUNDLE not in original and shared.absent(args.device),'task app initially present')
    out.mkdir(parents=True);(out/'input').mkdir();transport.publication_preflight(out)
    identity={'run_id':str(uuid.uuid4()),'nonce':str(uuid.uuid4()),'arm':'B','mode':'manual','source':plan['source'],'fixture':plan['fixture']}
    budget=plan['contract']['budgets_seconds'];started=time.time();native_deadline=started+budget['native']
    execution_deadline=native_deadline+budget['backend'];cleanup_deadline=execution_deadline+budget['cleanup']
    summary={'state':'RUNNING','scenario':'UNQUALIFIED','evidence':'INCOMPLETE','cleanup':'NOT_RUN','identity':identity,'device':device,
             'started_at':started,'native_deadline':native_deadline,'execution_deadline':execution_deadline,'cleanup_deadline':cleanup_deadline,
             'plan_sha256':shared.sha(root/'plan.json'),'build_sha256':shared.sha(root/'build-result.json'),
             'runtime_binding_sha256':shared.sha(root/'runtime-binding.json')}
    shared.save(out/'summary.json',summary);shared.save(out/'initial-apps.json',original,exclusive=True)
    documents=None;pid=None;initial=None;terminal=None;final_raw=None
    try:
        initial=transport.display(args.device,out,'initial-displays',native_deadline)
        empty=shared.request(out,identity,'@application.id:'+hosting_contract.APP_ID+' @context.probe.run_id:'+identity['run_id']+'-preflight',
                             'now-15m',min(native_deadline,time.time()+120),'preflight')
        require(not empty,'preflight returned stale data')
        shared.command(['xcrun','simctl','install',args.device,build['app']],out,'install',deadline=min(native_deadline,time.time()+60))
        installed=Path(shared.capture(['xcrun','simctl','get_app_container',args.device,shared.BUNDLE,'app']).stdout.decode().strip())
        require(shared.product(installed)==build['product'],'installed product differs')
        documents=Path(shared.capture(['xcrun','simctl','get_app_container',args.device,shared.BUNDLE,'data']).stdout.decode().strip())/'Documents'
        require(not documents.exists() or not list(documents.iterdir()),'stale native evidence')
        shared.save(out/'native-publication-preflight.json',transport.publication_preflight(documents),exclusive=True)
        shared.command(['xcrun','simctl','launch',args.device,shared.BUNDLE,'--run-id',identity['run_id'],'--nonce',identity['nonce'],
                        '--arm','B','--mode','manual'],out,'launch',deadline=min(native_deadline,time.time()+60))
        match=re.fullmatch(re.escape(shared.BUNDLE)+r': ([1-9][0-9]*)\s*',(out/'launch.log').read_text());require(match is not None,'missing launch PID');pid=int(match[1])
        require(Path(shared.process(pid)).resolve()==(installed/build['product']['executable']).resolve(),'wrong native process')
        seen=set()
        while not (documents/'terminal.json').exists():
            require(time.time()<native_deadline and bool(shared.process(pid)),'native timeout or process exited')
            if (documents/'evidence.json').exists():
                ready=pending_ready(transport.snapshot(documents,identity),seen)
                if ready:
                    preserve_ready(documents,out,identity,args.device,initial,ready,native_deadline);seen.add(ready['request_id'])
            time.sleep(.1)
        require(time.time()<native_deadline,'late native terminal')
        terminal=shared.read(documents/'terminal.json');final_raw=(documents/'evidence.json').read_bytes()
        shared.save(out/'native-terminal.json',terminal,exclusive=True);(out/'evidence.json').write_bytes(final_raw)
        document=terminal_document(final_raw,terminal,identity);local=oracle.local(document,identity)
        require(local['pid']==pid and set(local['human_input']['requests'])==seen,'missing pre-input collector observation')
        display=geometry.active_display(json.loads(initial),args.device)
        for boundary in [r for r in document['records'] if r['kind']=='boundary']:
            screen=boundary['screen'];require(screen['scale']==display['pointScale']
                and sorted([screen['width']*screen['scale'],screen['height']*screen['scale']])==sorted(display['nativeSize']), 'screen differs from actual display')
        shared.save(out/'local-result.json',local,exclusive=True);summary['scenario']='PASS'
        shared.collect(out,identity,local,started,min(execution_deadline,time.time()+budget['backend']));summary['evidence']='PASS'
        require(shared.product(installed)==build['product'],'installed product changed');workflow.verify(root)
        require(time.time()<execution_deadline,'late acceptance');summary['state']='PASS'
    except Exception as error:summary.update(state='INVALID',reason=str(error))
    finally:
        cleanup_started=time.time();deadline=min(cleanup_deadline,cleanup_started+budget['cleanup'])
        def recapture(raw,receipt,expected):
            require(raw==final_raw and shared.read(documents/'terminal.json')==receipt,'hosting evidence changed after terminal')
            return terminal_document(raw,receipt,expected)
        errors=transport.cleanup_cell(root,out,documents,identity,args.device,device,original,initial,pid,terminal,summary['scenario'],deadline,
            task_bundle=shared.BUNDLE,task_absent=shared.absent,verify_source=workflow.verify,recapture=recapture)
        evidence_errors=[e for e in errors if e.startswith(('terminal recapture:','preserve native evidence:'))]
        cleanup_errors=[e for e in errors if e not in evidence_errors]
        if evidence_errors:summary.update(state='INVALID',evidence='INCOMPLETE',evidence_errors=evidence_errors)
        summary['cleanup']='INVALID' if cleanup_errors else 'PASS'
        if cleanup_errors:summary['state']='INVALID'
        summary['cleanup_details']={'started_at':cleanup_started,'deadline':deadline,'finished_at':time.time(),'errors':cleanup_errors,
                                   'input_workers':'NONE; human control only; synchronous collector is quiescent'}
        summary['finished_at']=time.time();summary['artifacts']={str(p.relative_to(out)):shared.sha(p) for p in out.rglob('*') if p.is_file() and p!=out/'summary.json'}
        shared.save(out/'summary.json',summary)
        print(json.dumps({**{k:summary[k] for k in ['state','scenario','evidence','cleanup']},'summary':str(out/'summary.json')}),flush=True)
    return 0 if summary['state']=='PASS' else 1
