"""Strict decoder preparation for Xcode trace exports; no native admission implied."""
import statistics
import json
import hashlib
import sys
from pathlib import Path
import xml.etree.ElementTree as ET
from contract import Invalid, number, require, scenario, slope
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'acceptance'))
from s2_webview_runtime import active_display, display_signature

SCHEMAS = {
    'process-info': {'time':'event-time','pid':'pid','unique-id':'uint64','process':'process','process-name':'string'},
    'os-signpost-interval': {'start':'start-time','duration':'duration','name':'signpost-name','subsystem':'subsystem',
        'process':'process','end-process':'process','start-message':'os-log-metadata','end-message':'os-log-metadata'},
    'core-animation-fps-estimate': {'interval':'start-time','period':'duration','fps':'fps'},
    'hitches-summary': {'start':'start-time','duration':'duration','hitch-id':'uint32'},
    'hitches-render-interval': {'start':'start-time','duration':'duration','process':'process','display-id':'uint32'},
    'potential-hangs': {'start':'start-time','duration':'duration','process':'process'},
}
COLUMN_TYPES=json.loads((Path(__file__).parent/'trace-schemas.json').read_text())
NS = 1_000_000_000


def xml(raw):
    require(isinstance(raw,bytes) and b'<!DOCTYPE' not in raw and b'<!ENTITY' not in raw, 'unsafe trace XML')
    try:return ET.fromstring(raw)
    except ET.ParseError as error:raise Invalid('malformed trace XML') from error


def inventory(raw):
    root=xml(raw); runs=root.findall('.//run')
    require(len(runs)==1 and runs[0].get('number')=='1', 'ambiguous trace run')
    result={}
    for name in SCHEMAS:
        matches=runs[0].findall("./data/table[@schema='"+name+"']")
        require(len(matches)==1, 'missing/ambiguous trace table '+name)
        result[name]=dict(matches[0].attrib)
    try:threshold=int(result['potential-hangs']['hangs-threshold'])
    except (KeyError,ValueError):raise Invalid('missing hang detection threshold')
    require(0<threshold<=250, 'hang instrument misses required threshold')
    return result


def decode(raw, name):
    root=xml(raw); schemas=root.findall('.//schema')
    require(len(schemas)==1 and schemas[0].get('name')==name and name in SCHEMAS, 'wrong exported schema')
    columns=[];types={}
    for col in schemas[0].findall('col'):
        mnemonic=col.findtext('mnemonic');kind=col.findtext('engineering-type')
        require(mnemonic and kind and mnemonic not in types, 'incomplete/duplicate trace column')
        columns.append(mnemonic);types[mnemonic]=kind
    require(columns==list(COLUMN_TYPES[name]) and types==COLUMN_TYPES[name], 'trace columns changed')
    require(all(types.get(k)==v for k,v in SCHEMAS[name].items()), 'required trace columns changed')
    ids={}
    for element in root.iter():
        if 'id' in element.attrib:
            key=element.attrib['id'];require(key not in ids, 'duplicate XML object identity');ids[key]=element
    def resolve(element):
        seen=set()
        while 'ref' in element.attrib:
            key=element.attrib['ref'];require(key in ids and key not in seen, 'unresolved/cyclic trace reference');seen.add(key)
            require(element.tag==ids[key].tag, 'trace reference type changed');element=ids[key]
        return element
    def text(element):
        element=resolve(element)
        if element.tag=='os-log-metadata':
            # This engineering type exports the formatted emitted log message.
            require('fmt' in element.attrib, 'missing formatted signpost message')
            return element.attrib['fmt']
        require(not list(element) and element.text is not None, 'unsupported compound trace value')
        return element.text
    def value(element,kind):
        element=resolve(element)
        if kind=='process':
            pid=element.find('pid');name=element.find('name')
            require(pid is not None and name is not None, 'missing structural process identity')
            try:pid_value=int(text(pid))
            except ValueError:raise Invalid('invalid process PID')
            require(pid_value>0, 'invalid process PID')
            return dict(pid=pid_value,name=text(name))
        if kind in ['start-time','duration','event-time','pid','uint64','uint32']:
            try:result=int(text(element))
            except ValueError:raise Invalid('invalid trace integer')
            require(result>=0,'negative trace integer');return result
        if kind=='fps':
            try:result=float(text(element))
            except ValueError:raise Invalid('invalid FPS')
            return number(result,'FPS')
        return text(element)
    rows=[]
    for row in root.findall('.//row'):
        cells=list(row);require(len(cells)==len(columns), 'partial trace row')
        require(all(cell.tag==types[key] for key,cell in zip(columns,cells) if key in SCHEMAS[name]), 'trace value type changed')
        rows.append({key:value(cell,types[key]) for key,cell in zip(columns,cells) if key in SCHEMAS[name]})
    return rows


def interval(row, start='start', duration='duration'):
    a=number(row[start],start);d=number(row[duration],duration)
    require(d>0,'empty trace interval');return a,a+d


def overlap(a,b,start,end):return max(0,min(b,end)-max(a,start))


def union_duration(intervals):
    total=0;end=None
    for a,b in sorted(intervals):
        if end is None or a>=end:total+=b-a
        elif b>end:total+=b-end
        end=max(b,end if end is not None else b)
    return total


