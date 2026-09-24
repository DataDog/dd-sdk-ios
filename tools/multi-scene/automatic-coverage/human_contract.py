"""Native input qualification for the human automatic-tracking collector.

These checks prove observed input, not RUM completeness or default-predicate quality.
No XCTest result is constructed. The complete mapper inventory remains separate.
"""
import hashlib
import json
import math
import uuid


def require(value,message):
    if not value:raise ValueError('automatic human input: '+message)

def one(rows,label):
    require(len(rows)==1,'missing/duplicate '+label);return rows[0]

def rectangle(value):
    require(isinstance(value,list) and len(value)==4 and all(type(n) in [int,float] and math.isfinite(n) for n in value)
            and value[2]>0 and value[3]>0,'invalid visible frame');return value

def intersects(a,b):return min(a[0]+a[2],b[0]+b[2])>max(a[0],b[0]) and min(a[1]+a[3],b[1]+b[3])>max(a[1],b[1])

def rows(raw,run):
    require(raw.endswith(b'\n'),'partially written native evidence')
    result=[json.loads(line) for line in raw.splitlines()]
    require(result and all(r.get('run_id')==run for r in result),'foreign/restored run')
    require([r.get('sequence') for r in result]==list(range(1,len(result)+1)),'incomplete native sequence')
    require(len([r for r in result if r['kind']=='launch'])==1,'missing/duplicate native launch')
    require(not any(r['kind']=='human_failure' for r in result),'native observation failed')
    operations={'human_snapshot':'snapshot','human_callback':'callback','human_appearance':'appearance',
                'human_scroll_begin':'scroll','human_scroll_end':'scroll'}
    events={r['sequence']:r for r in result if r['kind'] in operations}
    costs={}
    for row in result:
        if row['kind']!='human_observer_cost':continue
        cost=row['payload'];event=events.get(cost.get('event_sequence'))
        require(event is not None and cost['event_sequence'] not in costs,'orphan/duplicate observer timing receipt')
        require(cost.get('operation')==operations[event['kind']] and event['sequence']<row['sequence']
                and cost.get('request_id')==event['payload'].get('current_request_id',event['payload'].get('request_id')),
                'observer timing receipt not bound to native event')
        limit=100_000_000 if cost['operation']=='snapshot' else 2_000_000
        require(type(cost.get('duration_ns')) is int and 0<=cost['duration_ns']<=limit,'observer exceeded main-thread budget')
        costs[cost['event_sequence']]=row
    require(set(costs)==set(events),'missing observer timing receipt')
    return result

PROVENANCE={'UIKit':{'window':['uikit_window'],'root':['uikit_navigation','uikit_split']},
            'SwiftUI':{'window':['uikit_window','swiftui_hosting'],'root':['uikit_navigation','uikit_split','swiftui_hosting']}}


def topology(value,binding):
    require(value['app_state']==0 and value['window_alive'] is True and value['root_alive'] is True
            and value['bound_root_unchanged'] is True,'fixture not attached and active')
    require(all(value['bound_'+k]==binding[k] for k in ['window','root','scene']),'fixture binding changed')
    scenes=value['scene_inventory'];require(len(scenes)==1,'not one actual native scene')
    scene=one([s for s in scenes if s['id']==binding['scene']],'bound scene');require(scene['activation']==0,'scene not active')
    windows=scene['windows'];require(windows and len({w['id'] for w in windows})==len(windows),'incomplete window inventory')
    owned=one([w for w in windows if w.get('owned') is True],'owned window')
    require(owned['id']==binding['window'] and owned['root']==binding['root'] and owned['key'] is True
            and owned['root_attached'] is True and owned['hidden'] is False and owned['alpha']>0 and owned['level']==0,'owned key/root/content differs')
    require([w['id'] for w in windows if w['key'] is True]==[owned['id']],'foreign key window')
    require(value.get('framework') in PROVENANCE,'unknown fixture framework')
    public=value['public_bundles'];require(set(public)=={'uikit_window','uikit_navigation','uikit_split','swiftui_hosting'},'public source provenance incomplete')
    require(all(isinstance(v,str) and v and v!=value['fixture_bundle'] for v in public.values()),'public framework/fixture provenance overlaps')
    allowed=PROVENANCE[value['framework']]
    require(owned['window_bundle'] in {public[k] for k in allowed['window']}
            and owned['root_bundle'] in {public[k] for k in allowed['root']},'foreign owned window/root provenance')
    rectangle(owned['bounds']);rectangle(scene['screen_bounds']);rectangle(scene['coordinate_bounds'])
    require(type(scene['screen_scale']) in [int,float] and scene['screen_scale']>0,'missing display scale')
    require(value['fixture_bundle'] not in [value['window_framework_bundle'],value['controller_framework_bundle']],
            'fixture and framework provenance not distinct')
    for window in windows:
        if window is owned:continue
        require(window['owned'] is False and window['key'] is False,'auxiliary window displaced content')
        # Framework origin is evidence; no class-name or window-count allowance is used.
        require(window['window_bundle']==value['window_framework_bundle'] and
                (window['root']=='nil' or window['root_bundle']==value['controller_framework_bundle']),'unreviewed additional app-owned window')
    require(not any('capture_error' in row for row in value['accessibility']),'incomplete public accessibility inventory')
    return scene,owned

