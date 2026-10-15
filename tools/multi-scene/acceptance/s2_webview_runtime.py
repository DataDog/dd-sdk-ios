"""Host-side WebView boundaries; pure checks, no UI input implementation."""
import hashlib
import json
import math
import uuid
from acceptance_common import require, unique


def sha(raw): return hashlib.sha256(raw).hexdigest()

def active_display(raw, device):
    info=raw.get('info',{});args=info.get('arguments',[])
    require(info.get('outcome')=='success' and info.get('commandType')=='devicectl.device.info.displays'
            and '--device' in args and args[args.index('--device')+1]==device,'foreign/failed actual display command')
    displays=raw.get('result',{}).get('displays',[])
    require(displays and len({d.get('uniqueId') for d in displays})==len(displays),'incomplete display inventory')
    display=unique([d for d in displays if d.get('active') is True],'actual active display')
    require(display.get('backlightState')=='activeOn','display off')
    require(isinstance(display.get('uniqueId'),str) and str(uuid.UUID(display['uniqueId'])).lower()==display['uniqueId'].lower(),'invalid display ID')
    require(type(display.get('pointScale')) in (int,float) and display['pointScale']>0,'missing display scale')
    require(isinstance(display.get('nativeSize'),list) and len(display['nativeSize'])==2
            and all(type(n) in (int,float) and math.isfinite(n) and n>0 for n in display['nativeSize']),'missing display size')
    require(display.get('currentOrientation') in ['rot0','rot90','rot180','rot270'],'missing actual orientation')
    return display


def owned_topology(row, scene, display):
    require(row.get('kind')=='topology' and row.get('controller_attached') is True,'missing attached topology')
    require(row.get('scene')==scene['scene'] and row.get('window')==scene['window']
            and row.get('navigation')==scene['navigation'] and row.get('root')==scene['root'],'native instance changed')
    inventory=row.get('inventory',[])
    require(row.get('connected_scene_count')==1 and len(inventory)==1 and inventory[0]['id']==scene['scene']
            and inventory[0]['activation']==0,'scene inventory/activation differs')
    windows=inventory[0].get('windows',[])
    require(windows and len({w.get('id') for w in windows})==len(windows),'incomplete window inventory')
    owned=unique([w for w in windows if w.get('owned') is True],'fixture-owned window')
    require(owned.get('id')==scene['window'] and owned.get('root')==scene['navigation']
            and owned.get('key') is True and owned.get('hidden') is False and owned.get('alpha',0)>0
            and owned.get('contains_fixture_controller') is True,'owned key/root/content displaced')
    screen=row.get('screen',{});scale=screen.get('scale')
    pixels=display['nativeSize'] if display['currentOrientation'] in ['rot0','rot180'] else display['nativeSize'][::-1]
    require(scale==display['pointScale'] and [screen.get('width',0)*scale,screen.get('height',0)*scale]==pixels,
            'native screen differs from actual display')
    require([owned.get('width',0)*scale,owned.get('height',0)*scale]==pixels,
            'owned window differs from actual display')
    for key in ['window_framework_bundle','controller_framework_bundle']:
        require(isinstance(row.get(key),str) and row[key].startswith('/'),'missing public defining bundle')
    for window in windows:
        require(window.get('screen')==screen.get('id'),'window belongs to another display')
        if window['id']==owned['id']:continue
        require(window.get('owned') is False and window.get('key') is False
                and window.get('contains_fixture_controller') is False
                and window.get('defining_bundle')==row['window_framework_bundle']
                and window.get('root_defining_bundle')==row['controller_framework_bundle']
                and isinstance(window.get('root'),str) and window['root']!=scene['navigation'],
                'unknown auxiliary ownership/provenance')
    start,end=row.get('capture_started_ns'),row.get('capture_finished_ns')
    require(type(start) is int and type(end) is int and 0<=end-start<1_000_000_000 and end<=row['monotonic_ns'],
            'topology capture is not timely/atomic')
    return owned


def display_signature(display):
    return {key:display.get(key) for key in ['uniqueId','displayId','nativeSize','pointScale','currentOrientation','bounds']}


