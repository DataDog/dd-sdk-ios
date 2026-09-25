const fs=require('fs'),assert=require('assert'),crypto=require('crypto');
const source=fs.readFileSync(__dirname+'/journey_connector.js','utf8');
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const connect=new AsyncFunction('tools','requestPath','repo',source);
async function run(options={}) {
  const request={run_id:'run',nonce:'nonce',query:'q',from:'2026-09-22T20:00:00Z',to:'2026-09-22T21:00:00Z'};
  const parts={},returns={},queries=[],commands=[];let calls=0,active=0,maxActive=0;
  const raw={content:[{type:'text',text:'Actual ☀ returned data '+(options.large?'x'.repeat(700000):'')}]};
  const reply=value=>({exit_code:0,output:JSON.stringify(value)});
  const tools={
    exec_command:async a=>{
      commands.push(a.cmd);
      if(a.cmd.startsWith('cat '))return reply({schema_version:1,row_limit:2000,page_limit:41,deadline:Date.now()/1000+60,request});
      const label=/--label '([^']+)'/.exec(a.cmd)?.[1];
      if(a.cmd.includes(' part ')) {
        const index=Number(/--index (\d+)/.exec(a.cmd)[1]);
        (parts[label]??=[])[index]=Buffer.from(/--payload '([^']+)'/.exec(a.cmd)[1],'base64');
        active++;maxActive=Math.max(active,maxActive);
        await new Promise(resolve=>setTimeout(resolve,9-index%8));active--;
        if(options.failPart && index===0) return {exit_code:1,output:'retained'};
        return reply({state:'RESPONSE_PART_RETAINED'});
      }
      if(a.cmd.includes(' seal ')) {
        assert.equal(active,0);
        const actual=Buffer.concat(parts[label]);assert.equal(crypto.createHash('sha256').update(actual).digest('hex'),/--sha256 '([^']+)'/.exec(a.cmd)[1]);
        assert.deepStrictEqual(JSON.parse(actual),returns[label]);
        return reply(label==='count'?{state:'COUNT_CAPTURED',pending:!!options.pending}:{state:'PAGE_CAPTURED',rows:label==='page000'?1:0,total:1});
      }
      if(a.cmd.includes(' finish '))return reply({state:options.pending?'PENDING':'COMPLETE_INVENTORY'});
      throw Error('Unexpected command');
    },
    mcp__datadog__aggregate_rum_events:async args=>{queries.push(args);returns.count=raw;return raw;},
    mcp__datadog__search_datadog_rum_events:async args=>{queries.push(args);const label='page'+String(calls++).padStart(3,'0');returns[label]=raw;return raw;}
  };
  let result;
  try { result=await connect(tools,'/prepared/request.json','/repo'); }
  catch(error) { error.observed={active,maxActive,parts,commands};throw error; }
  assert(queries.every(q=>q.from===request.from&&q.to===request.to));
  assert(commands.filter(x=>x.includes(' --payload ')).every(x=>x.length<70000));
  assert(queries.filter(q=>'detailed_output' in q).every(q=>q.max_tokens===100000));
  return {result,calls,parts,commands,maxActive};
}
(async()=>{
  let result=await run();assert.equal(result.result.state,'COMPLETE_INVENTORY');assert.equal(result.calls,2);
  result=await run({large:true});assert(result.parts.count.length>8);assert.equal(result.maxActive,8);
  result=await run({pending:true});assert.equal(result.result.state,'PENDING');assert.equal(result.calls,0);
  await assert.rejects(run({large:true,failPart:true}),error=>{
    assert.match(error.message,/part retention failed/);assert.equal(error.observed.active,0);
    assert.equal(error.observed.parts.count.filter(Boolean).length,8);
    assert(!error.observed.commands.some(c=>c.includes(' seal ')||c.includes(' finish ')));return true;
  });
  console.log('PASS 4 connector controls: exact Unicode/large hashes, bounded parallel parts, fixed interval/terminal page, pending and failed publication preserve all siblings');
})().catch(error=>{console.error(error);process.exitCode=1;});