def snapshot(all_rows,request_bytes,run):
    request=json.loads(request_bytes)
    require(set(request)=={'schema_version','run_id','request_id','phase'} and type(request['schema_version']) is int
            and request['schema_version']==1 and request['run_id']==run,'snapshot request schema/identity differs')
    require(str(uuid.UUID(request['request_id']))==request['request_id'] and request['phase'],'invalid snapshot identity')
    binding_row=one([r for r in all_rows if r['kind']=='human_window_binding'],'source-supported fixture window binding')
    result=one([r for r in all_rows if r['kind']=='human_snapshot' and r['payload']['request_id']==request['request_id']],'snapshot')
    require(result['payload']['request_sha256']==hashlib.sha256(request_bytes).hexdigest()
            and result['payload']['phase']==request['phase'] and binding_row['sequence']<result['sequence'],'stale snapshot/phase')
    require(type(result['payload']['uptime_ns']) is int and result['payload']['uptime_ns']>0,'missing native clock')
    topology(result['payload']['topology'],binding_row['payload']);return result,binding_row['payload']

def accessibility_owner(inventory,selected,window):
    """Validate the optional, source-bound public-container inventory as one graph."""
    graph_format=any('container_ids' in row or 'container_edges' in row for row in inventory)
    if not graph_format:
        require(not any(row.get('kind')=='UIAccessibilityObject' for row in inventory),
                'generic accessibility target lacks container provenance')
        return  # Legacy fixture inventories keep their original contract.
    require(0<len(inventory)<=4096,'invalid public accessibility inventory size')
    require(all(type(row.get('id')) is str and row['id'] and row['id']!='nil' for row in inventory),
            'missing public accessibility object identity')
    ids={row['id'] for row in inventory};require(len(ids)==len(inventory),'duplicate public accessibility object')
    children={identity:set() for identity in ids};roots=[]
    allowed={'subviews','accessibilityElements','automationElements','accessibilityElementAtIndex'}
    for row in inventory:
        parents=row.get('container_ids');edges=row.get('container_edges')
        require(type(parents) is list and parents and all(type(p) is str for p in parents)
                and len(parents)==len(set(parents)), 'missing/duplicate public accessibility containers')
        require(type(edges) is list and edges and all(type(e) is str for e in edges)
                and len(edges)==len(set(edges)), 'missing/duplicate public accessibility edges')
        actual_parents=set()
        for edge in edges:
            parts=edge.rsplit(':',1);require(len(parts)==2,'malformed public accessibility edge')
            parent,kind=parts;actual_parents.add(parent)
            if kind=='owned-window':
                require(parent=='nil' and row['id']==window and row.get('kind')=='UIView',
                        'foreign public accessibility root')
                roots.append(row['id'])
            else:
                require(kind in allowed and parent in ids,'unknown public accessibility edge/parent')
                children[parent].add(row['id'])
        require(actual_parents==set(parents),'public accessibility parent/edge mismatch')
    require(roots==[window],'missing/duplicate owned public accessibility root')
    reachable=set();pending=[window]
    while pending:
        current=pending.pop()
        if current in reachable:continue
        reachable.add(current);pending.extend(children[current]-reachable)
    require(reachable==ids and selected['id'] in reachable,'disconnected public accessibility ownership')


