"""Actual display and source-owned geometry for the existing automatic matrix."""
import json
import human_contract as h
import human_build  # Establish the existing acceptance helper path.
from acceptance_common import require
import s2_webview_runtime as displays


def screen(snapshot,binding,display,sdk,rows):
    scene,owned=h.topology(snapshot['payload']['topology'],binding)
    size=owned['bounds'][2:];scale=scene['screen_scale']
    pixels=display['nativeSize'] if display['currentOrientation'] in ['rot0','rot180'] else display['nativeSize'][::-1]
    reported=[n*scale for n in scene['screen_bounds'][2:]]
    full=scale==display['pointScale'] and reported==pixels and [n*scale for n in size]==pixels
    if full:return 'full_display'
    require(sdk=='26.5' and size==[375,667],'unqualified native/display geometry difference')
    # This legacy viewport was already admitted for genuine old-SDK apps. Its
    # original public trait collector stays in the unchanged observation file.
    geometry=[r for r in rows if r['kind']=='geometry' and r['sequence']<snapshot['sequence']]
    require(geometry,'missing original legacy geometry')
    scenes=geometry[-1]['payload']['scenes']
    require(len(scenes)==1 and scenes[0]['id']==binding['scene'] and scenes[0]['activation']==0,'legacy scene changed')
    matches=[w for w in scenes[0]['windows'] if [w['width'],w['height']]==size]
    require(matches and all(w['horizontal_size_class']==1 and w['vertical_size_class']==2 for w in matches),
            'legacy viewport lacks original compact public traits')
    return 'legacy_viewport'


def transition(before,after,binding,before_display,after_display,*,device,sdk,phase,before_rows,after_rows):
    require(phase in ['open','close','reopen'],'unknown fold phase')
    a=displays.active_display(json.loads(before_display),device);b=displays.active_display(json.loads(after_display),device)
    require(a['uniqueId']!=b['uniqueId'] and a['nativeSize']!=b['nativeSize'],'no actual display transition')
    require(a.get('primary') is (phase in ['open','reopen']) and b.get('primary') is (phase=='close'),
            'wrong actual fold displays')
    require(before['sequence']<after['sequence'] and before['payload']['uptime_ns']<after['payload']['uptime_ns'],
            'native fold observations stale or reordered')
    old=screen(before,binding,a,sdk,before_rows);new=screen(after,binding,b,sdk,after_rows)
    old_window=h.topology(before['payload']['topology'],binding)[1]
    new_window=h.topology(after['payload']['topology'],binding)[1]
    if old_window['bounds']==new_window['bounds']:
        require(sdk=='26.5' and old==new=='legacy_viewport','extra auxiliary windows do not establish a spatial resize')
        return 'legacy_viewport_unchanged'
    require(old==new=='full_display','unreviewed transition into or out of compatibility viewport')
    return 'resized'
