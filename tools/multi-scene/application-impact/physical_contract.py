"""Physical CoreDevice evidence differs from the Duo simulator schema."""
import math
from contract import require


def display(raw, device, *, require_lit=True):
    info=raw.get('info',{});args=info.get('arguments',[])
    require(info.get('outcome')=='success' and info.get('commandType')=='devicectl.device.info.displays'
            and '--device' in args and args[args.index('--device')+1]==device, 'foreign display response')
    screens=raw.get('result',{}).get('displays',[])
    require(len(screens)==1, 'physical display inventory ambiguous')
    screen=screens[0]
    require(screen.get('primary') is True and screen.get('type')=={'integrated':{}}, 'external physical display')
    require(type(screen.get('displayId')) is int and screen['displayId']>=0, 'missing physical display ID')
    require(screen.get('currentOrientation') in ['rot0','rot90','rot180','rot270'], 'missing physical orientation')
    require(type(screen.get('pointScale')) in (int,float) and math.isfinite(screen['pointScale']) and screen['pointScale']>0, 'invalid scale')
    require(isinstance(screen.get('nativeSize'),list) and len(screen['nativeSize'])==2
            and all(type(v) in (int,float) and math.isfinite(v) and v>0 for v in screen['nativeSize']), 'missing physical dimensions')
    if require_lit:require(screen.get('backlightState')=='activeOn', 'physical display not active')
    return {k:screen[k] for k in ['displayId','primary','type','nativeSize','pointScale','currentOrientation','bounds']}


def ready_admission(value, identity):
    require(set(value)=={'state',*identity} and value['state']=='TRACE_READY'
            and all(value[k]==v for k,v in identity.items()), 'foreign recorder admission')
    return True


def returned(raw, device, command):
    info=raw.get('info',{});args=info.get('arguments',[])
    require(info.get('outcome')=='success' and info.get('commandType')==command and '--device' in args
            and args[args.index('--device')+1]==device, 'foreign or failed CoreDevice response')
    return raw['result']


def app_absence(raw, device, bundle):
    value=returned(raw,device,'devicectl.device.info.apps')
    require(value.get('deviceIdentifier')==device and value.get('matchingBundleIdentifier')==bundle
            and value.get('apps')==[], 'task app still installed or incomplete inventory')
    return True
