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

// Export only this fixture's bounded synthetic values, preserving type and absence.
function projectAttributeState(payload, at) {
  const context = at(payload, "context") || {};
  const selected = {};
  for (const [key, value] of Object.entries(context)) {
    if (key.startsWith("exp178_")) selected[key] = value;
  }
  for (const [key, value] of Object.entries(payload)) {
    if (key.startsWith("context.exp178_")) selected[key.slice(8)] = value;
  }
  if (Object.hasOwn(selected, "exp178_nested.value")) {
    if (Object.hasOwn(selected, "exp178_nested")) return {invalid: true};
    selected.exp178_nested = {value: selected["exp178_nested.value"]};
    delete selected["exp178_nested.value"];
  }
  const allowed = new Set(["exp178_shadow", "exp178_process", "exp178_integer", "exp178_flag", "exp178_nested"]);
  if (Object.keys(selected).some(key => !allowed.has(key))) return {invalid: true};
  for (const [key, value] of Object.entries(selected)) {
    const valid = key === "exp178_shadow" ? ["global-v1", "global-v2", "swift-a", "objc-b"].includes(value)
      : key === "exp178_process" ? ["global-v1", "global-v2"].includes(value)
      : key === "exp178_integer" ? Number.isInteger(value) && value === 7
      : key === "exp178_flag" ? value === true
      : value && typeof value === "object" && !Array.isArray(value) &&
        Object.keys(value).length === 1 && ["swift-a", "objc-b"].includes(value.value);
    if (!valid) return {invalid: true};
  }
  return selected;
}

function projectTimingState(payload, at) {
  const timings = {};
  const keys = ["exp179_shared", "exp179_final_a", "exp179_final_b"];
  const raw = at(payload, "view.custom_timings") || {};
  for (const key of keys) {
    const value = at(payload, "view.custom_timings." + key);
    const present = Object.hasOwn(raw, key) || Object.hasOwn(payload, "view.custom_timings." + key) ||
      Object.hasOwn(payload.view || {}, "custom_timings." + key);
    if (value == null && !present) continue;
    if (!Number.isSafeInteger(value) || value <= 0) return {invalid: true};
    timings[key] = value;
  }
  const loading = at(payload, "view.loading_time");
  if (loading != null && (!Number.isSafeInteger(loading) || loading <= 0)) return {invalid: true};
  return {timings, loading};
}


function projectFlagValues(payload, at) {
  const raw = at(payload, "feature_flags");
  if (raw != null && (typeof raw !== "object" || Array.isArray(raw))) return {invalid: true};
  const selected = {};
  for (const [key, value] of Object.entries(raw || {})) {
    if (key.startsWith("exp180_")) selected[key] = value;
  }
  for (const [key, value] of Object.entries(payload)) {
    if (!key.startsWith("feature_flags.exp180_")) continue;
    const name = key.slice("feature_flags.".length);
    if (Object.hasOwn(selected, name)) return {invalid: true};
    selected[name] = value;
  }
  for (const key of ["exp180_shared", "exp180_final_a", "exp180_final_b"]) {
    const fields = ["enabled", "weights"];
    if (fields.some(field => Object.hasOwn(selected, key + "." + field))) {
      if (Object.hasOwn(selected, key) ||
          !fields.every(field => Object.hasOwn(selected, key + "." + field))) return {invalid: true};
      selected[key] = Object.fromEntries(fields.map(field => [field, selected[key + "." + field]]));
      for (const field of fields) delete selected[key + "." + field];
    }
  }
  for (const [key, value] of Object.entries(selected)) {
    if (!["exp180_shared", "exp180_final_a", "exp180_final_b"].includes(key)) return {invalid: true};
    const nested = value && typeof value === "object" && !Array.isArray(value) &&
      Object.keys(value).length === 2 && value.enabled === false &&
      Array.isArray(value.weights) && JSON.stringify(value.weights) === "[2,4]";
    const valid = key === "exp180_shared" ? value === true || value === 7 || value === "B" || nested
      : value === (key === "exp180_final_a" ? "A-final" : "B-final");
    if (!valid) return {invalid: true};
  }
  return selected;
}

function hasPayloadPath(payload, path) {
  const parts = path.split(".");
  let current = payload;
  for (let i = 0; i < parts.length; i++) {
    if (current == null || typeof current !== "object") return false;
    if (Object.hasOwn(current, parts.slice(i).join("."))) return true;
    current = current[parts[i]];
  }
  return current !== undefined;
}

function hasInternalFlagAttribute(payload) {
  return hasPayloadPath(payload, "context._dd.performance.first_build_complete");
}

function projectFlagState(payload, at) {
  const flags = projectFlagValues(payload, at);
  if (flags.invalid) return {invalid: true};
  const values = ["min", "max", "average"].map(key => at(payload, "view.flutter_build_time." + key));
  let build = null;
  if (hasPayloadPath(payload, "view.flutter_build_time") ||
      ["min", "max", "average"].some(key => hasPayloadPath(payload, "view.flutter_build_time." + key))) {
    if (!values.every(value => typeof value === "number" && Number.isFinite(value) && value > 0)) return {invalid: true};
    build = Object.fromEntries(["min", "max", "average"].map((key, i) => [key, values[i]]));
  }
  const fbc = at(payload, "view.performance.fbc.timestamp");
  if (hasPayloadPath(payload, "view.performance.fbc.timestamp") && (!Number.isSafeInteger(fbc) || fbc <= 0)) return {invalid: true};
  return {flags, build, fbc, leakedInternalAttribute: hasInternalFlagAttribute(payload)};
}

