// Execute through the local tool orchestrator, passing {tools, notify, device, repo}.
// The Python runner owns state; this bridge supplies authenticated source data.
async function execToCompletion(tools, args) {
  let result = await tools.exec_command(args);
  let output = result.output || "";
  while (result.exit_code === undefined && result.session_id !== undefined) {
    result = await tools.write_stdin({session_id: result.session_id, chars: "",
      yield_time_ms: 1000, max_output_tokens: args.max_output_tokens});
    output += result.output || "";
  }
  if (result.exit_code === undefined) throw Error("Helper returned neither completion nor a session");
  return {...result, output};
}

async function runAcceptance({tools, notify, device, repo}) {
  if (!repo || !device) throw Error("Explicit repository path and freshly resolved simulator UUID required");
  const shellQuote = value => "'" + value.replaceAll("'", "'\\''") + "'";
  const start = async (cmd, max_output_tokens = 1500) => tools.exec_command({
    cmd, workdir: repo, sandbox_permissions: "require_escalated",
    justification: "Run the authorized multi-scene acceptance workflow and exchange sanitized backend evidence.",
    yield_time_ms: 1000, max_output_tokens
  });
  const run = async (cmd, max_output_tokens = 1500) => execToCompletion(tools, {
    cmd, workdir: repo, sandbox_permissions: "require_escalated",
    justification: "Collect complete helper output for the authorized acceptance workflow.",
    yield_time_ms: 1000, max_output_tokens
  });
  const setup = await run("python3 - <<'PY'\nimport tempfile,json\nfrom pathlib import Path\np=Path(tempfile.mkdtemp(prefix='exp161-acceptance-'))/'run'\nprint(json.dumps({'output':str(p)}))\nPY");
  if (setup.exit_code !== 0) throw Error(setup.output);
  const output = JSON.parse(setup.output).output;
  const execution = await start("python3 tools/multi-scene/acceptance/acceptance.py --device " +
    shellQuote(device) + " --output " + shellQuote(output) + " --repo " + shellQuote(repo) +
    " --durable-output " + shellQuote(repo + "/DatadogRUM/MultiSceneSupport/Results/acceptance"), 1000);
  notify({acceptance_output: output, execution_session: execution.session_id});
  if (!execution.session_id) return execution;
  const handled = new Set();
  const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
  const textContent = result => (result.content || []).filter(c => c.type === "text").map(c => c.text).join("\n");
  const aggregate = async query => {
    const result = await tools.mcp__codex_apps__datadog__preview__datadog_preview_aggregate_rum_events({
      computes: [{aggregation:"COUNT",field:"*",output:"events"}],
      query, from:"now-2h", to:"now", max_tokens:1000,
      telemetry:{intent:"Validate exact run inventory for automated multi-scene acceptance."}
    });
    if (result.isError) throw Error("Datadog aggregate failed");
    const text = textContent(result);
    const tsv = text.match(/<TSV_DATA>\s*([\s\S]*?)\s*<\/TSV_DATA>/);
    if (!tsv) throw Error("Missing aggregate data");
    const lines = tsv[1].trim().split("\n").filter(Boolean);
    if (lines.length === 1 && /<total_buckets>0<\/total_buckets>/.test(text)) return 0;
    const count = Number(lines.at(-1).split("\t").at(-1));
    if (!Number.isInteger(count) || count < 0) throw Error("Malformed aggregate count");
    return count;
  };
  const at = (obj, path) => {
    const parts = path.split(".");
    let current = obj;
    for (let i=0; i<parts.length; i++) {
      if (current == null) return null;
      const remaining = parts.slice(i).join(".");
      if (Object.prototype.hasOwnProperty.call(current, remaining)) return current[remaining];
      current = current[parts[i]];
    }
    return current ?? null;
  };
  const rows = async (request, total) => {
    let all = [];
    while (all.length < total) {
      const result = await tools.mcp__codex_apps__datadog__preview__datadog_preview_search_datadog_rum_events({
        query:request.query, from:request.from, to:"now", detailed_output:true,
        start_at:all.length, max_tokens:20000,
        telemetry:{intent:"Retrieve exact owners and stop metadata for the automated acceptance oracle."}
      });
      if (result.isError) throw Error("Datadog search failed");
      const json = textContent(result).match(/<JSON_DATA>\s*([\s\S]*?)\s*<\/JSON_DATA>/);
      if (!json) throw Error("Missing detailed backend rows");
      const page = JSON.parse(json[1]);
      if (!Array.isArray(page) || page.length === 0) throw Error("Incomplete backend pagination");
      all.push(...page);
      if (all.length > 100) throw Error("Unexpected large result for bounded acceptance query");
    }
    if (all.length !== total || new Set(all.map(r=>r.id)).size !== total) throw Error("Backend count/pagination mismatch");
    return all.map(row => {
      const payload = row.attributes?.custom || row.custom || row.attributes || row;
      const base = {run_id:at(payload,"context.probe.run_id"),
                    session_id:at(payload,"session.id"), view_id:at(payload,"view.id")};
      if (request.kind === "views") return {...base, name:at(payload,"view.name")};
      return {...base, phase:at(payload,"context.probe.phase"),
        action_id:at(payload,"action.id"), target:at(payload,"action.target.name"),
        source_scene:at(payload,"context.probe.source_scene"),
        uptime:at(payload,"context.probe.uptime"), duration_ns:at(payload,"action.loading_time")};
    });
  };
  for (;;) {
    const listing = await run("python3 - " + shellQuote(output) + " <<'PY'\nimport json,sys\nfrom pathlib import Path\np=Path(sys.argv[1])\nrequests=[]\nfor f in sorted((p/'bridge').glob('*.request.json')):\n if not f.with_name(f.name.replace('.request.json','.response.json')).exists():\n  requests.append({'path':str(f),'request':json.loads(f.read_text())})\nprint(json.dumps({'requests':requests,'state':json.loads((p/'summary.json').read_text())['state']}))\nPY", 3500);
    if (listing.exit_code !== 0) throw Error(listing.output);
    const pending = JSON.parse(listing.output);
    for (const item of pending.requests) {
      const request = item.request;
      if (handled.has(request.request_id)) continue;
      let data;
      const deadline = Date.now()+240000;
      let count;
      do {
        count = await aggregate(request.query);
        if (request.kind === "auth" || request.kind === "errors" ||
            count >= (request.kind === "actions" ? 7 : 3)) break;
        await pause(10000);
      } while (Date.now()<deadline);
      if (request.kind === "auth") data = {authenticated:true, count};
      else if (request.kind === "errors") data = {count};
      else data = await rows(request, count);
      // Digest is calculated by the same canonical encoder as the runner.
      const payload = JSON.stringify({provider:"datadog-mcp",ok:true,complete:true,
                                      query:request.query,data});
      const write = await run("python3 - " + shellQuote(item.path) + " " + shellQuote(payload) +
        " <<'PY'\nimport hashlib,json,sys\nfrom pathlib import Path\np=Path(sys.argv[1]);request=json.loads(p.read_text());response=json.loads(sys.argv[2])\nresponse['request_id']=request['request_id']\nresponse['request_sha256']=hashlib.sha256(json.dumps(request,sort_keys=True,separators=(',',':')).encode()).hexdigest()\nout=p.with_name(p.name.replace('.request.json','.response.json'))\ntmp=out.with_suffix('.writing');tmp.write_text(json.dumps(response,indent=2)+'\\n');tmp.replace(out)\nprint(json.dumps({'fulfilled':request['kind'],'rows':len(response['data']) if isinstance(response['data'],list) else None}))\nPY", 1000);
      if (write.exit_code !== 0) throw Error(write.output);
      handled.add(request.request_id);
      notify(JSON.parse(write.output));
    }
    const progress = await tools.write_stdin({session_id:execution.session_id,chars:"",yield_time_ms:1000,max_output_tokens:1500});
    if (progress.output) notify(progress.output);
    if (progress.exit_code !== undefined) {
      const result = await run("python3 - " + shellQuote(output) +
        " <<'PY'\nfrom pathlib import Path\nimport sys\nprint((Path(sys.argv[1])/'summary.json').read_text())\nPY",5000);
      notify(result.output);
      return {output, exit_code:progress.exit_code};
    }
    await pause(1000);
  }
}
return runAcceptance({tools, notify, device, repo});
