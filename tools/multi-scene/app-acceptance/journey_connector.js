// Function body for the existing tool orchestrator: tools, requestPath, repo.
// Only exchanges one published backend request. Never launches or controls an app.
const quote = value => "'" + String(value).replaceAll("'", "'\\''") + "'";
const script = repo + '/tools/multi-scene/app-acceptance/journey_transport.py';
const bytes = value => Array.from(unescape(encodeURIComponent(value)), c => c.charCodeAt(0));
function base64(value) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'; let result = '';
  for (let i = 0; i < value.length; i += 3) {
    const word = (value[i] << 16) | ((value[i+1] || 0) << 8) | (value[i+2] || 0);
    result += alphabet[word >>> 18 & 63] + alphabet[word >>> 12 & 63] +
      (i+1 < value.length ? alphabet[word >>> 6 & 63] : '=') + (i+2 < value.length ? alphabet[word & 63] : '=');
  }
  return result;
}
function sha256(value) {
  const constants = [0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
  const hash = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
  const input = value.slice(), bits = value.length * 8; input.push(0x80);
  while (input.length % 64 !== 56) input.push(0);
  for (let n = 7; n >= 0; n--) input.push(Math.floor(bits / 2 ** (n*8)) & 255);
  const rotate = (x,n) => x >>> n | x << (32-n);
  for (let offset=0; offset<input.length; offset+=64) {
    const words = new Int32Array(64);
    for(let n=0;n<16;n++) words[n] = input[offset+n*4]<<24 | input[offset+n*4+1]<<16 | input[offset+n*4+2]<<8 | input[offset+n*4+3];
    for(let n=16;n<64;n++) {
      const a=words[n-15],b=words[n-2];
      words[n]=(words[n-16]+(rotate(a,7)^rotate(a,18)^a>>>3)+words[n-7]+(rotate(b,17)^rotate(b,19)^b>>>10))|0;
    }
    let [a,b,c,d,e,f,g,h] = hash;
    for(let n=0;n<64;n++) {
      const t1=(h+(rotate(e,6)^rotate(e,11)^rotate(e,25))+((e&f)^(~e&g))+constants[n]+words[n])|0;
      const t2=((rotate(a,2)^rotate(a,13)^rotate(a,22))+((a&b)^(a&c)^(b&c)))|0;
      h=g;g=f;f=e;e=(d+t1)|0;d=c;c=b;b=a;a=(t1+t2)|0;
    }
    [a,b,c,d,e,f,g,h].forEach((v,i)=>hash[i]=(hash[i]+v)|0);
  }
  return hash.map(v=>(v>>>0).toString(16).padStart(8,'0')).join('');
}
async function shell(cmd, mutation=false) {
  let result = await tools.exec_command({cmd, login:false, yield_time_ms:1000, max_output_tokens:2500,
    ...(mutation ? {sandbox_permissions:'require_escalated', justification:'Preserve and validate this actual controlled-session backend response under its original frozen deadline.'} : {})});
  let output = result.output || '';
  while(result.exit_code === undefined && result.session_id !== undefined) {
    result=await tools.write_stdin({session_id:result.session_id,chars:'',yield_time_ms:1000,max_output_tokens:2500});
    output+=result.output||'';
  }
  if(result.exit_code !== 0) throw Error('Backend evidence helper failed; raw parts retained');
  return JSON.parse(output);
}
async function persist(label, raw) {
  const payload=bytes(JSON.stringify(raw));
  if(payload.length>2097152) throw Error('Single tool response exceeds frozen limit');
  const parts=Math.ceil(payload.length/49152);
  for(let first=0;first<parts;first+=8) {
    const results=await Promise.allSettled(Array.from({length:Math.min(8,parts-first)},(_,n)=> {
      const i=first+n;
      return shell('python3 -B '+quote(script)+' part --request '+quote(requestPath)+' --label '+quote(label)+
        ' --index '+i+' --payload '+quote(base64(payload.slice(i*49152,(i+1)*49152))),true);
    }));
    const failures=results.filter(result=>result.status==='rejected');
    if(failures.length) throw Error('Response part retention failed; all completed siblings retained; no seal');
  }
  return await shell('python3 -B '+quote(script)+' seal --request '+quote(requestPath)+' --label '+quote(label)+
    ' --parts '+parts+' --sha256 '+quote(sha256(payload)),true);
}
const bound=await shell('cat '+quote(requestPath)), request=bound.request;
if(bound.schema_version!==1||bound.row_limit!==2000||bound.page_limit!==41||Date.now()/1000>=bound.deadline)
  throw Error('Unqualified or expired F08 request');
const count=await persist('count',await tools.mcp__datadog__aggregate_rum_events({query:request.query,from:request.from,to:request.to,
  computes:[{aggregation:'COUNT',field:'*',output:'events'}],max_tokens:1000,
  telemetry:{intent:'Count the complete controlled app session within its fixed source-bound acceptance interval'}}));
if(!count.pending) {
  let offset=0, complete=false;
  for(let index=0;index<bound.page_limit;index++) {
    if(Date.now()/1000>=bound.deadline) throw Error('Original backend deadline expired');
    const actual=await tools.mcp__datadog__search_datadog_rum_events({query:request.query,from:request.from,to:request.to,
      start_at:offset,detailed_output:true,max_tokens:100000,
      telemetry:{intent:'Retain full native and Browser event payloads and exact ownership for the controlled app journey'}});
    const page=await persist('page'+String(index).padStart(3,'0'),actual);
    if(page.rows===0) {complete=true;break;}
    offset+=page.rows;
    if(offset>bound.row_limit) throw Error('Original inventory bound exceeded');
  }
  if(!complete) throw Error('Required empty terminal page not captured');
}
return await shell('python3 -B '+quote(script)+' finish --request '+quote(requestPath),true);
