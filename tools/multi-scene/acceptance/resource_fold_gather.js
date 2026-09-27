// Inserted into the reviewed connector closure; all attempts share the request clock.
  const gather = async (request, requestPath) => {
    const root=output+"/backend-"+request.request_id;
    const apm=request.kind.startsWith("span-"),budget=apm?600000:115000;
    const gatherStarted=request.gather_started_ms,deadline=gatherStarted+budget;
    if(!Number.isSafeInteger(gatherStarted)||gatherStarted>Date.now())throw Error("Invalid original request clock");
    const check=()=>{if(Date.now()>=deadline)throw Error("Backend exchange exceeded phase bound");};
    const responsePath=requestPath.replace(/\.request\.json$/,".response.json");
    const minimum=request.kind==="rum-startup"?3:request.kind==="rum-session"?12:10;
    for(let attempt=0;attempt<20;attempt++){
      check();const base=root+"/inventory-"+String(attempt).padStart(3,"0");
      const retain=(raw,prefix,kind,started,finished)=>ingest({raw_envelope:raw,
        raw_path:prefix+(kind==="aggregate"?".raw.json":".raw"),decoded_path:prefix+".json",kind,
        request_path:requestPath,gather_started_ms:gatherStarted,deadline_ms:deadline,
        mcp_started_ms:started,mcp_finished_ms:finished});
      const countAt=async label=>{
        check();const started=Date.now();
        const raw=await(apm?tools.mcp__datadog__aggregate_spans:tools.mcp__datadog__aggregate_rum_events)({
          query:request.query,from:request.from,to:request.to,computes:[{aggregation:"COUNT",field:"*",output:"events"}],
          max_tokens:1000,telemetry:{intent:"Count the complete synthetic inventory within the original request clock."}});
        const result=await retain(raw,base+"/"+label,"aggregate",started,Date.now());check();return result.count;
      };
      const count=await countAt("aggregate"),traces=new Set();
      let received=0,cursor=null,page=0,inconsistent=count<minimum;
      while(!inconsistent&&received<count){
        check();const started=Date.now();
        const args={query:request.query,from:request.from,to:request.to,max_tokens:20000,
          telemetry:{intent:"Retrieve complete session or service rows without expected-owner filters."}};
        const raw=await(apm?tools.mcp__datadog__search_datadog_spans({...args,limit:100,...(cursor?{cursor}:{}),custom_attributes:["probe.*","duration","http.*","_dd.*"]})
          :tools.mcp__datadog__search_datadog_rum_events({...args,start_at:received,detailed_output:true}));
        const meta=await retain(raw,base+"/page-"+String(page).padStart(3,"0"),apm?"span":"rum",started,Date.now());check();
        if(meta.is_truncated==="true")throw Error("Truncated page");
        if(!Number.isSafeInteger(meta.row_count)||meta.row_count<0)throw Error("Invalid page count");
        received+=meta.row_count;for(const trace of meta.trace_ids)traces.add(trace);
        inconsistent=meta.row_count===0||received>count;
        if(apm){
          cursor=meta.next_cursor;
          if(received<count&&!cursor)inconsistent=true;
          if(received===count&&(cursor||meta.has_more==="true"))inconsistent=true;
        }
        if(++page>100)throw Error("Unbounded pagination");
      }
      if(!inconsistent)inconsistent=(await countAt("aggregate-after"))!==count;
      if(inconsistent){
        await saveMany([[base+"/inventory-status.json",{state:"INDEXING_CHANGED",count,received,gather_started_ms:gatherStarted,deadline_ms:deadline}]]);
        check();if(Date.now()+3000>=deadline)throw Error("Incomplete backend inventory at original deadline");
        await new Promise(resolve=>setTimeout(resolve,3000));continue;
      }
      const countPath=base+"/aggregate.json";
      if(!apm){
        // The original strict assembler checks duplicate IDs, pagination, exact
        // envelopes and request identity. No inconsistent attempt may publish.
        const args=" assemble --request "+quote(requestPath)+" --count "+quote(countPath)+" --pages "+quote(base)
          +" --output "+quote(responsePath)+" --gather-started-ms "+gatherStarted+" --deadline-ms "+deadline+adapterPins;
        const result=JSON.parse(await shell("python3 -B "+quote(host+"/backend_adapter.py")+args,true));
        if(result.published!==true||result.count!==count)throw Error("Incomplete RUM publication");
      }else{
        check();const details=await Promise.allSettled([...traces].map(async trace_id=>{
          const started=Date.now();const raw=await tools.mcp__datadog__get_datadog_trace({trace_id,only_service_entry_spans:false,
            max_tokens:20000,extra_fields:["_dd.*","probe.*","http.*","span.kind"],telemetry:{intent:"Verify complete trace ownership."}});
          return{trace_id,raw,started,finished:Date.now()};
        }));
        const payloads=[],errors=[];
        for(const item of details){
          if(item.status!=="fulfilled"){errors.push(String(item.reason));continue;}
          const {trace_id,raw,started,finished}=item.value,prefix=base+"/detail-"+trace_id;
          payloads.push({raw_envelope:raw,raw_path:prefix+".raw",decoded_path:prefix+".json",kind:"detail",request_path:requestPath,
            gather_started_ms:gatherStarted,deadline_ms:deadline,mcp_started_ms:started,mcp_finished_ms:finished});
        }
        const bundle={payloads,request_path:requestPath,count_path:countPath,pages_path:base,response_path:responsePath,
          gather_started_ms:gatherStarted,deadline_ms:deadline,publish:errors.length===0};
        let result;
        if(payloads.length)result=JSON.parse(await shell("python3 -B "+quote(host+"/backend_adapter.py")+" ingest-details --payload-json "+quote(JSON.stringify(bundle))+adapterPins,true));
        if(errors.length||!result||result.published!==true||result.count!==count||result.retained_details!==traces.size)
          throw Error("Incomplete trace detail publication: "+errors.join("; "));
      }
      notify({stage:"backend inventory retained",kind:request.kind,count,request_id:request.request_id,attempt});return;
    }
    throw Error("Backend inventory attempt bound reached without a complete result");
  };
