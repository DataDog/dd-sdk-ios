"""Fail-closed performance comparison; native trace export is a separate admission gate."""
import math
import statistics
import re
import uuid

class Invalid(ValueError):
    pass

def require(condition, message):
    if not condition:
        raise Invalid(message)

def number(value, name):
    require(type(value) in (int, float) and math.isfinite(value) and value >= 0, "invalid " + name)
    return value

def slope(samples):
    require(len(samples) >= 20, "missing sustained memory samples")
    times = [number(x[0], 'sample time') for x in samples]
    values = [number(x[1], 'memory') for x in samples]
    require(all(0 < b-a <= 1.5 for a,b in zip(times,times[1:])), "memory coverage gap")
    require(times[-1] - times[0] >= 19, "partial sustained memory interval")
    mean_x, mean_y = statistics.mean(times), statistics.mean(values)
    return sum((x-mean_x)*(y-mean_y) for x,y in zip(times,values)) / sum((x-mean_x)**2 for x in times)

def scenario(document, expected):
    require(set(expected) == {'run_id','nonce','source','fixture','framework','pid'}, "incomplete expected identity")
    require(type(expected['pid']) is int and expected['pid'] > 0, "invalid process identity")
    require(expected['framework'] in ['UIKit','SwiftUI'], "unknown framework")
    for name in ['run_id','nonce']:
        try: require(str(uuid.UUID(expected[name])) == expected[name], "invalid " + name)
        except (ValueError, TypeError, AttributeError): raise Invalid("invalid " + name)
    require(expected['run_id'] != expected['nonce'], "reused run nonce")
    for name,length in [('source',40),('fixture',64)]:
        require(isinstance(expected[name],str) and re.fullmatch('[0-9a-f]{'+str(length)+'}',expected[name]), "invalid " + name)
    require(document.get('schema_version') == 1, "unsupported native schema")
    require(all(document.get(k) == v for k,v in expected.items()), "source, fixture or run identity changed")
    rows = document.get('records', [])
    require(all(r.get('kind') in {'launch','admission','sample','phase-begin','phase-end','boundary','view','terminal',
                'native-appear','native-navigation','inactive','disconnected','metric-failure','topology-failure'} for r in rows), 'unknown native record kind')
    require(rows and [r.get('sequence') for r in rows] == list(range(1,len(rows)+1)), "incomplete native sequence")
    times = [number(r.get('uptime_ns'), 'native time') for r in rows]
    require(all(a <= b for a,b in zip(times,times[1:])), "native clock reversed")
    require(rows[-1].get('kind') == 'terminal' and rows[-1].get('state') == 'SCENARIO_COMPLETE'
            and sum(r.get('kind') == 'terminal' for r in rows) == 1, "native workload incomplete")
    require(not any(r['kind'] in ['inactive','disconnected','metric-failure','topology-failure'] for r in rows), "native continuity/metric failure")
    launches = [r for r in rows if r['kind'] == 'launch']
    require(len(launches) == 1 and all(launches[0].get(k)==v for k,v in expected.items()), "wrong launch identity")
    admissions = [r for r in rows if r['kind']=='admission']
    require(len(admissions)==1 and admissions[0].get('state')=='TRACE_READY'
            and all(admissions[0].get(k)==v for k,v in expected.items()), 'missing/foreign recorder admission')
    windows = [r for r in rows if r['kind']=='boundary']
    require(windows and len({(r['scene'],r['window'],r['width'],r['height'],r['screen_id'],r['screen_width'],r['screen_height'],r['scale'],r['maximum_fps']) for r in windows}) == 1, "scene/display changed")
    ready = [r for r in windows if r['step']=='ready' and r['cycle']==-1 and r['phase']=='launch']
    require(len(ready)==1 and launches[0]['uptime_ns'] < admissions[0]['uptime_ns'] < ready[0]['uptime_ns'], 'missing/late initial topology or admission')
    for r in windows:
        require(r.get('screen_count')==1 and r['width']==r['screen_width'] and r['height']==r['screen_height'], 'ambiguous or partial display')
        require(all(number(r[k],k)>0 for k in ['width','height','scale','maximum_fps']), 'empty display')
        owned = [w for w in r['windows'] if w['owned']]
        require(len(owned)==1 and owned[0]['key'] and not owned[0]['hidden'], "owned window missing")
        require(not any(w['key'] for w in r['windows'] if not w['owned']), "foreign key window")
    result = {}
    for phase,cycles,seconds in [('warmup',2,16),('active',12,96),('idle',0,30)]:
        begin = [r for r in rows if r['kind']=='phase-begin' and r['name']==phase]
        end = [r for r in rows if r['kind']=='phase-end' and r['name']==phase]
        require(len(begin)==len(end)==1, "missing/duplicate phase interval")
        require(begin[0]['phase'] == end[0]['phase'] == phase, "phase marker mislabeled")
        a,b = begin[0]['uptime_ns']/1e9,end[0]['uptime_ns']/1e9
        require(seconds-0.1 <= b-a <= seconds+0.5, "wrong phase duration")
        require(ready[0]['uptime_ns']/1e9 < a, 'initial topology late')
        bounds = [r for r in windows if r['phase']==phase and r['step']!='terminal']
        require([(r['cycle'],r['step']) for r in bounds] == [(i,str(j)) for i in range(cycles) for j in range(8)], "missing/reordered workload boundary")
        require(all(a < r['uptime_ns']/1e9 < b for r in bounds), "boundary outside phase")
        samples = [r for r in rows if r['kind']=='sample' and r['phase']==phase]
        require(len(samples)>=seconds, "partial sample coverage")
        require([r.get('sample_role') for r in samples] == ['begin']+['periodic']*(len(samples)-2)+['end'], "missing or reordered boundary samples")
        st = [r['uptime_ns']/1e9 for r in samples]
        require(all(a <= t <= b for t in st) and st[0]-a <=0.1 and b-st[-1] <=0.1, "partial sample coverage")
        require(all(0 < y-x <=1.5 for x,y in zip(st,st[1:])), "sample gap")
        require(all(r['thermal']==0 and r['low_power'] is False for r in samples), "thermal or low-power change")
        cpu = [number(r['cpu_seconds'],'CPU') for r in samples]
        require(all(x<=y for x,y in zip(cpu,cpu[1:])), "CPU time reversed")
        require(all(number(r['footprint_bytes'],'footprint')>0 for r in samples), "empty footprint")
        result[phase] = {'interval':[a,b], 'cpu_cores': (cpu[-1]-cpu[0])/(st[-1]-st[0]), 'samples':samples}
    require(result['warmup']['interval'][1] <= result['active']['interval'][0] < result['active']['interval'][1] <= result['idle']['interval'][0], "phase order changed")
    all_cpu = [number(r.get('cpu_seconds'),'CPU') for r in rows if r['kind']=='sample']
    require(all(x<=y for x,y in zip(all_cpu,all_cpu[1:])), "CPU time reversed between phases")
    view_ids = {r.get('id') for r in rows if r['kind']=='view' and r['phase']=='active'}
    require(None not in view_ids and len(view_ids)>=24, "RUM not exercised throughout workload")
    return result

