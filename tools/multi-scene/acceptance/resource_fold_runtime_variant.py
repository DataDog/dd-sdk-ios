"""Project the frozen Resource runner onto a separate human-input runtime stage."""
import hashlib
from pathlib import Path
from acceptance_common import require
from resource_fold_variant import replace_once, render as human_render


def render(name, original, expected_sha256, *, semantic=False):
    require(hashlib.sha256(original).hexdigest()==expected_sha256,'original runtime source changed')
    if name in ['fold_host.py','fold_oracle.py']:
        text=human_render(name,original,expected_sha256).decode()
        if name=='fold_host.py':
            text=replace_once(text,'import host,fold_oracle as rules,stage,fence',
                'import host,fold_oracle as rules\nimport resource_fold_runtime as stage\nimport resource_fold_runtime as fence')
    elif name=='cell.py':
        text=original.decode()
        text=replace_once(text,'import safety, host, fold_host, fence, stage',
            'import safety, host, fold_host\nimport resource_fold_runtime as fence\nimport resource_fold_runtime as stage')
        text=replace_once(text,'admission=safety.admit(args)','admission=stage.admit(args)')
        text=replace_once(text,"root=args.root.resolve();verify_helpers(root,args.helper_manifest_sha256,args.oracle);build=",
            "root=args.root.resolve();stage.verify_runtime(args.runtime_root);verify_helpers(root,args.helper_manifest_sha256,args.oracle);build=")
        text=replace_once(text,'    def update(state):',
            "    summary.update(runtime_plan_sha256=admission['plan_sha256'],runtime_stage_sha256=admission['stage_admission_sha256'],runtime_admission_sha256=args.admission_sha256)\n    def update(state):")
        text=replace_once(text,"        path=out/'bridge'/(request['request_id']+'.request.json');save(path,request)",
            "        budget=600 if kind.startswith('span-') else 115\n        request['gather_started_ms']=time.time_ns()//1_000_000\n        require(request['gather_started_ms']/1000+budget+10<host.DEADLINE,'no complete backend phase reserve')\n        path=out/'bridge'/(request['request_id']+'.request.json');save(path,request)\n        print(json.dumps({'backend_request':str(path),'request':request}),flush=True)")
        text=replace_once(text,"verify_helpers(root,args.helper_manifest_sha256,args.oracle);verify_backend_interpretation(root,args.helper_manifest_sha256);verify_source(root,args.arm);cleanup['helpers_unchanged']=True",
            "stage.verify_runtime(args.runtime_root);verify_helpers(root,args.helper_manifest_sha256,args.oracle);verify_backend_interpretation(root,args.helper_manifest_sha256);verify_source(root,args.arm);cleanup['helpers_unchanged']=True")
        text=replace_once(text,"p.add_argument('--admission-sha256',required=True)",
            "p.add_argument('--admission-sha256',required=True)\np.add_argument('--runtime-root',type=Path,required=True)")
    elif name=='connector.js':
        text=original.decode()
        text=replace_once(text,'admissionRequestSHA256})','runtimeRoot, runtimePlanSHA256, runtimeStageSHA256, runtimeScript})')
        text=replace_once(text,'  await verify();','  await verify();\n  await shell("python3 -B "+quote(runtimeScript)+" verify --runtime-root "+quote(runtimeRoot)+" --plan-sha256 "+quote(runtimePlanSHA256));')
        start=text.index('  const gather = async (request, requestPath) => {')
        end=text.index('  const execution=await tools.exec_command(',start)
        text=text[:start]+Path(__file__).with_name('resource_fold_gather.js').read_text()+text[end:]
        start=text.index('  const execution=await tools.exec_command(')
        end=text.index('  const readFinal',start)
        text=text[:start]+'''  const execution=await tools.exec_command({cmd:"python3 -B "+quote(runtimeScript)+" cell --runtime-root "+quote(runtimeRoot)+" --plan-sha256 "+quote(runtimePlanSHA256)+" --stage-sha256 "+quote(runtimeStageSHA256)+" --arm "+quote(arm)+" --mode "+quote(mode)+" --device "+quote(device),login:false,workdir:host,sandbox_permissions:"require_escalated",justification:"Run one defined human-input Resource/Trace acceptance cell with immutable build reuse, fixed clocks and task-only cleanup.",yield_time_ms:1000,max_output_tokens:1500});
'''+text[end:]
        start=text.index('  if(execution.exit_code!==undefined)')
        text=text[:start]+'''  const handled=new Set();let current=execution,pending="";
  while(true){
    pending+=(current.output||"");const lines=pending.split("\\n");pending=lines.pop();
    for(const line of lines){
      let row;try{row=JSON.parse(line);}catch{continue;}
      if(row.backend_request&&!handled.has(row.backend_request)){
        handled.add(row.backend_request);
        try{await gather(row.request,row.backend_request);}
        catch(error){
          const responsePath=row.backend_request.replace(/\\.request\\.json$/,".response.json");
          await shell("python3 -B "+quote(runtimeScript)+" transport-error --request "+quote(row.backend_request)+" --message "+quote(String(error)),true);
          notify({stage:"backend lane stopped",reason:String(error),responsePath});
        }
      }else if(row.state||row.human_input)notify(row);
    }
    if(current.exit_code!==undefined)break;
    if(current.session_id===undefined)throw Error("Cell lost process handle");
    current=await tools.write_stdin({session_id:current.session_id,chars:"",yield_time_ms:1000,max_output_tokens:1500});
  }
  return {exit_code:current.exit_code,summary:await readFinal()};
}
'''
        return text.encode()
    else:require(False,'unadmitted runtime projection')
    if semantic and name=='fold_oracle.py':
        from resource_fold_scope import render_fold
        return render_fold(text.encode())
    if semantic and name=='cell.py':
        require(text.count('safety.protected(root)')==2,'protected boundary count changed')
        text=text.replace('safety.protected(root)','stage.verify_workspace(args.runtime_root)')
        text=replace_once(text,"spec_from_file_location('oracle',args.oracle)",
                         "spec_from_file_location('oracle',args.runtime_root/'generated/scoped_oracle.py')")
        text=replace_once(text,"    def update(state):",
                         "    summary['scoped_oracle_sha256']=digest(args.runtime_root/'generated/scoped_oracle.py')\n    def update(state):")
    compile(text,name,'exec');return text.encode()
