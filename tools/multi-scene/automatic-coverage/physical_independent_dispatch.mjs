const configuration = load("p2_physical_configuration");
const configurationRef = load("p2_physical_configuration_ref");
const releaseRef = load("p2_physical_release_ref");
if (!configuration || !configurationRef || !releaseRef || configuration.operation_profile !== "P2_PHYSICAL_UIKIT_INDEPENDENT_CAPTURE_END_THEN_HUMAN_V1") throw Error("exact physical configuration absent");
const runtime = configuration.runtime_source;
if (!runtime || !runtime.path || !runtime.sha256) throw Error("bound runtime source absent");
const python = "/Users/valentin.pertuisot/.pyenv/versions/3.12.8/bin/python3";
const quote = value => "'" + String(value).replaceAll("'", "'\\''") + "'";
const args = [python,"-I","-S","-B",runtime.path];
const refs = [configurationRef.path,configurationRef.sha256,releaseRef.path,releaseRef.sha256];
const command = values => values.map(quote).join(" ");
const calls = [], workerReturns = [], helperReturns = [], seen = new Set();
let pending = 0, buffer = "", toolSession = null, last = null;
store("p2_physical_actuals",calls);store("p2_physical_pending",0);
store("p2_physical_worker_returns",workerReturns);store("p2_physical_helper_returns",helperReturns);
const result = value => {
  if (value.exit_code !== 0 || value.session_id) throw Error("request/publisher helper did not complete successfully");
  return JSON.parse(value.output);
};
const saveRaw = async (request, raw, started, finished) => {
  const path = configuration.root + "/owner-return-" + request.request_id + ".json";
  const data = JSON.stringify(JSON.stringify(raw));
  const script = "import pathlib,json,hashlib; p=pathlib.Path(" + JSON.stringify(path) + "); b=(json.dumps(json.loads(" + data + "),indent=2)+\"\\n\").encode(); p.open('xb').write(b); print(json.dumps(dict(path=str(p),sha256=hashlib.sha256(b).hexdigest())))";
  const saved = await tools.exec_command({cmd:command([python,"-I","-S","-B","-c",script]),sandbox_permissions:"require_escalated",justification:"Preserve this actual returned supported short-session observation before validation, with no additional native action.",max_output_tokens:1000});
  helperReturns.push(saved);const rawRef=result(saved);
  calls[calls.length-1].raw_ref=rawRef;store("p2_physical_actuals",calls);
  const published = await tools.exec_command({cmd:command([...args,"publish",...refs,request.path,rawRef.path,rawRef.sha256,String(started),String(finished)]),sandbox_permissions:"require_escalated",justification:"Publish the exact observed response to the immutable request-bound short-session consumer; retain errors or late observations as returned.",max_output_tokens:2000});
  helperReturns.push(published);return result(published);
};
const processLine = async (line, cleanupOnly=false) => {
  let row;try {row=JSON.parse(line);} catch {return;}
  if (!row.supported_session) { if (row.human_setup || row.human_input || row.human_release) {store("p2_physical_latest_human_message",row);text(row);} return; }
  if (cleanupOnly && row.supported_session.phase!=="end") {
    store("p2_physical_held_request",{line,reason:"original dispatch stopped; no new Start/capture admitted"});return;
  }
  const path=row.supported_session.request;
  const checked=await tools.exec_command({cmd:command([...args,"request",...refs,path]),max_output_tokens:2500});helperReturns.push(checked);
  const bound=result(checked), request=bound.request;
  if (seen.has(request.request_id) || request.phase!==row.supported_session.phase) throw Error("duplicate/foreign short-session dispatch");
  seen.add(request.request_id);
  const tool={start:"mcp__xcode__DeviceInteractionStartSession",capture:"mcp__xcode__DeviceInteractionSynthesize",end:"mcp__xcode__DeviceInteractionEndSession"}[request.phase];
  if (!tool || !tools[tool]) throw Error("supported tool unavailable");
  const started=Date.now()/1000;pending=1;store("p2_physical_pending",pending);
  const raw=await tools[tool](request.arguments);
  const finished=Date.now()/1000;pending=0;store("p2_physical_pending",pending);
  const actual={request:bound.reference,phase:request.phase,request_id:request.request_id,tool,arguments:request.arguments,started_at:started,finished_at:finished,raw};
  calls.push(actual);store("p2_physical_actuals",calls);
  actual.publication=await saveRaw({...request,path},raw,started,finished);
};
const consume = async cleanupOnly => {
  buffer += last.output || "";
  const lines=buffer.split("\n");buffer=lines.pop();
  for (const line of lines) await processLine(line,cleanupOnly);
};
try {
  last = await tools.exec_command({cmd:command([...args,"execute",...refs]),sandbox_permissions:"require_escalated",justification:"Execute the exact root-released physical UIKit candidate: frozen CLI product launch, one short workspace-free capture and owned End, same-process writer/idle proof before genuine Ready, unchanged human journey and task-only cleanup within fixed clocks.",yield_time_ms:1000,max_output_tokens:2500});
  workerReturns.push(last);toolSession=last.session_id;
  while (true) {
    await consume(false);
    if (!last.session_id) break;
    last=await tools.write_stdin({session_id:last.session_id,chars:"",yield_time_ms:1000,max_output_tokens:2500});workerReturns.push(last);
  }
  store("p2_physical_owner_terminal",{pending,tool_session:toolSession,actuals:calls,worker_returns:workerReturns,helper_returns:helperReturns,terminal:last,buffer});
  text({state:"ACTUAL_PHYSICAL_WORKER_TERMINAL",tool_session:toolSession,pending,calls:calls.length,exit_code:last.exit_code,terminal_output:last.output});
} catch (error) {
  const primary={pending,tool_session:toolSession,actuals:calls,worker_returns:workerReturns,helper_returns:helperReturns,last,buffer,error:String(error)};
  store("p2_physical_owner_stop",primary);
  // An unresolved supported call is fatal: no competing End or cleanup owner.
  // After a completed returned observation/publication failure, retain the worker
  // and drain only its original validated End request. Never redispatch a capture.
  let cleanupStop=null;
  if (pending===0 && last?.session_id) {
    try {
      while (last.session_id) {
        last=await tools.write_stdin({session_id:last.session_id,chars:"",yield_time_ms:1000,max_output_tokens:2500});workerReturns.push(last);
        await consume(true);
      }
    } catch (cleanupError) {cleanupStop=String(cleanupError);}
  }
  store("p2_physical_stopped_worker_disposition",{pending,tool_session:toolSession,last,buffer,cleanup_stop:cleanupStop,actuals:calls,worker_returns:workerReturns,helper_returns:helperReturns,qualified:false});
  throw error;
}