def compare_pair(baseline, candidate):
    """Numbers are usable only after the native trace adapter validates raw evidence."""
    fields=['fps','hitch_ratio','max_hitch_seconds','max_hang_seconds','cpu_cores','idle_memory_bytes','idle_slope_bytes_per_second']
    for item in [baseline,candidate]:
        for name in fields:
            if name == 'idle_slope_bytes_per_second':
                require(type(item.get(name)) in (int,float) and math.isfinite(item[name]), 'invalid memory slope')
            else: number(item.get(name),name)
        require(item['fps']>0 and item['hitch_ratio']<=1, 'invalid frame denominator')
    require(baseline['max_hang_seconds']<0.25, 'hanging baseline cannot qualify')
    checks = {
        'fps': candidate['fps'] >= baseline['fps']*0.95,
        'hitch_ratio': candidate['hitch_ratio']-baseline['hitch_ratio'] <= 0.01 + 1e-12,
        'hitch': candidate['max_hitch_seconds']<0.25,
        'hang': candidate['max_hang_seconds']<0.25,
        'cpu': candidate['cpu_cores']-baseline['cpu_cores'] <= max(baseline['cpu_cores']*0.10,0.02) + 1e-12,
        'memory': candidate['idle_memory_bytes']-baseline['idle_memory_bytes'] <= max(baseline['idle_memory_bytes']*0.10,10*1024**2),
        'memory_slope': candidate['idle_slope_bytes_per_second'] <= 0.1*1024**2,
    }
    return {'state':'PASS' if all(checks.values()) else 'FAIL','checks':checks}

def compare_abba(rows):
    require([r.get('arm') for r in rows]==['A','B','B','A'], 'wrong paired order')
    pairs=[compare_pair(rows[0],rows[1]),compare_pair(rows[3],rows[2])]
    # Across independently clean-installed repeats, reject a rising candidate-only retained footprint.
    excess=(rows[2]['idle_memory_bytes']-rows[1]['idle_memory_bytes'])-(rows[3]['idle_memory_bytes']-rows[0]['idle_memory_bytes'])
    trend=excess <= 5*1024**2
    return {'state':'PASS' if all(p['state']=='PASS' for p in pairs) and trend else 'FAIL','pairs':pairs,'repeat_memory_excess_bytes':excess,'repeat_memory_trend':trend}
