"""Exact per-run RUM ownership and paired no-worse classification for EXP-223."""
import json
from pathlib import Path
import sys
import transition_contract as native
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'acceptance'))
from hosting_contract import APP_ID

SERVICE='ios-s2-transition-validation'


def launch_identity(rows, identity):
    launch=native.one([r for r in rows if r['kind']=='launch'],'native launch')['payload']
    for field in ['source','fixture','tracking','framework','layout','nonce','pid']:
        native.require(launch[field]==identity[field],'wrong source-bound '+field)
    native.require(launch['build_sdk']=='iphonesimulator27.1' and launch['multiple_scenes'] is False,
                   'unqualified simulator/manifest')
    native.require(launch.get('bundle')==identity['bundle'],'native task bundle differs')


def inventory(rows, identity):
    launch_identity(rows,identity)
    native.require(rows and [r['sequence'] for r in rows]==list(range(1,len(rows)+1))
                   and all(r['run_id']==identity['run_id'] for r in rows),'incomplete or foreign run')
    views={};order=[];accepted={};sessions=set()
    for row in rows:
        if row['kind']!='rum':continue
        event=row['payload'];family=event['type']
        native.require(family in ['view','action','resource','error'],'unexpected mapper family')
        native.require(event['application']['id']==APP_ID and event['service']==SERVICE
                       and event['source']=='ios','foreign mapper application/service/source')
        native.require(event['session']['type']=='user','non-user native session')
        sessions.add(event['session']['id'])
        key=(family,event[family]['id'])
        if family=='view':key+= (event['_dd']['document_version'],)
        native.require(key not in accepted,'duplicate event/revision')
        value=dict(sequence=row['sequence'],monotonic_ns=None,event=event)
        accepted[key]=value
        if family!='view':continue
        view=event['view'];previous=views.get(view['id'])
        native.require(type(view['is_active']) is bool and type(key[2]) is int
                       and key[2]==(previous['event']['_dd']['document_version']+1 if previous else 1),'missing mapper revision')
        if previous:
            native.require(all(previous['event'][k]==event[k] for k in ['date','session'])
                           and all(previous['event']['view'][k]==view[k] for k in ['id','name','url']),'changed occurrence identity')
        else:order.append(view['id'])
        views[view['id']]=value
    native.require(len(sessions)==1 and views,'missing/foreign session or empty mapped inventory')
    native.require(all(v['event']['view']['is_active'] is False for v in views.values()),'unclosed terminal view')
    for value in accepted.values():
        native.require(value['event']['view']['id'] in views,'unmapped event owner')
        native.require(value['event']['type'] not in ['error','resource'],'unplanned Resource/error in transition fixture')
    return dict(accepted=accepted,dropped={},views=views,occurrence_order=order,session_id=next(iter(sessions)))


def owners(rows,boundary):
    return [dict(id=x['event']['view']['id'],name=x['event']['view']['name'],path=x['event']['view']['url'],
                 session=x['event']['session']['id'],mapper_sequence=x['sequence'])
            for x in native.active_owner(rows,boundary)]


def transition_owners(rows,before,after,result):
    a,b=owners(rows,before),owners(rows,after)
    callback=native.callback_work(rows,result)
    completion=native.one([r for r in rows if r['kind']=='transition_complete'
                          and r['payload']['callback_id']==result['callback_id']],'bound completion')
    at_callback=owners(rows,completion)
    relation=('missing' if not a or not b else 'ambiguous' if len(a)!=1 or len(b)!=1 else
              'preserved' if a[0]['id']==b[0]['id'] else 'fresh')
    expected='preserved' if result['cancelled'] else 'fresh'
    expected_owners=a if result['cancelled'] else b
    callback_matches=len(expected_owners)==1 and callback['view']==expected_owners[0]['id'] and callback['session']==expected_owners[0]['session']
    callback_boundary_matches=(len(expected_owners)==1 and len(at_callback)==1
        and all(at_callback[0][k]==expected_owners[0][k] for k in ['id','session','name','path'])
        and type(at_callback[0]['mapper_sequence']) is int
        and 0<at_callback[0]['mapper_sequence']<completion['sequence'])
    failures=[]
    if not callback_boundary_matches:failures.append('expected occurrence was not independently mapped before callback work')
    if relation!=expected:failures.append('outgoing/return occurrence differs')
    if not callback_matches:failures.append('actual callback action has unresolved or wrong-side owner')
    # A known baseline limitation cannot be silently fixed in the oracle. Keep
    # the failed semantic expectation and a separate paired release disposition.
    return dict(before=a,after=b,callback_snapshot=at_callback,callback=callback,relation=relation,
                semantic_expectation='PASS' if not failures else 'FAIL',semantic_failures=failures,
                callback_expected_side='before' if result['cancelled'] else 'after',callback_owner_matches=callback_matches,
                callback_boundary_matches=callback_boundary_matches,expected_relation=expected,
                native_transition=result['transition_id'],callback_id=result['callback_id'])


