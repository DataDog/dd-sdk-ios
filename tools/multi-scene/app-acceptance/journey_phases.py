"""Pure F08 native phase assertions; no UI input or identity inferred from names alone."""
from journey_contract import one, require, field, mapper_inventory

NAMES = {'login':['LoginView'], 'list':['ServiceList','Services'], 'detail':['ServiceDetail','ServiceDetails'],
         'dashboard':['DashboardDetails'], 'account-home':['Home']}
LABELS = {'list':'List of Services', 'detail':'Service Details', 'dashboard':'Dashboard Details'}


def nodes(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():yield from nodes(child)
    elif isinstance(value, list):
        for child in value:yield from nodes(child)


def label(value):return value.get('AXLabel', value.get('label', value.get('Label','')))
def kind(value):return str(value.get('type', value.get('role', value.get('AXRole','')))).replace('AX','').replace('XCUIElementType','').lower()
def matches(tree, text, role=None):return [n for n in nodes(tree) if label(n)==text and (role is None or kind(n)==role)]



def service_list_loaded(tree, service):
    """The title also exists on errors; require the source-defined service row."""
    if not any(matches(tree, title) for title in ['Services', 'List of Services']):
        return False
    if any('Permission Required' in str(label(node)) for node in nodes(tree)):
        return False
    choices = []
    for node in nodes(tree):
        parts = str(label(node)).split(', ')
        # APMServiceListCell combines exact service name, monitor status,
        # favorite state and properties into one accessibility label.
        if not parts or parts[0] != service or not {'favorited', 'not favorited'}.intersection(parts):
            continue
        frame = node.get('frame', node.get('AXFrame', {}))
        if (node.get('enabled', True) is True and node.get('AXHidden', False) is False
                and all(type(frame.get(key)) in (int, float) for key in ['x', 'y', 'width', 'height'])
                and frame['width'] > 0 and frame['height'] > 0):
            choices.append(node)
    return len(choices) == 1


def login(tree, subdomain=False):
    default=matches(tree,'Log In with Subdomain','button')
    title=matches(tree,'Enter Subdomain','statictext')
    fields=[n for n in nodes(tree) if kind(n)=='textfield' and n.get('enabled') is True and n.get('AXValue')=='subdomain']
    if subdomain:return len(title)==1 and len(fields)==1 and not default
    return len(default)==1 and not title and not fields


def back_target(tree):
    require(login(tree, True), 'subdomain form is not ready')
    heading=one(matches(tree,'Enter Subdomain','statictext'),'subdomain heading')
    def frame(node):
        value=node.get('frame',node.get('AXFrame'))
        require(isinstance(value,dict) and all(type(value.get(k)) in (float,int) for k in ['x','y','width','height'])
                and value['width']>0 and value['height']>0, 'AX target geometry unavailable')
        return value
    h=frame(heading);choices=[]
    for value in matches(tree,'Back','button'):
        f=frame(value);cy=f['y']+f['height']/2
        if value.get('enabled',True) is True and h['x']-80<=f['x']+f['width']<=h['x']+2 and h['y']-8<=cy<=h['y']+h['height']+8:choices.append(value)
    return one(choices,'source-defined subdomain Back')


def home(tree, process=None):
    if not isinstance(tree,list) or len(tree)!=1 or kind(tree[0])!='application' or not process:return False
    root=tree[0];pid=root.get('pid');frame=root.get('frame',{})
    if type(pid)!=int or pid<=0 or process.get('pid')!=pid:return False
    if not process.get('executable','').endswith('/RuntimeRoot/System/Library/CoreServices/SpringBoard.app/SpringBoard'):return False
    if {n['pid'] for n in nodes(tree) if n.get('pid') is not None}!={pid}:return False
    if not all(type(frame.get(k)) in (int,float) for k in ['x','y','width','height']):return False
    if frame['width']<=0 or frame['height']<=0:return False
    def within(value, exact=False):
        f=value.get('frame',{})
        if not all(type(f.get(k)) in (int,float) for k in frame):return False
        if exact:return all(abs(f[k]-frame[k])<.01 for k in frame)
        return (f['width']>0 and f['height']>0 and f['x']>=frame['x'] and f['y']>=frame['y']
                and f['x']+f['width']<=frame['x']+frame['width'] and f['y']+f['height']<=frame['y']+frame['height'])
    icons=[n for n in nodes(tree) if n.get('AXUniqueId')=='Home screen icons' and n.get('enabled') is True and within(n,True)]
    pages=[n for n in nodes(tree) if n.get('AXUniqueId')=='Page control' and kind(n)=='slider' and n.get('enabled') is True and within(n)]
    return len(icons)==1 and len(pages)==1 and not matches(tree,'Log In with Subdomain','button') and not matches(tree,'Enter Subdomain','statictext')


def visible(rows, snapshot, phase, binding):
    """Tie the actual attached labelled controller to the original navigation callback."""
    require(phase in LABELS, 'unknown authenticated phase')
    topology=snapshot['fields']['topology']
    controller=one([c for c in topology['controllers'] if c.get('label')==LABELS[phase]
                    and c.get('window')==binding['window'] and c.get('scene')==binding['scene']], 'attached phase controller')
    require(not controller.get('transition'), 'native transition still active')
    if phase == 'dashboard':
        # DashboardDetailCoordinator pushes its public UIViewController wrapper;
        # the labelled DashboardDetailViewController is installed as one child.
        wrapper=one([c for c in topology['controllers'] if c['id']==controller.get('parent')], 'dashboard wrapper')
        navigation=one([c for c in topology['controllers'] if c['id']==wrapper.get('parent')], 'dashboard navigation')
        require(controller.get('class')=='DatadogApp.DashboardDetailViewController'
                and wrapper.get('class')=='UIViewController' and navigation.get('class')=='UINavigationController',
                'source-defined dashboard containment differs')
        require(wrapper.get('children')==[controller['id']]
                and navigation.get('children',[])[-1:]==[wrapper['id']], 'dashboard containment is not reciprocal or topmost')
        for node in [controller,wrapper,navigation]:
            require(node.get('window')==binding['window'] and node.get('scene')==binding['scene']
                    and not node.get('transition') and node.get('presented')=='nil', 'dashboard native owner unsettled')
        callbacks=[r for r in rows if r['sequence']<snapshot['sequence'] and r['kind']=='navigation_callback'
                   and r['fields'].get('navigation')==navigation['id']]
        require(callbacks and callbacks[-1]['fields']['callback']=='didShow-exit', 'dashboard navigation has not finished')
        latest=callbacks[-1];fields=latest['fields'];shown=fields['controller']
        require(fields['stack']==navigation['children'] and shown['id']==wrapper['id']
                and all(shown.get(k)==wrapper.get(k) for k in ['parent','children','scene','window']),
                'latest dashboard navigation callback has a different owner')
        return dict(controller=controller['id'],navigation_controller=navigation['id'],wrapper=wrapper['id'],
                    native_callback_sequence=latest['sequence'],label=LABELS[phase])
    callbacks=[r for r in rows if r['sequence']<snapshot['sequence'] and r['kind']=='navigation_callback'
               and r['fields']['controller']['id']==controller['id']]
    require(callbacks and callbacks[-1]['fields']['callback']=='didShow-exit'
            and callbacks[-1]['fields']['stack'][-1]==controller['id'], 'original navigation delegate did not finish on phase controller')
    return dict(controller=controller['id'], native_callback_sequence=callbacks[-1]['sequence'], label=LABELS[phase])


def foreground_binding(rows, snapshot, previous=None, *, authenticated_transition=False):
    topology=snapshot['fields']['topology'];scenes=topology.get('scene_inventory',[])
    scene=one(scenes,'ordinary scene')
    window=one([w for w in scene['windows'] if w.get('owned') is True],'source-owned window')
    source=one([r for r in rows if r['sequence']<snapshot['sequence'] and r['kind']=='owned_window'
                and r['fields']['window']==window['id'] and r['fields']['scene']==scene['id']], 'source window installation')
    current=dict(scene=scene['id'],window=window['id'],root=window['root'],owned_labels=list(LABELS.values()))
    if previous:
        require(all(current[k]==previous[k] for k in ['scene','window']), 'owned native scene/window replaced')
        require(authenticated_transition or current['root']==previous['root'], 'root changed outside authenticated transition')
    return current


def dashboard_timeframe(ready, text):
    """Bind the unique native duration button to the source-defined dashboard."""
    topology=ready['snapshot']['fields']['topology'];binding=ready['binding'];controllers=topology['controllers']
    timer=one([c for c in controllers if c.get('class')=='DatadogApp.TimeframeViewController'
               and c.get('window')==binding['window']], 'owned dashboard timeframe controller')
    bottom=one([c for c in controllers if c['id']==timer.get('parent')], 'dashboard bottom controller')
    dashboard=one([c for c in controllers if c['id']==bottom.get('parent')], 'timeframe dashboard')
    require(bottom.get('class')=='UIViewController' and bottom.get('children')==[timer['id']]
            and dashboard['id']==ready['visible']['controller'] and dashboard.get('children')==[bottom['id']]
            and dashboard.get('class')=='DatadogApp.DashboardDetailViewController', 'foreign timeframe containment')
    require(all(c.get('scene')==binding['scene'] and c.get('window')==binding['window']
                and not c.get('transition') for c in [timer,bottom,dashboard]), 'timeframe detached or transitioning')
    tree=ready['ax'];require(isinstance(tree,list) and len(tree)==1 and kind(tree[0])=='application'
                            and tree[0].get('pid')==topology['pid'], 'foreign timeframe accessibility process')
    button=one(matches(tree,text,'button'), 'unique dashboard duration button')
    frame=button.get('frame',{});screen=tree[0].get('frame',{})
    require(button.get('pid')==topology['pid'] and button.get('enabled') is True
            and button.get('AXHidden',False) is False
            and all(type(f.get(k)) in (int,float) for f in [frame,screen] for k in ['x','y','width','height'])
            and frame['width']>0 and frame['height']>0 and frame['x']>=screen['x'] and frame['y']>=screen['y']
            and frame['x']+frame['width']<=screen['x']+screen['width']
            and frame['y']+frame['height']<=screen['y']+screen['height'], 'timeframe button hidden or outside owned display')
    return dict(controller=timer['id'],dashboard=dashboard['id'],label=text,frame=frame)


CAPTURED_LIFECYCLE_CALLBACKS = ('willResignActive', 'didEnterBackground', 'didBecomeActive')


def lifecycle(rows, start, end, scene, callback):
    names=[callback+'-enter',callback+'-exit']
    selected=[r for r in rows if start<r['sequence']<=end and r['kind']=='scene_callback'
              and r['fields']['callback'] in names]
    require([r['fields']['callback'] for r in selected]==names and all(r['fields']['scene']==scene for r in selected),
            callback + ': missing, repeated or foreign lifecycle boundary')
    return [r['sequence'] for r in selected]


def lifecycle_cycle(rows, start, end, scene):
    """Require the callback pairs emitted by the source-bound scene recorder."""
    callbacks={name:lifecycle(rows,start,end,scene,name) for name in CAPTURED_LIFECYCLE_CALLBACKS}
    ordered=[sequence for pair in callbacks.values() for sequence in pair]
    require(ordered==sorted(ordered), 'lifecycle callback order differs')
    return callbacks


def j01(rows, phases, expected, background):
    names=['login-initial','login-subdomain','login-returned','login-reactivated']
    require(all(name in phases for name in names), 'incomplete J01 phase inventory')
    owners=[phases[name]['owner']['view_id'] for name in names]
    require(len(set(owners[:3]))==1 and owners[3]!=owners[0], 'login lifecycle owner behavior differs')
    local=mapper_inventory(rows,expected)
    manual=[v['event'] for k,v in local['accepted'].items() if k[0]=='action' and field(v['event'],'action.target.name')=='LoginWithSubdomainTapped']
    require(len(manual)==1 and field(manual[0],'view.id')==owners[0], 'named subdomain action owner/count differs')
    first,last=(phases[n]['snapshot']['sequence'] for n in ['login-returned','login-reactivated'])
    scene=phases['login-returned']['binding']['scene']
    require(first<background['sequence']<last, 'Home evidence outside journey')
    callbacks=lifecycle_cycle(rows,first,last,scene)
    require(background['sequence']==callbacks['didEnterBackground'][-1], 'Home checkpoint is not the captured background exit')
    require(field(local['views'][owners[0]]['event'],'view.is_active') is False, 'previous login owner never stopped')
    return dict(state='J01_LOCAL_BOUNDARIES_JOINED', old_view=owners[0], new_view=owners[3], action_count=1)


def j04(rows, observations, expected, background):
    before=observations['service-list-after-dashboard'];after=observations['service-list-reactivated']
    old,new=before['owner']['view_id'],after['owner']['view_id']
    require(old!=new, 'foreground reentry reused the stopped service-list occurrence')
    require(before['binding']==after['binding'] and before['visible']['controller']==after['visible']['controller'],
            'authenticated list native instance changed')
    start,end=before['snapshot']['sequence'],after['snapshot']['sequence']
    require(start<background['sequence']<end, 'authenticated Home evidence outside journey')
    callbacks=lifecycle_cycle(rows,start,end,before['binding']['scene'])
    require(background['sequence']==callbacks['didEnterBackground'][-1], 'Home checkpoint is not the captured background exit')
    local=mapper_inventory(rows,expected)
    require(field(local['views'][old]['event'],'view.is_active') is False
            and field(local['views'][new]['event'],'view.is_active') is True, 'authenticated view lifetime differs')
    return dict(state='J04_LOCAL_BOUNDARIES_JOINED',old_view=old,new_view=new,process_id=expected['pid'])
