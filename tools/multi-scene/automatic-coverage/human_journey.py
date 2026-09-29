"""Finite human input effects, separate from the unchanged RUM comparison oracle."""
import re
import human_contract as h


def flow(layout,prefix):
    h.require(layout in ['stack','split'],'unknown ordinary layout')
    root='sidebar' if layout=='split' else 'home';steps=[]
    def add(phase,target,kind,screen,after=None):
        steps.append({'phase':prefix+'.'+phase,'target':target,'kind':kind,'screen':screen,'after_screen':after or screen})
    for label,screen in [('root',root),('detail','detail')]:
        for kind in ['tap','toggle','scroll']:add(label+'.'+kind,screen+'.'+kind,kind,screen)
        if label=='root':add('navigate',root+'.next','navigate',root,'detail')
    add('present','detail.sheet','navigate','detail','sheet')
    add('sheet.tap','sheet.tap','tap','sheet')
    add('dismiss','sheet.close','navigate','sheet','detail')
    add('detail.return.tap','detail.tap','tap','detail')
    add('back','detail.back','navigate','detail',root)
    add('root.return.tap',root+'.tap','tap',root)
    return steps


def steps(layout,duo):
    result=flow(layout,'initial')
    if duo:
        result.append({'phase':'open','kind':'fold','pose':'open'})
        result+=flow(layout,'inner')
        result.append({'phase':'stable.navigate','target':('sidebar' if layout=='split' else 'home')+'.next',
                       'kind':'navigate','screen':'sidebar' if layout=='split' else 'home','after_screen':'detail'})
        for phase,pose in [('closed','close'),('reopened','reopen')]:
            result.append({'phase':pose,'kind':'fold','pose':pose})
            result.append({'phase':phase+'.detail.tap','target':'detail.tap','kind':'tap','screen':'detail','after_screen':'detail'})
    result.append({'phase':'background','kind':'home'})
    return result


def counter(snapshot,screen,binding,framework):
    control=h.target(snapshot,screen+'.receipt',binding)
    h.require(framework in ['UIKit','SwiftUI'],'unknown counter framework')
    text=control.get('text' if framework=='UIKit' else 'label')
    h.require(isinstance(text,str) and re.fullmatch(r'receipt:[0-9]+',text),'native counter missing')
    return int(text.split(':')[1])


def visible(snapshot,screen,binding):return h.target(snapshot,'screen.'+screen,binding)



def ready_controls(snapshot, screen, binding, framework):
    """Prove the whole first screen is observable before asking for any input."""
    visible(snapshot,screen,binding)
    names=['tap','toggle','scroll','receipt','next']
    controls={name:h.target(snapshot,screen+'.'+name,binding) for name in names}
    count=counter(snapshot,screen,binding,framework)
    matches=[]
    for scroll in snapshot['payload']['topology'].get('scrolls',[]):
        if not (scroll.get('owned') is True and scroll.get('window')==binding['window']
                and scroll.get('scene')==binding['scene'] and scroll.get('hidden') is False
                and scroll.get('alpha',0)>0 and scroll.get('enabled') is True):continue
        try:h.scroll_geometry.check(scroll,scroll,controls['scroll'],framework)
        except ValueError:continue
        matches.append(scroll)
    actual=h.one(matches,'owned first-screen scroll')
    return dict(identifiers=['screen.'+screen]+[screen+'.'+name for name in names],
                counter=count,scroll_id=actual['id'],snapshot_sequence=snapshot['sequence'])


def interval(rows,before,after):
    h.require(before['sequence']<after['sequence'],'input effect precedes readiness')
    return [r for r in rows if before['sequence']<r['sequence']<after['sequence']]


def effect(rows,before,after,step,binding,framework):
    """Called only with request-bound durable snapshots; never substitutes XCTest PASS."""
    h.require(framework in ['UIKit','SwiftUI'],'unknown automatic framework')
    h.require(before['payload']['phase']==step['phase']+'.before' and after['payload']['phase']==step['phase']+'.effect',
              'wrong input phase')
    visible(before,step['screen'],binding);visible(after,step['after_screen'],binding)
    selected=interval(rows,before,after)
    if step['kind']=='scroll':
        h.require(not any(r['kind'] in ['human_callback','native_input'] for r in selected),'unexpected action during scroll')
        witness=h.scroll(rows,before,after,step['target'],binding)
        if framework=='UIKit':
            drag=h.one([r for r in selected if r['kind']=='native_scroll'],'original UIKit drag effect')
            h.require(drag['payload']['screen']==step['screen'],'drag callback belongs to another screen')
        return {'kind':'scroll','begin':witness['begin']['sequence'],'end':witness['end']['sequence']}
    if framework=='SwiftUI' and step['target'].endswith('.next'):
        h.target(before,step['target'],binding)
        h.require(not any(r['kind'] in ['human_callback','native_input'] for r in selected),'unexpected action during NavigationLink')
        appearances=[r for r in selected if r['kind']=='native_appear' and r['payload']['screen']==step['after_screen']]
        appeared=h.one(appearances,'actual NavigationLink destination appearance')
        witness=h.one([r for r in selected if r['kind']=='human_appearance' and r['payload']['screen']==step['after_screen']],
                      'timed destination appearance')
        h.require(witness['payload']['request_id']==before['payload']['request_id']
                  and before['payload']['uptime_ns']<=witness['payload']['uptime_ns']<=after['payload']['uptime_ns']
                  and witness['sequence']<appeared['sequence'],'foreign or late destination appearance')
        return {'kind':'navigation','appearance':appeared['sequence']}
    callback=h.callback(rows,before,after,step['target'],binding)
    if step['kind'] in ['tap','toggle']:
        # In these unchanged sources a toggle's valueChanged/onChange callback
        # increments this counter once; callback delivery alone is insufficient.
        h.require(counter(after,step['screen'],binding,framework)==counter(before,step['screen'],binding,framework)+1,'native control did not change state exactly once')
    elif step['kind']=='navigate':
        if step['target']=='sheet.close':
            h.require(not any(r.get('identifier')=='screen.sheet' for r in after['payload']['topology']['accessibility']),
                      'dismissed sheet remains in the native inventory')
    else:h.require(False,'unknown ordinary input kind')
    return {'kind':step['kind'],'callback':callback['sequence']}
