"""Physical launch binding; telemetry contracts match the frozen EXP223 owner."""
import ownership_contract as common

APP_ID=common.APP_ID
SERVICE=common.SERVICE
require=common.native.require


def launch_identity(rows,identity):
    launch=common.native.one([r for r in rows if r['kind']=='launch'],'physical native launch')['payload']
    for field in ['source','fixture','tracking','framework','layout','nonce','pid','bundle']:
        require(launch[field]==identity[field],'wrong physical source-bound '+field)
    require(launch['build_sdk']=='iphoneos27.1' and launch['multiple_scenes'] is False and launch['os']==identity['os'],
            'wrong physical SDK/OS/manifest')


def inventory(rows,identity):
    launch_identity(rows,identity)
    require(rows and [r['sequence'] for r in rows]==list(range(1,len(rows)+1)) and all(r['run_id']==identity['run_id'] for r in rows),
            'incomplete or foreign physical run')
    views={};order=[];accepted={};sessions=set()
    for row in rows:
        if row['kind']!='rum':continue
        event=row['payload'];family=event['type']
        require(family in ['view','action','resource','error'],'unexpected mapper family')
        require(event['application']['id']==APP_ID and event['service']==SERVICE and event['source']=='ios','foreign mapper source')
        require(event['session']['type']=='user','non-user native session');sessions.add(event['session']['id'])
        key=(family,event[family]['id'])
        if family=='view':key+=(event['_dd']['document_version'],)
        require(key not in accepted,'duplicate event/revision')
        value=dict(sequence=row['sequence'],monotonic_ns=None,event=event);accepted[key]=value
        if family!='view':continue
        view=event['view'];previous=views.get(view['id'])
        require(type(view['is_active']) is bool and type(key[2]) is int and key[2]==(previous['event']['_dd']['document_version']+1 if previous else 1),
                'missing mapper revision')
        if previous:
            require(all(previous['event'][k]==event[k] for k in ['date','session']) and
                    all(previous['event']['view'][k]==view[k] for k in ['id','name','url']),'changed occurrence identity')
        else:order.append(view['id'])
        views[view['id']]=value
    require(len(sessions)==1 and views,'missing/foreign session or empty mapped inventory')
    require(all(v['event']['view']['is_active'] is False for v in views.values()),'unclosed terminal view')
    for value in accepted.values():
        require(value['event']['view']['id'] in views,'unmapped event owner')
        require(value['event']['type'] not in ['error','resource'],'unplanned Resource/error')
    return dict(accepted=accepted,dropped={},views=views,occurrence_order=order,session_id=next(iter(sessions)))
