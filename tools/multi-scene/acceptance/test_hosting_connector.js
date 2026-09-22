const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
const source=fs.readFileSync(path.join(__dirname,'hosting_connector.js'),'utf8');
async function run(options={}) {
  const bound={request:{run_id:'run',nonce:'nonce',query:'query',from:'now-15m',to:'now'},deadline:options.expired?0:Date.now()/1000+60};
  const count={content:[{type:'text',text:'raw count preserved'}]};
  const rows=options.tooMany?Array.from({length:101},(_,i)=>({id:String(i)})):[{id:'actual-return',value:'é'}];
  const pages=[{content:[{type:'text',text:'<JSON_DATA>'+JSON.stringify(rows)+'</JSON_DATA>'}]},{content:[{type:'text',text:'<JSON_DATA>[]</JSON_DATA>'}]}];
  let calls=0,published,aggregateCalls=0,searchCalls=0,waits=0;
  const tools={
    exec_command:async args=>{
      if(args.cmd.includes(' cell '))return {session_id:1,output:'{"backend_request":"/fresh/request.request.json"}\n'};
      if(args.cmd.startsWith('cat '))return {exit_code:0,output:JSON.stringify(bound)};
      if(args.cmd.includes(' publish ')){
        const encoded=args.cmd.match(/--payload '([^']+)'/)[1];published=JSON.parse(Buffer.from(encoded,'base64').toString('utf8'));
        return options.yieldPublication?{session_id:2,output:''}:{exit_code:0,output:'published'};
      }
      throw Error('Unexpected command');
    },
    write_stdin:async ({session_id})=>{waits++;return {exit_code:0,output:session_id===1?'':'publication completed'};},
    mcp__datadog__aggregate_rum_events:async()=>{aggregateCalls++;return count;},
    mcp__datadog__search_datadog_rum_events:async()=>{searchCalls++;if(options.failedPage)throw Error('read failed');return pages[calls++];}
  };
  const result=await new AsyncFunction('tools','notify','root','arm','mode','device','repo',source)(tools,()=>{},'/root','A','automatic','device','/repo');
  return {published,count,pages,aggregateCalls,searchCalls,waits,result};
}
test('keeps exact raw count and actual returned pages',async()=>{const r=await run();assert.deepEqual(r.published.count_response,r.count);assert.deepEqual(r.published.pages.map(p=>p.response),r.pages);assert.deepEqual(r.published.pages.map(p=>p.start_at),[0,1]);});
test('failed page retains fulfilled count',async()=>{const r=await run({failedPage:true});assert.deepEqual(r.published.count_response,r.count);assert.match(r.published.error,/read failed/);});
test('expired request sends no backend query',async()=>{const r=await run({expired:true});assert.equal(r.aggregateCalls,0);assert.equal(r.searchCalls,0);assert.match(r.published.error,/Expired/);});
test('excess inventory remains raw evidence and fails',async()=>{const r=await run({tooMany:true});assert.equal(r.published.pages.length,1);assert.match(r.published.error,/bound exceeded/);});
test('waits for yielded publication completion',async()=>{const r=await run({yieldPublication:true});assert.equal(r.waits,2);assert.equal(r.result.exit_code,0);});