def paired(baseline,candidate,*,tracking):
    """Compare normalized occurrence relationships, never process-specific UUIDs."""
    native.require(tracking in ['automatic','manual'],'unqualified paired tracking mode')
    native.require(set(baseline)==set(candidate)=={'pop.finish','pop.cancel','dismiss.finish','dismiss.cancel'},
                   'finite transition inventory incomplete')
    limitations=[]
    for phase in baseline:
        a,b=baseline[phase],candidate[phase]
        def signature(x):
            def owner_names(key):return [v['name'] for v in x[key]]
            callback=x['callback']['view']
            role='before' if callback in [v['id'] for v in x['before']] else 'after' if callback in [v['id'] for v in x['after']] else 'other'
            return dict(relation=x['relation'],before=owner_names('before'),after=owner_names('after'),
                        callback=role,callback_snapshot=owner_names('callback_snapshot'),semantic_expectation=x['semantic_expectation'],
                        automatic_paths={key:[v['path'] for v in x[key]] for key in ['before','after','callback_snapshot']} if tracking=='automatic' else None)
        native.require(signature(a)==signature(b),'new paired ownership or coverage difference at '+phase)
        if a['semantic_expectation']!='PASS':limitations.append(phase)
    return dict(state='PAIRED_OWNER_PATTERN_MATCH_REQUIRES_CLASSIFICATION',inherited_limitations=limitations,
                release_acceptance=False,remaining='Complete native/backend/cleanup inventory and source classification, including process-local paths and automatic limitations.')


def paired_inventory(baseline,candidate,baseline_callbacks,candidate_callbacks,*,tracking,layout="stack"):
    """Compare all unique local events and terminal counters; backend is still required."""
    native.require(tracking in ['automatic','manual'],'unqualified paired inventory mode')
    native.require(layout in ['stack','split'],'unknown paired layout')
    phases={'pop.finish','pop.cancel','dismiss.finish','dismiss.cancel'} if layout=='stack' else set()
    def project(local,callbacks):
        native.require(set(callbacks)==phases,'callback phase inventory incomplete')
        reverse={value['callback_id']:phase for phase,value in callbacks.items()}
        native.require(len(reverse)==len(phases),'aliased real callback identities')
        order=local['occurrence_order'];rank={identity:index for index,identity in enumerate(order)}
        native.require(set(rank)==set(local['views']) and len(order)==len(rank),'incomplete view order')
        views=[]
        for identity in order:
            view=local['views'][identity]['event']['view']
            counts={key:view.get(key) for key in ['action','resource','error','long_task','frustration']}
            views.append(dict(name=view['name'],path=view['url'] if tracking=='automatic' else None,counts=counts))
        events=[];seen_callbacks=[]
        for key,value in local['accepted'].items():
            event=value['event'];family=event['type']
            if family=='view':continue
            native.require(family=='action','unplanned non-view event family')
            action=event['action'];context=event.get('context',{});callback=context.get('transition_callback')
            if action['type']=='custom':
                native.require(callback in reverse and action['target']['name']=='transition.callback','unplanned custom action')
                seen_callbacks.append(callback)
            else:native.require(callback is None,'callback tagged as automatic work')
            native.require(event['view']['id'] in rank,'foreign action owner')
            events.append(dict(family=family,type=action['type'],target=action.get('target'),
                owner=rank[event['view']['id']],callback_phase=reverse.get(callback)))
        native.require(len(seen_callbacks)==len(phases) and set(seen_callbacks)==set(reverse),'missing/extra callback work')
        return dict(views=views,events=sorted(json.dumps(e,sort_keys=True) for e in events))
    a,b=project(baseline,baseline_callbacks),project(candidate,candidate_callbacks)
    native.require(a==b,'paired terminal view counters or complete event inventory differs')
    return dict(state='PAIRED_LOCAL_INVENTORY_MATCH_BACKEND_REQUIRED',view_count=len(a['views']),
                non_view_count=len(a['events']),release_acceptance=False)


def adaptive_owners(before,after):
    relation=('missing' if not before or not after else 'ambiguous' if len(before)!=1 or len(after)!=1 else
              'preserved' if before[0]['id']==after[0]['id'] else 'fresh')
    return dict(before=before,after=after,relation=relation,
                semantic_expectation='PASS' if relation=='preserved' else 'FAIL',
                remaining='Any inherited owner change requires paired source classification.')


def paired_adaptive(baseline,candidate,*,tracking):
    native.require(tracking in ['automatic','manual'],'unknown adaptive tracking')
    native.require([r['phase'] for r in baseline]==[r['phase'] for r in candidate]==['open','close','reopen'],
                   'incomplete actual adaptive sequence')
    limitations=[]
    for a,b in zip(baseline,candidate):
        def signature(record):
            value=record['ownership']
            return dict(relation=value['relation'],semantic_expectation=value['semantic_expectation'],
                owners={side:[(r['name'],r['path'] if tracking=='automatic' else None) for r in value[side]]
                        for side in ['before','after']})
        native.require(signature(a)==signature(b),'paired adaptive ownership differs at '+a['phase'])
        if a['ownership']['semantic_expectation']!='PASS':limitations.append(a['phase'])
    return dict(state='PAIRED_ADAPTIVE_OWNER_PATTERN_REQUIRES_CLASSIFICATION',
                inherited_limitations=limitations,release_acceptance=False)
