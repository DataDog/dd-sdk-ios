"""Finite native/browser session inventory, independent of display and cleanup proofs."""
import json
import math
from acceptance_common import require, unique
from app_journey_inventory import field, source, identifier
from hosting_contract import APP_ID, sdk_milliseconds
from s2_webview_contract import evaluate_markers, backend_projection, contains_fields, body

NATIVE_SERVICE='ios-s2-webview-native-validation'
BROWSER_SERVICE='ios-s2-webview-browser-validation'


def native_inventory(document):
    views={};starts=[];sessions=set()
    for row in document['records']:
        if not row['kind'].startswith('native-') or 'event_json' not in row:continue
        event=json.loads(row['event_json']);sessions.add(identifier(field(event,'session.id')))
        require(field(event,'application.id')==APP_ID and event.get('service')==NATIVE_SERVICE,'foreign native event')
        kind=event['type']
        if kind=='view':
            vid=identifier(event['view']['id']);version=field(event,'_dd.document_version');old=views.get(vid)
            require(type(version) is int and version>0 and (old is None or version>field(old,'_dd.document_version')),'invalid native revision')
            require(old is None or all(field(old,path)==field(event,path) for path in ['date','view.name','view.url']),'native occurrence changed')
            views[vid]=event
        else:
            require(kind=='action' and field(event,'action.type')=='application_start','unexpected native telemetry')
            starts.append(event)
    require(len(sessions)==1,'missing or changing native session')
    return views,starts,next(iter(sessions))


def acknowledge_markers(document, callbacks, rows, identity):
    """Validate actual marker rows before releasing a native wait or TTL boundary."""
    require(document.get('identity')==identity and callbacks,'foreign or empty callback exchange')
    views,_,session=native_inventory(document)
    owners={e['view']['name']:e['view']['id'] for e in views.values()}
    require(len(rows)==len(callbacks),'marker inventory not settled','PENDING')
    acknowledgements=[]
    for callback in callbacks:
        marker=callback['marker'];event=body(callback['body_json']);vid=event['view']['id']
        require(callback in document['records'] and callback['kind']=='webkit-callback'
                and callback['view_id']==vid and marker in ['M1','M2','M3','M4'],'callback is not actual native evidence')
        row=unique([row for row in rows if field(row['attributes']['custom'],'view.id')==vid],'exact browser marker')
        raw=json.dumps(row,separators=(',',':'),ensure_ascii=False);uploaded=backend_projection(raw)
        require(uploaded['source']=='browser' and uploaded['service']==BROWSER_SERVICE
                and field(uploaded,'application.id')==APP_ID and field(uploaded,'session.id')==session,'foreign browser acknowledgement')
        require(uploaded.get('context',{}).get('probe')=={'run_id':identity['run_id'],'marker':marker}
                and contains_fields(uploaded['view'],event['view']) and contains_fields(uploaded['_dd'],event['_dd']),
                'changed browser marker payload')
        wanted=owners['NativeA'] if marker=='M1' or (marker=='M3' and identity['arm']=='B') else owners.get('NativeB') if marker=='M2' else None
        container=uploaded.get('container')
        require(container is None if wanted is None else contains_fields(container,{'source':'ios','view':{'id':wanted}}),
                'wrong native container at acknowledgement','FAIL')
        import hashlib
        acknowledgements.append({'marker':marker,'view_id':vid,'event_json':raw,'event_sha256':hashlib.sha256(raw.encode()).hexdigest(),'evidence_kind':'datadog-mcp'})
    return acknowledgements


def local_session(document, identity, scene, *, mode="fold", require_backend=True):
    markers=evaluate_markers(document,{'identity':identity,'application_id':APP_ID,'browser_service':BROWSER_SERVICE,'window':scene['window'],'scene':scene['scene'],'mode':mode}, require_backend=require_backend)
    records=document['records'];views,starts,session=native_inventory(document)
    require(not any(r['kind'] in ['failure','encoding-failure','scene-disconnected','scene-background','ttid-observer-failure'] for r in records),'native continuity/persistence failure')
    require(len(views)==3 and sorted(e['view']['name'] for e in views.values())==['ApplicationLaunch','NativeA','NativeB'],'native view inventory differs')
    require(all(e['view']['is_active'] is False for e in views.values()),'native views still active')
    require(all(r.get('scene')==scene['scene'] for r in records if r['kind'].startswith('scene-')),'scene lifecycle owner changed')
    observer=unique([r for r in records if r['kind']=='ttid-observer-registered'],'TTID observer')
    enable=unique([r for r in records if r['kind']=='rum-enable'],'RUM enable')
    witness=unique([r for r in records if r['kind']=='ttid-message'],'TTID dispatch')
    require(observer['sequence']<enable['sequence']<witness['sequence'],'TTID witness registered too late')
    values={}
    require(witness['payload_type']=='TTIDMessage' and witness['vital_name']=='time_to_initial_display','wrong TTID payload')
    require(set(witness['attributes'])=={'application.id','session.id','view.id','view.name'},'TTID attributes differ')
    for name,kind in [('application.id','String'),('session.id','String'),('view.id','[String]'),('view.name','[String]')]:
        item=witness['attributes'][name];require(set(item)=={'type','value'} and item['type']==kind,'wrong typed TTID attribute')
        value=item['value']
        if kind=='[String]':require(isinstance(value,list) and len(value)==1,'ambiguous TTID owner');value=value[0]
        require(isinstance(value,str) and value,'empty TTID attribute');values[name]=value
    owner=values['view.id']
    require(values['application.id']==APP_ID and values['session.id']==session and owner in views
            and values['view.name']==views[owner]['view']['name'],'foreign TTID dispatch owner')
    identifier(witness['vital_id']);require(type(witness['duration_ns']) is int and witness['duration_ns']>0,'invalid TTID duration')
    require(all(type(witness.get(key)) in (int,float) and math.isfinite(witness[key]) for key in ['raw_date_reference_seconds','raw_date_unix_seconds','server_time_offset_seconds']),'invalid TTID date')
    require(witness['raw_date_reference_seconds']+978307200==witness['raw_date_unix_seconds'],'inconsistent raw TTID Date')
    corrected=sdk_milliseconds(witness['raw_date_reference_seconds']+witness['server_time_offset_seconds']+978307200)
    return {'state':'LOCAL_QUALIFIED','mode':mode,'identity':identity,'views':views,'starts':starts,'session_id':session,'markers':markers,
            'ttid':{'owner':owner,'id':witness['vital_id'],'duration':witness['duration_ns'],'date':corrected},
            'browser_rows':[json.loads(r['event_json']) for r in records if r['kind']=='writer-ack']}


