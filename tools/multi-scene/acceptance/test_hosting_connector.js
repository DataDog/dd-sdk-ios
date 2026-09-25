const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
const source=fs.readFileSync(path.join(__dirname,'hosting_connector.js'),'utf8');
async function run(options={}) {
  const bound={request:{run_id:'run',nonce:'nonce',query:'query',from:'now-15m',to:'now'},deadline:options.expired?0:Date.now()/1000+60,minimum_rows:options.notReady?2:0};
  const count={content:[{type:'text',text:'<METADATA><total_buckets>1</total_buckets></METADATA><TSV_DATA>events\n1</TSV_DATA>'}]};
  const rows=options.tooMany?Array.from({length:101},(_,i)=>({id:String(i)})):[{id:'actual-return',value:options.large?'é'.repeat(300000):'é'}];
  const pages=[{content:[{type:'text',text:'<JSON_DATA>'+JSON.stringify(rows)+'</JSON_DATA>'}]},{content:[{type:'text',text:'<JSON_DATA>[]</JSON_DATA>'}]}];
  let calls=0,published,aggregateCalls=0,searchCalls=0,waits=0;const commands=[],notifications=[];
  const tools={
    exec_command:async args=>{
      commands.push(args.cmd);
      if(args.cmd.includes(' cell ')||args.cmd.includes(' backend-only '))return {session_id:1,output:(options.human?'{}\n{"human_input":{"phase":"open"}}\n':'')+'{"backend_request":"/fresh/request.request.json"}\n'};
      if(args.cmd.startsWith('cat '))return {exit_code:0,output:JSON.stringify(bound)};
      if(args.cmd.includes('workflow.publish(')){
        const encoded=args.cmd.match(/payload='([^']+)'/)[1];published=JSON.parse(Buffer.from(encoded,'base64').toString('utf8'));
        return options.yieldPublication?{session_id:2,output:''}:{exit_code:0,output:'published'};
      }
      throw Error('Unexpected command');
    },
    write_stdin:async ({session_id})=>{waits++;return {exit_code:0,output:session_id===1?'':'publication completed'};},
    mcp__datadog__aggregate_rum_events:async()=>{aggregateCalls++;return count;},
    mcp__datadog__search_datadog_rum_events:async()=>{searchCalls++;if(options.failedPage)throw Error('read failed');return pages[calls++];}
  };
  const result=await new AsyncFunction('tools','notify','root','arm','mode','device','repo','family',source)(tools,value=>notifications.push(value),'/root',options.backendOnly?'backend-only':options.family==='webview_candidate'?'B':'A','automatic','device','/repo',options.family);
  return {published,count,pages,aggregateCalls,searchCalls,waits,result,commands,notifications};
}
test('keeps exact raw count and actual returned pages',async()=>{const r=await run();assert.deepEqual(r.published.count_response,r.count);assert.deepEqual(r.published.pages.map(p=>p.response),r.pages);assert.deepEqual(r.published.pages.map(p=>p.start_at),[0,1]);});
test('failed page retains fulfilled count',async()=>{const r=await run({failedPage:true});assert.deepEqual(r.published.count_response,r.count);assert.match(r.published.error,/read failed/);});
test('expired request sends no backend query',async()=>{const r=await run({expired:true});assert.equal(r.aggregateCalls,0);assert.equal(r.searchCalls,0);assert.match(r.published.error,/Expired/);});
test('excess inventory remains raw evidence and fails',async()=>{const r=await run({tooMany:true});assert.equal(r.published.pages.length,1);assert.match(r.published.error,/bound exceeded/);});
test('waits for yielded publication completion',async()=>{const r=await run({yieldPublication:true});assert.equal(r.waits,2);assert.equal(r.result.exit_code,0);});

test('count readiness retains actual count and avoids unstable pages',async()=>{const r=await run({notReady:true});assert.equal(r.searchCalls,0);assert.deepEqual(r.published.count_response,r.count);assert.deepEqual(r.published.pages,[]);assert.equal(r.published.count_pending,true);});
test('backend-only continuation uses the same response transport',async()=>{const r=await run({backendOnly:true});assert.equal(r.result.exit_code,0);assert.equal(r.searchCalls,2);});

test('WebView shares raw transport and exposes only ready human steps',async()=>{const r=await run({family:'webview',human:true});assert.equal(r.result.exit_code,0);assert.match(r.commands[0],/s2_webview_workflow/);assert.doesNotMatch(r.commands[0],/--mode/);assert.deepEqual(r.notifications,[{human_input:{phase:'open'}}]);assert.deepEqual(r.published.count_response,r.count);});

test('human hosting cell uses the shared exact raw transport',async()=>{const r=await run({family:'hosting_paced',human:true});assert.match(r.commands[0],/s2_hosting_paced_workflow/);assert.doesNotMatch(r.commands[0],/--mode/);assert.deepEqual(r.published.pages.map(p=>p.response),r.pages);assert.equal(r.notifications.length,1);});

test('large raw inventories use stdin without an oversized payload argument',async()=>{const r=await run({large:true});assert.deepEqual(r.published.pages.map(p=>p.response),r.pages);const command=r.commands.find(c=>c.includes('workflow.publish('));assert.match(command,/python3 -B - <</);assert.doesNotMatch(command,/--payload /);});


test('candidate continuation uses shared executor transport and captures stage clocks',async()=>{
  const r=await run({family:'webview_candidate'});
  assert.match(r.commands[0],/s2_webview_candidate\.py' cell/);
  const t=r.published.transport;
  assert.deepEqual(t.stages.map(s=>s.name),['count','page-0','page-1']);
  assert.ok(t.stages.every(s=>t.request_read_at<=s.started_at&&s.started_at<=s.finished_at&&s.finished_at<=t.publication_started_at));
  assert.match(r.commands.find(c=>c.includes('workflow.publish(')),/persistence_finished_at/);
});
test('failed backend call keeps its timing and prior raw response',async()=>{
  const r=await run({failedPage:true});assert.equal(r.published.transport.stages.length,2);
  assert.ok(r.published.transport.stages[1].finished_at);assert.deepEqual(r.published.count_response,r.count);
});
