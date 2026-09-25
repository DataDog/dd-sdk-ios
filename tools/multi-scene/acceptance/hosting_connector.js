// Existing acceptance transport: one autonomous cell, no model-mediated critical input.
// Arguments supplied by the trusted tool orchestrator: tools, notify, root, arm, mode, device, repo.
const quote = s => "'" + String(s).replaceAll("'", "'\\''") + "'";
const selectedFamily = typeof family === 'undefined' ? 'hosting' : family;
if (!['hosting','webview','hosting_paced'].includes(selectedFamily)) throw Error('Unknown acceptance family');
const script = repo + '/tools/multi-scene/acceptance/s2_' + selectedFamily + '_workflow.py';
const shell = async args => {
  let r = await tools.exec_command(args); let output = r.output || '';
  while (r.exit_code === undefined && r.session_id !== undefined) {
    r = await tools.write_stdin({session_id:r.session_id,chars:'',yield_time_ms:1000,max_output_tokens:1500});
    output += r.output || '';
  }
  if (r.exit_code === undefined) throw Error('Missing helper completion');
  return {...r,output};
};
async function exchange(path) {
  const read = await shell({cmd:'cat '+quote(path),login:false,max_output_tokens:2000});
  if (read.exit_code!==0) throw Error('Request unavailable');
  const bound=JSON.parse(read.output),request=bound.request;
  const response={request,count_response:null,pages:[]};
  try {
    if (Date.now()/1000>=bound.deadline) throw Error('Expired request');
    response.count_response=await tools.mcp__datadog__aggregate_rum_events({query:request.query,from:request.from,to:request.to,computes:[{aggregation:'COUNT',field:'*',output:'events'}],max_tokens:1000,telemetry:{intent:'Count complete controlled acceptance session for exact native ownership acceptance'}});
    const countText=response.count_response.content.filter(x=>x.type==='text').map(x=>x.text).join('\n');
    const countPayload=[...countText.matchAll(/<TSV_DATA>([\s\S]*?)<\/TSV_DATA>/g)];
    if(countPayload.length!==1) throw Error('Unqualified count response');
    const countRows=countPayload[0][1].trim().split(/\r?\n/);
    if(countRows[0]!=='events'||countRows.length>2||(countRows.length===2&&!/^\d+$/.test(countRows[1]))) throw Error('Unqualified count shape');
    const observedCount=countRows.length===1?0:Number(countRows[1]);
    if(observedCount<(bound.minimum_rows||0)) response.count_pending=true;
    let offset=0;
    for(let page=0;!response.count_pending&&page<6;page++) {
      if (Date.now()/1000>=bound.deadline) throw Error('Expired inventory deadline');
      const raw=await tools.mcp__datadog__search_datadog_rum_events({query:request.query,from:request.from,to:request.to,start_at:offset,detailed_output:true,max_tokens:50000,telemetry:{intent:'Retain complete raw controlled acceptance session including final view revisions'}});
      response.pages.push({start_at:offset,response:raw});
      const text=raw.content.filter(x=>x.type==='text').map(x=>x.text).join('\n');
      const matches=[...text.matchAll(/<JSON_DATA>([\s\S]*?)<\/JSON_DATA>/g)];
      if(matches.length!==1) throw Error('Unqualified raw response schema');
      const rows=matches[0][1].trim()?JSON.parse(matches[0][1]):[];
      if(!Array.isArray(rows)) throw Error('Raw rows are not an array');
      if(rows.length===0) break;
      offset+=rows.length;
      if(offset>100||page===5) throw Error('Inventory bound exceeded');
    }
  } catch(error) {response.error=String(error);}
  // ASCII transport of exact tool return objects; no source projection or fixture substitution.
  const bytes=Array.from(unescape(encodeURIComponent(JSON.stringify(response))),x=>x.charCodeAt(0));
  const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';let payload='';
  for(let i=0;i<bytes.length;i+=3){const n=(bytes[i]<<16)|((bytes[i+1]||0)<<8)|(bytes[i+2]||0);payload+=alphabet[(n>>>18)&63]+alphabet[(n>>>12)&63]+(i+1<bytes.length?alphabet[(n>>>6)&63]:'=')+(i+2<bytes.length?alphabet[n&63]:'=');}
  // Send raw evidence through stdin; large complete inventories exceed macOS argv limits.
  const publication="python3 -B - <<'S2_RAW_EVIDENCE'\nimport sys\nfrom pathlib import Path\nfrom types import SimpleNamespace\nsys.path.insert(0,"+JSON.stringify(repo+'/tools/multi-scene/acceptance')+")\nimport s2_hosting_workflow as workflow\nworkflow.publish(SimpleNamespace(request=Path("+JSON.stringify(path)+"),payload='"+payload+"'))\nS2_RAW_EVIDENCE";
  const done=await shell({cmd:publication,login:false,sandbox_permissions:'require_escalated',justification:'Persist exact Datadog tool responses and atomically publish the validated acceptance inventory within its original deadline.',max_output_tokens:1200});
  if(done.exit_code!==0) throw Error('Evidence publication failed: '+done.output);
}
const invocation=arm==='backend-only'?' backend-only --root '+quote(root):' cell --root '+quote(root)+' --arm '+quote(arm)+(selectedFamily==='hosting'?' --mode '+quote(mode):'')+' --device '+quote(device);
const args={cmd:'python3 -B '+quote(script)+invocation,login:false,sandbox_permissions:'require_escalated',justification:'Run the defined acceptance cell, collect exact local/backend evidence, and remove only its task app under fixed deadlines.',yield_time_ms:1000,max_output_tokens:1500};
let current=await tools.exec_command(args);let pending='';const seen=new Set();
while(true) {
  pending+=(current.output||'');
  const lines=pending.split('\n');pending=lines.pop();
  for(const line of lines) {
    let row;try {row=JSON.parse(line);} catch {continue;}
    if(row.backend_request&&!seen.has(row.backend_request)) {
      seen.add(row.backend_request);
      try {await exchange(row.backend_request);} catch(error) {notify({transport_error:String(error)});}
    } else if(row.state || row.human_input) notify(row);
  }
  if(current.exit_code!==undefined) return {exit_code:current.exit_code,root,arm,mode};
  if(current.session_id===undefined) throw Error('Cell lost process handle');
  current=await tools.write_stdin({session_id:current.session_id,chars:'',yield_time_ms:1000,max_output_tokens:1500});
}
