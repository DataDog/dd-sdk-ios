"""Public controller visibility and real adaptive geometry; no private class rules."""
import transition_contract as native


def front_controllers(snapshot,binding):
    graph=native.controller_map(snapshot);root=binding['root'];window=binding['window']
    native.require(root in graph,'owned root absent from public controller inventory')
    seen=set()
    def visit(identity):
        native.require(identity in graph and identity not in seen,'missing/cyclic public controller hierarchy')
        seen.add(identity);node=graph[identity]
        native.require(node['window']==window,'foremost controller detached from owned window')
        presented=node['presented']
        if presented!='nil':return visit(presented)
        result={identity}
        if 'navigation_stack' in node:
            visible=node['visible'];native.require(visible in node['navigation_stack'],'navigation visible controller outside its native stack')
            return result|visit(visible)
        for child in node['children']:
            native.require(child in graph,'incomplete actual child inventory')
            if graph[child]['window']==window:result |= visit(child)
        return result
    return visit(root)


def visible_transition(before,after,binding,result):
    a=front_controllers(before,binding);b=front_controllers(after,binding)
    native.require(result['from'] in a and result['result'] in b,'transition endpoint is attached but not foremost')
    if not result['cancelled']:
        native.require(result['from'] not in b,'completed outgoing controller remains foremost')
    return dict(state='PUBLIC_FOREMOST_CONTROLLER_QUALIFIED',before=sorted(a),after=sorted(b))


def selected_detail(snapshot,binding,framework):
    state=snapshot['payload']['transition'];graph=native.controller_map(snapshot)
    front=front_controllers(snapshot,binding)
    if framework=='SwiftUI':
        model=state['model'];native.require(model['selection']=='detail' and isinstance(model['selection_occurrence'],str)
            and model['selection_occurrence'] and model['path']==[] and model['sheet'] is False,'split model/path not stable on selected Detail')
    else:
        native.require(framework=='UIKit','unknown native framework')
        model=state['model'];native.require(model['selection']=='detail' and model['selection_occurrence'],'UIKit selection not recorded')
        details=[row for row in graph.values() if row['accessibility_id']=='controller.detail' and row['id'] in front]
        native.require(len(details)==1,'selected UIKit detail not actually foremost')
    splits=[row for row in graph.values() if 'split_collapsed' in row]
    if framework=='UIKit':
        native.require(len(splits)==1,'missing or ambiguous fixture-owned UIKit split controller')
        split=splits[0]['id']
    else:
        # The frozen SwiftUI source constructs NavigationSplitView. Its public
        # UIKit containment is evidence, not an assumed implementation class.
        split=binding['root']
    return dict(model=model,split=split,source='UISplitViewController' if framework=='UIKit' else 'NavigationSplitView',
                native_splits=[dict(id=x['id'],collapsed=x['split_collapsed']) for x in splits],front=sorted(front))


def adaptive(before,after,binding,framework):
    a,b=selected_detail(before,binding,framework),selected_detail(after,binding,framework)
    native.require(a['model']==b['model'] and a['split']==b['split'],'selection/path or native split replaced across resize')
    native.require(before['sequence']<after['sequence'],'adaptive boundaries reversed')
    def owned(snapshot):
        scenes=snapshot['payload']['topology']['scene_inventory']
        native.require(len(scenes)==1 and scenes[0]['id']==binding['scene'],'adaptive scene changed')
        windows=[w for w in scenes[0]['windows'] if w['id']==binding['window']]
        native.require(len(windows)==1,'adaptive owned window absent')
        return windows[0]['bounds']
    native.require(owned(before)!=owned(after),'unchanged app window is not adaptive resize')
    return dict(state='ADAPTIVE_SELECTION_AND_NATIVE_GEOMETRY_QUALIFIED',before=a,after=b,
                remaining='Actual display/fold or physical-window evidence and independent mapper/backend ownership remain required.')


def restored(original,current,binding,framework,initial_display,final_display):
    a,b=selected_detail(original,binding,framework),selected_detail(current,binding,framework)
    keys=['uniqueId','displayId','nativeSize','pointScale','currentOrientation','bounds','primary']
    native.require(initial_display.get('primary') is True and final_display.get('primary') is True
        and all(initial_display.get(k)==final_display.get(k) for k in keys),'final active display is not original Closed state')
    native.require(a['model']==b['model'] and a['split']==b['split'],'original selected path or native root not restored')
    def state(snapshot):
        scenes=snapshot['payload']['topology']['scene_inventory']
        native.require(len(scenes)==1 and scenes[0]['id']==binding['scene'],'restored scene differs')
        scene=scenes[0];window=native.one([w for w in scene['windows'] if w['id']==binding['window']],'restored owned window')
        return dict(scene={k:scene[k] for k in ['id','activation','screen_bounds','coordinate_bounds','screen_scale']},
                    window={k:window[k] for k in ['id','root','bounds','key','root_attached','hidden','alpha','level']})
    native.require(state(original)==state(current),'original native scene/window geometry not restored')
    return dict(state='ORIGINAL_DISPLAY_WINDOW_SELECTION_RESTORED',display={k:final_display.get(k) for k in keys},
                original_sequence=original['sequence'],restored_sequence=current['sequence'])