def measure(toc, exports, document, expected, process_name, display_before, display_after, device):
    """Returns metrics only. The caller must separately qualify capture and cleanup."""
    inventory(toc)
    native=scenario(document,expected)
    before=active_display(display_before,device);after=active_display(display_after,device)
    require(len(display_before['result']['displays'])==len(display_after['result']['displays'])==1
            and display_signature(before)==display_signature(after), 'physical display changed or ambiguous')
    ready=next(r for r in document['records'] if r['kind']=='boundary' and r['step']=='ready')
    pixels=before['nativeSize'] if before['currentOrientation'] in ['rot0','rot180'] else before['nativeSize'][::-1]
    require(ready['scale']==before['pointScale'] and [ready['screen_width']*ready['scale'],ready['screen_height']*ready['scale']]==pixels,
            'physical/native display differs')
    require(set(exports)==set(SCHEMAS),'incomplete exported inventory')
    rows={name:decode(exports[name],name) for name in SCHEMAS}
    process=dict(pid=expected['pid'],name=process_name)
    lifetimes=[r for r in rows['process-info'] if r['pid']==expected['pid']]
    require(lifetimes and all(r['process']==process and r['process-name']==process_name for r in lifetimes)
            and len({r['unique-id'] for r in lifetimes})==1, 'wrong or reused process lifetime')
    signs=[r for r in rows['os-signpost-interval'] if r['subsystem']=='com.datadoghq.application-impact' and r['name']=='Workload']
    require(len(signs)==3, 'missing/extra workload signpost')
    phases={};offsets=[]
    for phase in ['warmup','active','idle']:
        message=expected['run_id']+' '+phase
        matches=[r for r in signs if r['start-message']==r['end-message']==message]
        require(len(matches)==1, 'wrong signpost run or phase')
        row=matches[0];require(row['process']==row['end-process']==process,'foreign signpost owner')
        a,b=interval(row);na,nb=native[phase]['interval']
        require(abs((b-a)/NS-(nb-na))<=0.1, 'partial signpost interval')
        offsets += [a/NS-na,b/NS-nb];phases[phase]=(a,b)
    require(max(offsets)-min(offsets)<=0.1, 'trace/native clock mapping changed')
    require(phases['warmup'][1]<=phases['active'][0]<phases['active'][1]<=phases['idle'][0], 'trace phase order changed')
    require(all(r['time']<=phases['warmup'][0] for r in lifetimes), 'late process lifetime evidence')
    start,end=phases['active'];full_start,full_end=phases['warmup'][0],phases['idle'][1]
    fps=sorted(rows['core-animation-fps-estimate'],key=lambda r:r['interval'])
    cursor=full_start;weighted=0;weight=0
    for row in fps:
        a,b=interval(row,'interval','period')
        if b<=full_start or a>=full_end:continue
        require(a<=cursor and (cursor==full_start or a==cursor), 'missing/overlapping display samples')
        require(b-a<=1.5*NS, 'stale display sample')
        cursor=min(b,full_end)
        duration=overlap(a,b,start,end);weighted+=row['fps']*duration;weight+=duration
    require(cursor==full_end and weight==end-start and weighted>0, 'partial display FPS coverage')
    render=[r for r in rows['hitches-render-interval'] if overlap(*interval(r),full_start,full_end)>0]
    require(len({r['display-id'] for r in render})<=1, 'ambiguous render display')
    # These are window-server intervals. Filtering by the app PID would erase real display work.
    hitches=[];hitch_ids=set();max_hitch=0
    for row in rows['hitches-summary']:
        a,b=interval(row)
        if overlap(a,b,start,end):
            require(row['hitch-id'] not in hitch_ids,'duplicate hitch identity');hitch_ids.add(row['hitch-id'])
            hitches.append((max(a,start),min(b,end)));max_hitch=max(max_hitch,(b-a)/NS)
    hangs=[]
    for row in rows['potential-hangs']:
        a,b=interval(row)
        if row['process']==process and overlap(a,b,start,end):hangs.append((b-a)/NS)
    idle_end=native['idle']['interval'][1]
    idle=[(r['uptime_ns']/NS,r['footprint_bytes']) for r in native['idle']['samples'] if idle_end-20<=r['uptime_ns']/NS<=idle_end]
    metrics=dict(fps=weighted/weight,hitch_ratio=union_duration(hitches)/(end-start),max_hitch_seconds=max_hitch,
                 max_hang_seconds=max(hangs,default=0),cpu_cores=native['active']['cpu_cores'],
                 idle_memory_bytes=statistics.median([r[1] for r in idle]),idle_slope_bytes_per_second=slope(idle))
    return dict(metrics=metrics,trace_phases_ns=phases,process=process,physical_display_id=before['uniqueId'],render_display_id_unjoined=render[0]['display-id'] if render else None,
                column_schema_sha256=hashlib.sha256(json.dumps(COLUMN_TYPES,separators=(',',':')).encode()).hexdigest(),
                fps_scope='display-driver estimate during app workload',hitch_scope='global display during app workload',
                native_admitted=False)
