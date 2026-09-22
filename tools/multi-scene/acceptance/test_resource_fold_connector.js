const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const source=fs.readFileSync(process.env.RESOURCE_FOLD_CONNECTOR,'utf8');
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
async function run(options={}){
  const started=Date.now()-(options.expired?120000:300),request={request_id:'request',kind:'rum-startup',gather_started_ms:options.future?Date.now()+10000:started,query:'exact session',from:'from',to:'to'};
  const raw={content:[{type:'text',text:'actual returned é'}]},payloads=[],commands=[],notes=[];let queried=0,polls=0;
  const line=JSON.stringify({backend_request:'/runtime/cells/A-automatic/bridge/request.request.json',request})+'\n';
  const tools={
    exec_command:async args=>{
      commands.push(args.cmd);
      if(args.cmd.includes(' cell '))return {session_id:9,output:options.fragment?line.slice(0,25):'{"human_input":{"phase":"open"}}\n'+line};
      if(args.cmd.includes(' ingest --payload-json ')){
        const encoded=args.cmd.match(/--payload-json '([\s\S]+)' --root/)[1].replaceAll("'\\''","'");const payload=JSON.parse(encoded);payloads.push(payload);
        if(options.publicationFailure&&payload.kind==='rum')throw Error('late publication');
        return {exit_code:0,output:JSON.stringify(payload.kind==='aggregate'?{count:3}:{row_count:3,trace_ids:[],published:true,count:3})};
      }
      if(args.cmd.includes('summary.json'))return {exit_code:0,output:'{"state":"mock-complete"}'};
      if(args.cmd.includes('transport-error'))return {exit_code:0,output:''};
      if(args.cmd.includes(' verify-helpers ')||args.cmd.includes(' verify '))return {exit_code:0,output:'verified'};
      throw Error('unexpected helper '+args.cmd);
    },
    write_stdin:async()=>{polls++;return options.fragment&&polls===1?{session_id:9,output:line.slice(25)+line}:{exit_code:0,output:''};},
    mcp__datadog__aggregate_rum_events:async()=>{queried++;return raw;},
    mcp__datadog__search_datadog_rum_events:async()=>{queried++;return raw;}
  };
  const invoke=await new AsyncFunction(source+'\nreturn runEXP202;')();
  const result=await invoke({tools,notify:x=>notes.push(x),host:'/original/host',matrix:'/original/matrix',oracle:'/original/oracle',arm:'A',mode:'automatic',device:'device',output:'/runtime/cells/A-automatic',purpose:'acceptance',helperManifestSHA256:'original',runtimeRoot:'/runtime',runtimePlanSHA256:'plan',runtimeStageSHA256:'stage',runtimeScript:'/repo/resource_fold_runtime.py'});
  return {raw,payloads,commands,notes,queried,result,started};
}
test('retains actual tool envelopes and original published request clock',async()=>{const r=await run();assert.equal(r.queried,2);assert.deepEqual(r.payloads.map(p=>p.raw_envelope),[r.raw,r.raw]);for(const p of r.payloads){assert.equal(p.gather_started_ms,r.started);assert.equal(p.deadline_ms,r.started+115000);}assert.equal(r.result.exit_code,0);});
test('expired phase is not renewed at connector arrival',async()=>{const r=await run({expired:true});assert.equal(r.queried,0);assert(r.commands.some(x=>x.includes('transport-error')));});
test('future request clock fails before backend access',async()=>{const r=await run({future:true});assert.equal(r.queried,0);assert(r.commands.some(x=>x.includes('transport-error')));});
test('fragmented stdout and repeated notification consume one request',async()=>{const r=await run({fragment:true});assert.equal(r.queried,2);assert.equal(r.payloads.length,2);});
test('late publication keeps raw response and emits terminal error',async()=>{const r=await run({publicationFailure:true});assert.equal(r.payloads.length,2);assert.deepEqual(r.payloads[1].raw_envelope,r.raw);assert(r.commands.some(x=>x.includes('transport-error')));});
test('human prompt is exposed without an automated input lease',async()=>{const r=await run();assert(r.notes.some(x=>x.human_input?.phase==='open'));assert(!r.commands.some(x=>x.includes('fence.lease')||x.includes('pose.request')));});