def fold_receipt(request_raw, proof_raw, *, identity, device, host_run, initial_raw, before_raw, admission_raw):
    """Every proof retains this actual response; no sidebar or previous-sample substitution."""
    request=json.loads(request_raw);proof=json.loads(proof_raw);admission=json.loads(admission_raw)
    require(request.get('kind')=='human-fold' and request.get('identity')==identity,'foreign fold request')
    require(proof.get('kind')=='actual-display' and proof.get('state')=='PASS'
            and proof.get('identity')==identity and proof.get('device')==device and proof.get('host_run')==host_run
            and proof.get('request_sha256')==sha(request_raw),'fold proof binding differs')
    phase=request.get('fields',{}).get('phase')
    require(phase in ['open','closed'] and proof.get('phase')==phase,'fold phase differs')
    require(admission.get('request_sha256')==sha(request_raw) and proof.get('admission_sha256')==sha(admission_raw),
            'host deadline admission differs')
    times=[admission.get('observed_at_ms'),proof.get('capture_started_at_ms'),proof.get('captured_at_ms'),proof.get('proof_created_at_ms'),admission.get('deadline_ms')]
    require(all(type(value) is int and value>0 for value in times)
            and times[0]<=times[1]<=times[2]<=times[3]<times[4], 'stale or late actual display proof')
    require(times[2]-times[1]<=30_000, 'actual display capture exceeded budget')
    actual=proof.get('actual_response_json')
    require(isinstance(actual,str) and proof.get('actual_response_sha256')==sha(actual.encode()),'actual response digest differs')
    require(proof.get('before_response_sha256')==sha(before_raw)
            and proof.get('initial_response_sha256')==sha(initial_raw),'fold baseline binding differs')
    observed=active_display(json.loads(actual),device)
    initial=active_display(json.loads(initial_raw),device);before=active_display(json.loads(before_raw),device)
    require(observed['uniqueId']!=before['uniqueId'] and observed['nativeSize']!=before['nativeSize'],'fold had no actual display effect')
    require(observed['uniqueId']!=initial['uniqueId'] if phase=='open' else display_signature(observed)==display_signature(initial),
            'Closed did not restore initial display')
    return observed


def admit_request(request_raw, *, observed_at, phase_budget, overall_deadline):
    """Native elapsed time is a duration, never a host wall timestamp."""
    request=json.loads(request_raw);issued=request.get('issued_ns');expires=request.get('deadline_ns')
    require(type(issued) is int and type(expires) is int and 0<=issued<expires,'invalid native monotonic deadline')
    remaining=(expires-issued)/1_000_000_000
    require(0<remaining<=phase_budget and observed_at<overall_deadline,'invalid native phase budget')
    return {'request_sha256':sha(request_raw),'observed_at_ms':int(observed_at*1000),
            'deadline_ms':int(min(overall_deadline,observed_at+remaining)*1000),'native_duration_ns':expires-issued}


def consumed_response(document, request_raw, response_raw):
    request=json.loads(request_raw);response=json.loads(response_raw)
    require(response.get('id')==request['id'] and response.get('kind')==request['kind']
            and response.get('identity')==request['identity'] and response.get('state')=='PASS'
            and response.get('request_sha256')==sha(request_raw),'native response binding differs')
    issued=unique([r for r in document['records'] if r['kind']=='host-request-issued' and r.get('request_id')==request['id']],'issued native request')
    consumed=unique([r for r in document['records'] if r['kind']=='host-response-consumed' and r.get('request_id')==request['id']],'consumed native response')
    for row in [issued,consumed]:
        require(row.get('request_kind')==request['kind'] and row.get('request_sha256')==sha(request_raw)
                and row.get('issued_ns')==request['issued_ns'] and row.get('deadline_ns')==request['deadline_ns'],
                'native deadline/request changed')
    require(consumed.get('response_sha256')==sha(response_raw) and issued['sequence']<consumed['sequence']
            and request['issued_ns']<=issued['monotonic_ns']<=consumed['consumed_ns']<request['deadline_ns']
            and consumed['consumed_ns']<=consumed['monotonic_ns'],'native response consumed late or out of order')
    return consumed
