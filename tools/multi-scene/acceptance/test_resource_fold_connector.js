const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const source=fs.readFileSync(process.env.RESOURCE_FOLD_CONNECTOR,'utf8');
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
async function run(options={}){
  const started=Date.now()-(options.expired?120000:300),request={request_id:'request',kind:'rum-startup',gather_started_ms:options.future?Date.now()+10000:started,query:'exact session',from:'from',to:'to'};
  const raw={content:[{type:'text',text:'actual returned é'}]},payloads=[],commands=[],notes=[];let queried=0,polls=0,clock=Date.now(),lastCount=3;
  const line=JSON.stringify({backend_request:'/runtime/cells/A-automatic/bridge/request.request.json',request})+'\n';
  const tools={
    exec_command:async args=>{
      commands.push(args.cmd);
      if(args.cmd.includes(' cell '))return {session_id:9,output:options.fragment?line.slice(0,25):'{"human_input":{"phase":"open"}}\n'+line};
      if(args.cmd.includes(' ingest --payload-json ')){
        const encoded=args.cmd.match(/--payload-json '([\s\S]+)' --root/)[1].replaceAll("'\\''","'");const payload=JSON.parse(encoded);payloads.push(payload);
        if(options.decodeFailure&&payload.kind==='rum')throw Error(options.decodeFailure);
        const first=payload.decoded_path.includes('/inventory-000/');
        lastCount=options.growth&&!first&&!options.alwaysGrowing?4:3;
        if(options.lateRetry&&payload.kind==='rum')clock=started+114000;
        return {exit_code:0,output:JSON.stringify(payload.kind==='aggregate'?{count:lastCount}:{row_count:options.growth?4:3,trace_ids:[],published:false,is_truncated:options.truncated?'true':'false'})};
      }
      if(args.cmd.includes(' assemble --request ')){
        if(options.publicationFailure)throw Error('late publication');
        return{exit_code:0,output:JSON.stringify({published:true,count:lastCount})};
      }
      if(args.cmd.startsWith('python3 -c ')&&args.cmd.includes('inventory-status.json'))return {exit_code:0,output:''};
      if(args.cmd.includes('summary.json'))return {exit_code:0,output:'{"state":"mock-complete"}'};
      if(args.cmd.includes('transport-error'))return {exit_code:0,output:''};
      if(args.cmd.includes(' verify-helpers ')||args.cmd.includes(' verify '))return {exit_code:0,output:'verified'};
      throw Error('unexpected helper '+args.cmd);
    },
    write_stdin:async()=>{polls++;return options.fragment&&polls===1?{session_id:9,output:line.slice(25)+line}:{exit_code:0,output:''};},
    mcp__datadog__aggregate_rum_events:async()=>{queried++;return raw;},
    mcp__datadog__search_datadog_rum_events:async()=>{queried++;return raw;}
  };
  class Clock extends Date{static now(){return clock;}}
  const invoke=await new AsyncFunction('Date','setTimeout',source+'\nreturn runEXP202;')(Clock,(fn,ms)=>{clock+=ms;fn();});
  const result=await invoke({tools,notify:x=>notes.push(x),host:'/original/host',matrix:'/original/matrix',oracle:'/original/oracle',arm:'A',mode:'automatic',device:'device',output:'/runtime/cells/A-automatic',purpose:'acceptance',helperManifestSHA256:'original',runtimeRoot:'/runtime',runtimePlanSHA256:'plan',runtimeStageSHA256:'stage',runtimeScript:'/repo/resource_fold_runtime.py'});
  return {raw,payloads,commands,notes,queried,result,started};
}
test('retains actual tool envelopes and original published request clock',async()=>{const r=await run();assert.equal(r.queried,3);assert.deepEqual(r.payloads.map(p=>p.raw_envelope),[r.raw,r.raw,r.raw]);for(const p of r.payloads){assert.equal(p.gather_started_ms,r.started);assert.equal(p.deadline_ms,r.started+115000);}assert.equal(r.result.exit_code,0);});
test('expired phase is not renewed at connector arrival',async()=>{const r=await run({expired:true});assert.equal(r.queried,0);assert(r.commands.some(x=>x.includes('transport-error')));});
test('future request clock fails before backend access',async()=>{const r=await run({future:true});assert.equal(r.queried,0);assert(r.commands.some(x=>x.includes('transport-error')));});
test('fragmented stdout and repeated notification consume one request',async()=>{const r=await run({fragment:true});assert.equal(r.queried,3);assert.equal(r.payloads.length,3);});
test('late publication keeps raw response and emits terminal error',async()=>{const r=await run({publicationFailure:true});assert.equal(r.payloads.length,3);assert.deepEqual(r.payloads[1].raw_envelope,r.raw);assert(r.commands.some(x=>x.includes('transport-error')));});
test('human prompt is exposed without an automated input lease',async()=>{const r=await run();assert(r.notes.some(x=>x.human_input?.phase==='open'));assert(!r.commands.some(x=>x.includes('fence.lease')||x.includes('pose.request')));});
test('count growth retains the failed inventory then republishes only a complete fresh attempt',async()=>{
  const r=await run({growth:true});assert.equal(r.payloads.length,5);
  assert.equal(new Set(r.payloads.map(p=>p.raw_path)).size,5);
  assert(r.commands.some(c=>c.includes('inventory-status.json')));
  const publication=r.commands.find(c=>c.includes(' assemble --request '));assert(publication.includes('inventory-001'));
  assert(!r.commands.some(c=>c.includes('transport-error')));
  assert.deepEqual(new Set(r.payloads.map(p=>p.deadline_ms)),new Set([r.started+115000]));
});
test('continuously growing indexing stops at finite bound without publication',async()=>{
  const r=await run({growth:true,alwaysGrowing:true});assert.equal(r.payloads.length,40);
  assert(!r.commands.some(c=>c.includes(' assemble --request ')));assert(r.commands.some(c=>c.includes('transport-error')));
});
test('late growth cannot renew the original request clock',async()=>{
  const r=await run({growth:true,lateRetry:true});assert.equal(r.payloads.length,2);assert(r.commands.some(c=>c.includes('transport-error')));
});
test('truncated and malformed responses stop without retrying or publication',async()=>{
  for(const option of [{truncated:true},{decodeFailure:'duplicate backend row'},{decodeFailure:'malformed envelope'}]){
    const r=await run(option);assert.equal(r.payloads.length,2);assert(r.commands.some(c=>c.includes('transport-error')));
    assert(!r.commands.some(c=>c.includes(' assemble --request ')));
  }
});