def target(before,identifier,binding):
    value=before['payload']['topology'];_,window=topology(value,binding)
    item=one([r for r in value['accessibility'] if r.get('identifier')==identifier],'actual target '+identifier)
    accessibility_owner(value['accessibility'],item,binding['window'])
    frame=rectangle(item['frame_in_window'])
    require(item.get('hidden',False) is False and item.get('alpha',1)>0 and intersects(frame,window['bounds']),'target not visible in owned window')
    return item

def callback(all_rows,before,after,identifier,binding):
    target(before,identifier,binding);topology(after['payload']['topology'],binding)
    require(before['sequence']<after['sequence'],'post-input observation precedes readiness')
    selected=[r for r in all_rows if before['sequence']<r['sequence']<after['sequence']]
    row=one([r for r in selected if r['kind']=='human_callback'],'native callback')
    require(row['payload']['target']==identifier,'unexpected callback before target effect')
    effect=one([r for r in selected if r['kind']=='native_input'],'original native callback')
    require(effect['payload']['name']==identifier,'unexpected native input before target effect')
    require(row['payload']['request_id']==before['payload']['request_id'] and row['sequence']<effect['sequence'],'consumed/foreign callback boundary')
    topology(row['payload']['topology'],binding)
    require(before['payload']['uptime_ns']<=row['payload']['uptime_ns']<=after['payload']['uptime_ns'],'native callback clock outside readiness')
    return row

def scroll(all_rows,before,after,identifier,binding):
    item=target(before,identifier,binding);topology(after['payload']['topology'],binding)
    selected=[r for r in all_rows if before['sequence']<r['sequence']<after['sequence'] and r['kind'].startswith('human_scroll_')]
    begin=one([r for r in selected if r['kind']=='human_scroll_begin'],'scroll begin')
    end=one([r for r in selected if r['kind']=='human_scroll_end'],'scroll end')
    a,b=begin['payload'],end['payload'];request=before['payload']['request_id']
    require(begin['sequence']<end['sequence'] and a['gesture_id']==b['gesture_id'] and a['gesture_id']!='nil'
            and a['request_id']==b['request_id']==a['current_request_id']==b['current_request_id']==request,'foreign/consumed gesture')
    require(a['state']==1 and b['state']==3,'gesture did not actually begin/end')
    require(before['payload']['uptime_ns']<=a['uptime_ns']<=b['uptime_ns']<=after['payload']['uptime_ns'],'gesture outside native boundary')
    x,y=a['scroll'],b['scroll']
    require(x['id']==y['id'] and x['owned'] is True and y['owned'] is True
            and x['window']==y['window']==binding['window'] and x['scene']==y['scene']==binding['scene'],'scroll owner changed')
    require(all(z['hidden'] is False and z['alpha']>0 and z['enabled'] is True for z in [x,y]),'scroll was unavailable')
    # Public accessibility bounds tie the callback's concrete UIScrollView to this phase's control.
    require(rectangle(x['frame_in_window'])==rectangle(item['frame_in_window']),'gesture belongs to another visible scroll')
    require(len(x['offset'])==len(y['offset'])==2 and all(type(n) in [int,float] and math.isfinite(n) for n in x['offset']+y['offset'])
            and x['offset']!=y['offset'],'no actual content displacement')
    return {'begin':begin,'end':end}


def checkpoint(raw, receipt, run, request):
    """Validate the exact committed prefix; later bytes cannot replace earlier readiness."""
    require(set(receipt)=={'schema_version','run_id','request_id','sequence','success','byte_count','sha256'}
            and type(receipt['schema_version']) is int and receipt['schema_version']==1
            and receipt['run_id']==run and receipt['request_id']==request and receipt['success'] is True,
            'foreign or failed durable writer receipt')
    size=receipt['byte_count'];require(type(size) is int and 0<size<=len(raw),'incomplete durable prefix')
    prefix=raw[:size];require(hashlib.sha256(prefix).hexdigest()==receipt['sha256'],'durable native bytes changed')
    result=rows(prefix,run)
    require(type(receipt['sequence']) is int and result[-1]['sequence']==receipt['sequence'],'durable sequence differs')
    return result