async function runAcceptance({tools, notify, device, repo, scenario}) {
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
  const setup = await run("python3 - <<'PY'\nimport tempfile,json\nfrom pathlib import Path\np=Path(tempfile.mkdtemp(prefix='multi-scene-acceptance-'))/'run'\nprint(json.dumps({'output':str(p)}))\nPY");
  if (setup.exit_code !== 0) throw Error(setup.output);
  const output = JSON.parse(setup.output).output;
  const execution = await start("python3 tools/multi-scene/acceptance/acceptance.py --device " +
    shellQuote(device) + " --output " + shellQuote(output) + " --repo " + shellQuote(repo) +
    (scenario ? " --scenario " + shellQuote(scenario) : "") +
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
      if (request.kind === "flag_views") return {...base, name:at(payload, "view.name"),
        flag_state:projectFlagState(payload, at)};
      if (request.kind === "flag_errors") {
        const phase = at(payload, "context.probe.phase");
        return {...base, phase, event_id:at(payload, "error.id"),
          source_scene:at(payload, "context.probe.source_scene"),
          error_source:at(payload, "error.source"), error_type:at(payload, "error.type"),
          is_crash:at(payload, "error.is_crash"), payload_matches:at(payload, "error.message") === phase,
          flags:projectFlagValues(payload, at), leaked_internal_attribute:hasInternalFlagAttribute(payload)};
      }
      if (request.kind === "timing_views") return {...base, name:at(payload, "view.name"),
        timing_state:projectTimingState(payload, at)};
      if (request.kind === "timing_errors") {
        const phase = at(payload, "context.probe.phase");
        return {...base, phase, event_id:at(payload, "error.id"),
          source_scene:at(payload, "context.probe.source_scene"),
          error_source:at(payload, "error.source"), error_type:at(payload, "error.type"),
          is_crash:at(payload, "error.is_crash"), payload_matches:at(payload, "error.message") === phase};
      }
      if (request.kind === "attribute_errors") {
        const phase = at(payload, "context.probe.phase");
        return {...base, phase, event_id:at(payload, "error.id"),
          source_scene:at(payload, "context.probe.source_scene"),
          error_source:at(payload, "error.source"), error_type:at(payload, "error.type"),
          is_crash:at(payload, "error.is_crash"), attribute_state:projectAttributeState(payload, at),
          payload_matches:at(payload, "error.message") === phase};
      }
      if (request.kind === "current_errors") {
        const phase = at(payload,"context.probe.phase");
        const ids = at(payload,"action.id");
        const stack = at(payload,"error.stack");
        const stackMatches = phase === "error-swift-message" ? stack === "Exp177.swift:177" :
          phase === "error-objc-message" ? stack === "exp177 stack" : true;
        return {...base, phase, event_id:at(payload,"error.id"), source_scene:at(payload,"context.probe.source_scene"),
          action_ids:Array.isArray(ids) ? ids : ids == null ? [] : [ids],
          error_source:at(payload,"error.source"), error_type:at(payload,"error.type"),
          is_crash:at(payload,"error.is_crash"), url:at(payload,"error.resource.url"), status:at(payload,"error.resource.status_code"),
          payload_matches:at(payload,"error.message") === phase && stackMatches};
      }
      if (request.kind === "resources" || request.kind === "resource_errors") {
        const error = request.kind === "resource_errors";
        const path = error ? "error.resource" : "resource";
        const completion = {...base, phase:at(payload,"context.probe.phase"), kind:error ? "error" : "resource",
          event_id:at(payload,error ? "error.id" : "resource.id"),
          source_scene:at(payload,"context.probe.source_scene"),
          url:at(payload,path + ".url"), status:at(payload,path + ".status_code"),
          action_ids:at(payload,"action.id")};
        return error ? {...completion, error_source:at(payload,"error.source"), is_crash:at(payload,"error.is_crash")} :
          {...completion, method:at(payload,"resource.method"), duration_ns:at(payload,"resource.duration"),
           size:at(payload,"resource.size"), encoded_size:at(payload,"resource.encoded_body_size")};
      }
      if (request.kind === "peer_actions") return {...base, phase:at(payload,"context.probe.phase"),
        action_id:at(payload,"action.id"), target:at(payload,"action.target.name"),
        resource_count:at(payload,"action.resource.count"), error_count:at(payload,"action.error.count")};
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
        if (count >= request.expected_count) break;
        await pause(10000);
      } while (Date.now()<deadline);
      if (request.kind === "auth") data = {authenticated:true, count};
      else if (request.kind === "errors" || request.kind === "crashes") data = {count};
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
return runAcceptance({tools, notify, device, repo, scenario: typeof scenario === "undefined" ? undefined : scenario});