def backend_session(rows, local, *, pending=True):
    state='PENDING' if pending else 'INVALID';native={};browser={};starts=[];vitals=[];reducers=[]
    scoped=local.get('mode')=='navigation-ttl'
    session=local['session_id'];marker_rows={field(r['attributes']['custom'],'view.id'):r for r in local['browser_rows']}
    for row in rows:
        event=row['attributes']['custom'];kind=event['type']
        require(field(event,'application.id')==APP_ID and field(event,'session.id')==session,'foreign backend identity')
        if kind=='session':require(field(event,'_dd.origin')=='reducer','unknown aggregate');reducers.append(event);continue
        if source(row)=='browser':
            vid=field(event,'view.id');require(kind=='view' and vid in marker_rows and vid not in browser,'unexpected/duplicate browser telemetry')
            expected=marker_rows[vid]
            actual_fields=backend_projection(json.dumps(row));prior_fields=backend_projection(json.dumps(expected))
            stable=['type','application.id','session.id','session.has_replay','source','service','date','view','container','context.probe','_dd.format_version','_dd.document_version']
            require((scoped or row['id']==expected['id']) and all(field(actual_fields,key)==field(prior_fields,key) for key in stable),
                    'browser event changed after acknowledged boundary')
            browser[vid]=row;continue
        require(source(row)=='ios' and event['service']==NATIVE_SERVICE,'foreign native backend event')
        vid=field(event,'view.id');require(vid in local['views'],'unknown native backend owner')
        if kind=='view':
            ver=field(event,'_dd.document_version');require(type(ver) is int and ver>0 and (vid,ver) not in native,'duplicate/invalid native revision')
            require(row['attributes']['client_time']==local['views'][vid]['date'],'native start date differs');native[vid,ver]=event
        elif kind=='action':require(field(event,'action.type')=='application_start','unexpected native action');starts.append(event)
        elif kind=='vital':
            witness=local['ttid'];require(vid==witness['owner'] and field(event,'vital.id')==witness['id']
                and (scoped or field(event,'vital.duration')==witness['duration'] and row['attributes']['client_time']==witness['date'])
                and field(event,'vital.type')=='app_launch' and field(event,'vital.name')=='time_to_initial_display'
                and field(event,'vital.app_launch_metric')=='ttid' and field(event,'view.name')==local['views'][vid]['view']['name']
                and field(event,'view.url')==local['views'][vid]['view']['url'],'TTID differs from exact dispatch witness');vitals.append(event)
        else:require(False,'unexpected backend family')
    require(set(browser)==set(marker_rows) and {vid for vid,_ in native}==set(local['views']),'view inventory incomplete',state)
    for vid,expected in local['views'].items():
        actual=max((e for (key,_),e in native.items() if key==vid),key=lambda e:field(e,'_dd.document_version'))
        for path in ['view.name','view.url','view.is_active','view.time_spent','view.action.count','view.resource.count','view.error.count','view.long_task.count']:
            require(field(actual,path)==field(expected,path),'native terminal field not settled: '+path,state)
    require(len(starts)<=len(local['starts']) and len(vitals)<=1 and len(reducers)<=1,'duplicate incidental telemetry')
    require((scoped or len(vitals)==1 and len(reducers)==1) and len(starts)==len(local['starts']),'incidental inventory incomplete',state)
    require({field(e,'action.id'):field(e,'view.id') for e in starts}=={field(e,'action.id'):field(e,'view.id') for e in local['starts']},'application-start owner differs')
    for name,wanted in ([] if scoped else [('view',len(local['views'])+len(marker_rows)),('action',len(starts)),('crash',0)]):
        count=field(reducers[0],'session.'+name+'.count')
        require(type(count) is int and 0<=count<=wanted,'unexpected aggregate '+name)
        require(count==wanted,'aggregate '+name+' not settled',state)
    return {'state':'BACKEND_QUALIFIED','raw_rows':len(rows),'native_views':len(local['views']),'browser_views':len(browser),'session_id':session,'incidental':{'vitals':len(vitals),'reducers':len(reducers)}}
