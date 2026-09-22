"""Bounded source transformation of the stopped fold runner; original artifacts stay immutable."""
import hashlib
from acceptance_common import require


def replace_once(text, before, after):
    require(text.count(before)==1,'fold runner anchor changed: '+before[:70])
    return text.replace(before,after)


def render(name, original, expected_sha256):
    require(hashlib.sha256(original).hexdigest()==expected_sha256,'frozen fold source changed')
    text=original.decode()
    if name=='fold_oracle.py':
        text='from resource_fold_human import validate_input\n'+text
        start=text.index("    command=json.loads(asset(p['cua_command']))")
        end=text.index("    display=json.loads(asset(p['displays']))",start)
        text=text[:start]+"    validate_input(p,request,device)\n"+text[end:]
        text=replace_once(text,"['input_started_at','input_finished_at','input_returned_at','cua_before','cua_after','cua_command']",
                          "['input_kind','input_started_at','input_finished_at','input_returned_at','human_before_display','human_after_display','human_prompt','human_before_command','human_after_command']")
        text=replace_once(text,"audit=json.loads(asset(expected.get('ownership_audit')))",
                          "audit_document=json.loads(asset(expected.get('ownership_audit')))\n    require(audit_document.get('status')=='SOURCE_REVIEWED' and set(audit_document.get('arms',{}))=={'A','B'},'incomplete full ownership audit')\n    audit=audit_document['arms'][ident['arm']]")
    elif name=='fold_host.py':
        text='import resource_fold_human as human\n'+text
        start=text.index("    proof=admission['pose_preflight']");end=text.index('def extract_ready',start)
        text=text[:start]+"    observed=display(device,out,'fold-initial-displays');active=rules.active_display(host.read(observed['path']),device)\n    inventory=host.read(observed['path'])['result']['displays']\n    host.require(any(d.get('active') is not True and d['nativeSize'][0]*d['nativeSize'][1]>active['nativeSize'][0]*active['nativeSize'][1] for d in inventory),'initial Closed display absent')\n    return {'initial_displays':observed,'phases':{},'cleanup_pose_restored':False}\n"+text[end:]
        text=replace_once(text,"folder=out/('pose-'+phase_name)","folder=out/('human-'+phase_name)")
        start=text.index("    returned=wait_file(folder/'pose.response.json'");end=text.index('    observed_doc=',start)
        text=text[:start]+"    input_path=human.observe(request_path,host=host,rules=rules,display=display)\n    receipt=complete_pose(request_path,input_path)\n"+text[end:]
        text=replace_once(text,"['cua_before','cua_after','cua_command','terminal']","['human_before_display','human_after_display','human_prompt','terminal']")
        text=replace_once(text,"terminal['status']=='ONE_POSE_CLICK_RETURNED'","terminal['status']=='HUMAN_DISPLAY_OBSERVED' and terminal['automated_input_workers']==0")
        text=replace_once(text,"['input_started_at','input_finished_at','input_returned_at','cua_before','cua_after','cua_command']",
                          "['input_kind','input_started_at','input_finished_at','input_returned_at','human_before_display','human_after_display','human_prompt','human_before_command','human_after_command']")
        start=text.index('def cleanup(');end=text.index("\nif __name__=='__main__':",start)
        text=text[:start]+"def cleanup(device,out,fold,wait_file):\n    return human.restore(device,out,fold,host=host,rules=rules,display=display,reserve=stage.NATIVE_CLEANUP_RESERVE)\n"+text[end:]
    else:require(False,'unadmitted fold transformation')
    compile(text,name,'exec')
    return text.encode()
