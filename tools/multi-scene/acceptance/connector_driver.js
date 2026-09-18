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

function projectTraceRow(row, details, at) {
  const exactText = (value, label) => {
    if (typeof value !== "string" || !value) throw Error("Missing exact " + label);
    return value;
  };
  const decimalID = value => {
    if (typeof value !== "string" || !/^(0|[1-9][0-9]*)$/.test(value)) throw Error("Malformed decimal span identity");
    const number = BigInt(value);
    if (number > 0xffffffffffffffffn) throw Error("Span identity exceeds UInt64");
    return number.toString(16).padStart(16, "0");
  };
  const traceID = exactText(row.traceid, "trace identity");
  if (!/^[0-9a-f]{32}$/.test(traceID) || /^0+$/.test(traceID)) throw Error("Malformed full trace identity");
  const spanID = decimalID(row.spanid);
  if (/^0+$/.test(spanID)) throw Error("Zero span identity");
  if (!Array.isArray(details) || details.length !== 1) throw Error("Unexpected root trace detail inventory");
  const detail = details[0];
  const meta = name => at(detail, "meta." + name);
  if (decimalID(detail.span_id) !== spanID || decimalID(detail.parent_id) !== decimalID(row.parentid) ||
      meta("_dd.p.ftid") !== traceID) throw Error("Search/detail identity mismatch");
  const operation = exactText(row.operationname, "span operation");
  const resource = exactText(row.resourcename, "span resource");
  if (detail.name !== operation || detail.resource !== resource || detail.service !== row.service) {
    throw Error("Search/detail payload mismatch");
  }
  const runID = exactText(at(row, "custom.probe.run_id"), "run identity");
  if (meta("probe.run_id") !== runID) throw Error("Search/detail run mismatch");
  const duration = at(row, "custom.duration");
  if (!Number.isSafeInteger(duration) || duration <= 0) throw Error("Missing exact nanosecond span duration");
  if (row.status !== "ok" && row.status !== "error") throw Error("Missing span status");
  const httpURL = operation === "urlsession.request" ? exactText(at(row, "custom.http.url"), "original HTTP URL") : null;
  if (httpURL !== null && meta("http.url") !== httpURL) throw Error("Search/detail URL mismatch");
  const phase = operation === "urlsession.request" ? httpURL.split("/").at(-1) :
    /^exp181\.(native|otel)_(a|b|fallback)$/.test(operation) ? operation.slice(7).replace("_", "-") : null;
  if (!phase) throw Error("Undeclared span operation");
  const action = meta("_dd.action.id");
  if (action !== null && (typeof action !== "string" || !action)) throw Error("Malformed captured action");
  return {phase, trace_id:traceID, span_id:spanID, parent_id:decimalID(row.parentid),
    run_id:runID, application_id:exactText(meta("_dd.application.id"), "RUM application"),
    session_id:exactText(meta("_dd.session.id"), "RUM session"),
    view_id:exactText(meta("_dd.view.id"), "RUM view"), action_ids:action === null ? [] : [action],
    operation, resource, http_url:httpURL, service:exactText(row.service, "service"),
    duration_ns:duration, is_error:row.status === "error"};
}


async function collectTraceDetails(rows, fetchTrace, decodePages, at) {
  for (const row of rows) {
    if (typeof row.traceid !== "string" || !/^[0-9a-f]{32}$/.test(row.traceid)) throw Error("Invalid search trace identity");
  }
  const results = await Promise.allSettled(rows.map(row => fetchTrace(row.traceid)));
  if (results.some(result => result.status !== "fulfilled")) throw Error("Incomplete trace detail reads");
  const pages = await decodePages(results.map(result => result.value));
  if (pages.length !== rows.length) throw Error("Incomplete trace detail decoding");
  return rows.map((row, index) => projectTraceRow(row, pages[index], at));
}


function parseLogCount(body) {
  const match = body.match(/<TSV_DATA>\s*([\s\S]*?)\s*<\/TSV_DATA>/);
  if (!match) throw Error("Missing Logs aggregate data");
  const lines = match[1].trim().split("\n");
  if (lines.length !== 2 || lines[0].trim() !== "events" || !/^\d+$/.test(lines[1].trim())) {
    throw Error("Malformed Logs aggregate count");
  }
  const count = Number(lines[1].trim());
  if (!Number.isSafeInteger(count) || count > 100) throw Error("Unbounded Logs inventory");
  return count;
}

const logGroupColumns = {
  run_id:"@probe.run_id", phase:"@probe.phase", application_id:"@application_id",
  session_id:"@session_id", view_id:"@view.id", action_id:"@user_action.id",
  source_scene:"@probe.source_scene", service:"service", status:"status", message:"message"
};

function parseLogGroups(body) {
  const match = body.match(/<TSV_DATA>\s*([\s\S]*?)\s*<\/TSV_DATA>/);
  if (!match) throw Error("Missing Logs grouped data");
  const lines = match[1].trim().split("\n");
  const keys = [...Object.keys(logGroupColumns), "events"];
  if (lines.shift() !== keys.join("\t")) throw Error("Malformed Logs group columns");
  for (const [name, expected] of [["displayed_columns", keys.length], ["displayed_rows", lines.length],
                                 ["total_rows", lines.length]]) {
    const value = body.match(new RegExp("<" + name + ">([0-9]+)</" + name + ">"));
    if (!value || Number(value[1]) !== expected) throw Error("Incomplete Logs grouped inventory");
  }
  if (lines.length > 100) throw Error("Unbounded Logs grouped inventory");
  return lines.map(line => {
    const fields = line.split("\t");
    if (fields.length !== keys.length || fields.some(value => !value) || fields.at(-1) !== "1") {
      throw Error("Malformed or duplicated Logs group");
    }
    return {...Object.fromEntries(keys.map((key, i) => [key, fields[i]])), events:1};
  });
}

function validateLogInventory(total, rows, groups) {
  if (!Number.isSafeInteger(total) || total < 0 || total > 100 ||
      rows.length !== total || groups.length !== total ||
      new Set(rows.map(row => row.phase)).size !== total ||
      new Set(groups.map(row => row.phase)).size !== total) {
    throw Error("Logs count/pagination/group mismatch");
  }
  const ids = rows.map(row => row.log_id).filter(value => value !== null);
  if (new Set(ids).size !== ids.length) throw Error("Duplicate backend log ID");
  for (const row of rows) {
    const group = groups.find(value => value.phase === row.phase);
    if (!group || group.events !== 1 ||
        Object.keys(logGroupColumns).some(key => row[key] !== group[key])) {
      throw Error("Logs raw/group ownership mismatch");
    }
  }
  return {count:total, rows, groups};
}

function logAttribute(row, key) {
  const attributes = row.attributes || {};
  const values = [];
  function collect(object, path) {
    if (object == null || typeof object !== "object") return;
    if (Object.hasOwn(object, path)) values.push(object[path]);
    const dot = path.indexOf(".");
    if (dot !== -1) collect(object[path.slice(0, dot)], path.slice(dot + 1));
  }
  collect(attributes, "custom." + key);
  collect(attributes, "attributes." + key);
  if (values.length > 1) throw Error("Ambiguous Logs attribute: " + key);
  return values.length ? values[0] : null;
}

function hasPrivateMirrorMetadata(payload) {
  const prefix = "_dd.internal.rum.error.";
  function visit(value, path = "") {
    if (value == null || typeof value !== "object") return false;
    return Object.entries(value).some(([key, child]) => {
      const joined = path ? path + "." + key : key;
      return joined.startsWith(prefix) || visit(child, joined);
    });
  }
  return visit(payload);
}

function projectLogRow(row) {
  if (!row || typeof row !== "object") throw Error("Malformed backend log row");
  if (row.id != null && (typeof row.id !== "string" || !row.id)) throw Error("Malformed backend log ID");
  const get = key => logAttribute(row, key);
  const selected = {run_id:get("probe.run_id"), phase:get("probe.phase"),
    application_id:get("application_id"), session_id:get("session_id"), view_id:get("view.id"),
    action_id:get("user_action.id"), source_scene:get("probe.source_scene"),
    service:row.service, status:row.status, message:row.message};
  if (Object.values(selected).some(value => typeof value !== "string" || !value)) {
    throw Error("Missing or malformed selected Logs field");
  }
  const attributes = row.attributes || {};
  selected.log_id = row.id ?? null;
  const privateFlat = Object.keys(attributes).some(key =>
    key.replace(/^(custom|attributes)\./, "").startsWith("_dd.internal.rum.error."));
  selected.leaked_internal_attribute = privateFlat || hasPrivateMirrorMetadata(attributes.custom) ||
    hasPrivateMirrorMetadata(attributes.attributes);
  return selected;
}

function webValue(payload, path) {
  const parts = path.split(".");
  const values = [];
  const walk = (object, remaining) => {
    if (object == null || typeof object !== "object") return;
    for (let i = 1; i <= remaining.length; i++) {
      const key = remaining.slice(0, i).join(".");
      if (!Object.hasOwn(object, key)) continue;
      if (i === remaining.length) values.push(object[key]);
      else walk(object[key], remaining.slice(i));
    }
  };
  walk(payload, parts);
  if (values.length > 1) throw Error("Ambiguous WebView backend field: " + path);
  return {present:values.length === 1, value:values.length ? values[0] : null};
}

function projectWebView(payload, envelope = {}) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) throw Error("Malformed WebView payload");
  const get = path => webValue(payload, path).value;
  const present = path => webValue(payload, path).present;
  const source = get("source");
  const envelopeSource = Object.hasOwn(envelope, "source") ? envelope.source : null;
  if (present("source") && envelopeSource !== null && source !== envelopeSource) {
    throw Error("Conflicting WebView envelope source");
  }
  return {
    run_id:get("context.probe.run_id"), session_id:get("session.id"),
    application_id:get("application.id"), view_id:get("view.id"), name:get("view.name"),
    source:envelopeSource !== null ? envelopeSource : source, phase:get("context.probe.phase"), source_scene:get("context.probe.source_scene"),
    document_id:get("context.probe.document_id"), url:get("view.url"),
    container_id:get("container.view.id"), container_source:get("container.source"),
    container_present:present("container") || present("container.view.id") || present("container.source"),
    leaked_internal_attribute:present("_dd.internal.native_scene_id") || present("context._dd.internal.native_scene_id"),
    has_replay:get("session.has_replay"), is_active:get("view.is_active"),
    action_count:get("view.action.count"), resource_count:get("view.resource.count"),
    error_count:get("view.error.count"), long_task_count:get("view.long_task.count"),
    time_spent:get("view.time_spent"), loading_type:get("view.loading_type"),
    format_version:get("_dd.format_version"), document_version:get("_dd.document_version")
  };
}

function projectFatal(payload, envelope = {}) {
  const get = path => webValue(payload, path).value;
  const common = projectWebView(payload, envelope);
  return {
    run_id:common.run_id, session_id:common.session_id, view_id:common.view_id,
    name:common.name, source:common.source, phase:common.phase,
    container_present:common.container_present, is_active:common.is_active,
    action_count:common.action_count, resource_count:common.resource_count,
    error_count:common.error_count, crash_count:get("view.crash.count"),
    document_version:common.document_version,
    sdk_document_version:get("context.exp184_sdk_document_version"),
    event_id:get("error.id"), error_source:get("error.source"),
    error_type:get("error.type"), is_crash:get("error.is_crash"),
    incident_id:get("error.meta.incident_identifier"), exception_type:get("error.meta.exception_type"),
    crashed_process:get("error.meta.process"),
    action_present:hasPayloadPath(payload, "action") || hasPayloadPath(payload, "action.id")
  };
}

function projectProcess(payload, envelope = {}, kind) {
  if (!["process_views", "process_errors", "process_long_tasks", "process_actions"].includes(kind)) {
    throw Error("Unknown process projection kind");
  }
  const get = path => webValue(payload, path).value;
  const common = projectWebView(payload, envelope);
  const idPath = {process_views:null, process_errors:"error.id",
    process_long_tasks:"long_task.id", process_actions:"action.id"}[kind];
  return {
    run_id:common.run_id, session_id:common.session_id, view_id:common.view_id,
    name:common.name, source:common.source, container_present:common.container_present,
    action_present:hasPayloadPath(payload, "action") || hasPayloadPath(payload, "action.id"),
    event_id:idPath === null ? null : get(idPath),
    duration_ns:kind === "process_long_tasks" ? get("long_task.duration") : get("freeze.duration"),
    error_source:get("error.source"), error_source_type:get("error.source_type"),
    error_type:get("error.type"), error_category:get("error.category"), is_crash:get("error.is_crash"),
    action_type:get("action.type"), action_target:get("action.target.name"),
    view_long_task_count:common.long_task_count, view_error_count:common.error_count,
    view_action_count:common.action_count, view_resource_count:common.resource_count,
    view_crash_count:get("view.crash.count")
  };
}

function projectVitals(payload, envelope = {}) {
  const get = path => webValue(payload, path).value;
  const common = projectWebView(payload, envelope);
  return {
    run_id:common.run_id, session_id:common.session_id, view_id:common.view_id,
    name:common.name, source:common.source, is_active:common.is_active,
    container_present:common.container_present,
    slow_frames_present:webValue(payload, "view.slow_frames").present,
    counters:{
      actions:common.action_count, resources:common.resource_count, errors:common.error_count,
      longTasks:common.long_task_count ?? 0, crashes:get("view.crash.count") ?? 0
    },
    metrics:{
      cpuTicks:get("view.cpu_ticks_count"), cpuRate:get("view.cpu_ticks_per_second"),
      memoryAverage:get("view.memory_average"), memoryMax:get("view.memory_max"),
      refreshRateAverage:get("view.refresh_rate_average"), refreshRateMin:get("view.refresh_rate_min"),
      timeSpentNanoseconds:common.time_spent, slowFrames:get("view.slow_frames"),
      slowFramesRate:get("view.slow_frames_rate")
    }
  };
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
  const read = async (cmd, max_output_tokens = 1500) => execToCompletion(tools, {
    cmd, workdir: repo, yield_time_ms:1000, max_output_tokens
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
  const aggregate = async (query, apm = false) => {
    const aggregateTool = apm ? tools.mcp__codex_apps__datadog__preview__datadog_preview_aggregate_spans
      : tools.mcp__codex_apps__datadog__preview__datadog_preview_aggregate_rum_events;
    const result = await aggregateTool({
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
  const logAggregate = async request => {
    const result = await tools.mcp__codex_apps__datadog__preview__datadog_preview_analyze_datadog_logs({
      filter:request.query, from:request.from, to:"now", sql_query:"SELECT COUNT(*) AS events FROM logs",
      max_tokens:1000, telemetry:{intent:"Count the complete synthetic log run independently of ownership filters."}
    });
    if (result.isError) throw Error("Logs aggregate failed");
    return parseLogCount(textContent(result));
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
      if (request.kind === "vitals_views") return projectVitals(payload, row.attributes || row);
      if (["process_views", "process_errors", "process_long_tasks", "process_actions"].includes(request.kind)) {
        return projectProcess(payload, row.attributes || row, request.kind);
      }
      if (["fatal_views", "fatal_errors"].includes(request.kind)) return projectFatal(payload, row.attributes || row);
      if (request.kind === "webview_views") return projectWebView(payload, row.attributes || row);
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
      if (request.kind === "log_errors") {
        const phase = at(payload, "context.probe.phase");
        const ids = at(payload, "action.id");
        return {...base, phase, event_id:at(payload, "error.id"),
          source_scene:at(payload, "context.probe.source_scene"),
          action_ids:Array.isArray(ids) ? ids : ids == null ? [] : [ids],
          error_source:at(payload, "error.source"), is_crash:at(payload, "error.is_crash"),
          payload_matches:at(payload, "error.message") === phase,
          leaked_internal_attribute:hasPrivateMirrorMetadata(at(payload, "context")) ||
            ["target_view_id", "target_action_id", "target_scene_id", "context_captured"].some(key =>
              hasPayloadPath(payload, "context._dd.internal.rum.error." + key))};
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
  const structuredSpanPages = async responses => {
    const descriptors = responses.map(response => {
      if (response.isError) throw Error("Datadog span query failed");
      const body = textContent(response);
      const yaml = body.match(/<YAML_DATA>\s*([\s\S]*?)\s*<\/YAML_DATA>/);
      const json = body.match(/<JSON_DATA>\s*([\s\S]*?)\s*<\/JSON_DATA>/);
      if (json) return {body, page:JSON.parse(json[1])};
      if (!yaml) throw Error("Missing structured span evidence");
      return {body, yaml:yaml[1]};
    });
    const yaml = descriptors.filter(item => Object.hasOwn(item, "yaml"));
    if (yaml.length) {
      const decoded = await read("ruby tools/multi-scene/acceptance/parse_span_response.rb --batch-json " +
        shellQuote(JSON.stringify(yaml.map(item => item.yaml))), 20000);
      if (decoded.exit_code !== 0) throw Error("Could not safely decode span evidence");
      const pages = JSON.parse(decoded.output);
      if (!Array.isArray(pages) || pages.length !== yaml.length) throw Error("Incomplete span decoding");
      yaml.forEach((item, index) => { item.page = pages[index]; });
    }
    return descriptors;
  };
  const logRows = async (request, total) => {
    const all = [];
    while (all.length < total) {
      const response = await tools.mcp__codex_apps__datadog__preview__datadog_preview_search_datadog_logs({
        query:request.query, from:request.from, to:"now", sort:"timestamp", start_at:all.length, max_tokens:12000,
        extra_fields:["application_id", "session_id", "view.id", "user_action.id", "probe.*", "_dd.internal.rum.error.*"],
        telemetry:{intent:"Bind all synthetic Logs to exact emission owners and mirrored RUM errors."}
      });
      const [{body, page}] = await structuredSpanPages([response]);
      if (!Array.isArray(page) || !page.length) throw Error("Incomplete Logs pagination");
      all.push(...page);
      if (all.length > 100) throw Error("Unexpected large Logs inventory");
      if (all.length < total && body.includes("<has_more>false</has_more>")) throw Error("Incomplete Logs inventory");
    }
    if (all.length !== total) throw Error("Logs count/pagination mismatch");
    return all.map(projectLogRow);
  };
  const logGroups = async request => {
    const columns = Object.entries(logGroupColumns);
    const quoted = value => '"' + value + '"';
    const result = await tools.mcp__codex_apps__datadog__preview__datadog_preview_analyze_datadog_logs({
      filter:request.query, from:request.from, to:"now", max_tokens:6000,
      sql_query:"SELECT " + columns.map(([key, value]) => quoted(value) + " AS " + key).join(", ") +
        ", COUNT(*) AS events FROM logs GROUP BY " + columns.map(([, value]) => quoted(value)).join(", "),
      extra_columns:columns.filter(([, value]) => value.startsWith("@"))
        .map(([, name]) => ({name, type:"varchar"})),
      telemetry:{intent:"Independently verify one log for every exact phase and owner in the complete synthetic run."}
    });
    if (result.isError) throw Error("Logs grouped query failed");
    return parseLogGroups(textContent(result));
  };
  const logEvidence = async (request, count) => {
    const reads = await Promise.allSettled([logRows(request, count), logGroups(request)]);
    if (reads.some(result => result.status !== "fulfilled")) {
      throw Error("Incomplete Logs raw/group reads: " + reads.filter(r => r.status === "rejected")
        .map(r => String(r.reason)).join("; "));
    }
    return validateLogInventory(count, reads[0].value, reads[1].value);
  };
  const spanRows = async (request, total) => {
    const all = [];
    while (all.length < total) {
      const response = await tools.mcp__codex_apps__datadog__preview__datadog_preview_search_datadog_spans({
        query:request.query, from:request.from, to:"now", start_at:all.length, max_tokens:20000,
        custom_attributes:["probe.run_id", "duration", "http.url"],
        telemetry:{intent:"Retrieve complete synthetic Trace inventory with exact captured RUM owners and span identities."}
      });
      const [{body, page}] = await structuredSpanPages([response]);
      if (!Array.isArray(page) || !page.length) throw Error("Incomplete span pagination");
      all.push(...page);
      if (all.length > 100) throw Error("Unexpected large span inventory");
      if (all.length < total && /<has_more>false<\/has_more>/.test(body)) throw Error("Incomplete span inventory");
    }
    const detailStart = Date.now();
    const projected = await collectTraceDetails(all, trace_id =>
      tools.mcp__codex_apps__datadog__preview__datadog_preview_get_datadog_trace({
        trace_id, only_service_entry_spans:false, max_tokens:3500,
        extra_fields:["_dd.application.id", "_dd.session.id", "_dd.view.id", "_dd.action.id",
          "_dd.p.ftid", "probe.run_id"],
        telemetry:{intent:"Bind indexed synthetic spans to exact retained RUM ownership in complete trace details."}
      }), async responses => (await structuredSpanPages(responses)).map(item => item.page), at);
    notify({backend_detail_count:projected.length, elapsed_ms:Date.now() - detailStart});
    if (projected.length !== total || new Set(projected.map(s => s.span_id)).size !== total) {
      throw Error("Span count/pagination mismatch");
    }
    return projected;
  };
  for (;;) {
    const listing = await read("python3 - " + shellQuote(output) + " <<'PY'\nimport json,sys\nfrom pathlib import Path\np=Path(sys.argv[1])\nrequests=[]\nfor f in sorted((p/'bridge').glob('*.request.json')):\n if not f.with_name(f.name.replace('.request.json','.response.json')).exists():\n  requests.append({'path':str(f),'request':json.loads(f.read_text())})\nprint(json.dumps({'requests':requests,'state':json.loads((p/'summary.json').read_text())['state']}))\nPY", 3500);
    if (listing.exit_code !== 0) throw Error(listing.output);
    const pending = JSON.parse(listing.output);
    for (const item of pending.requests) {
      const request = item.request;
      if (handled.has(request.request_id)) continue;
      let data;
      const deadline = Date.now()+240000;
      let count;
      do {
        count = ["log_auth", "logs"].includes(request.kind) ? await logAggregate(request)
          : await aggregate(request.query, ["trace_auth", "trace_spans"].includes(request.kind));
        if (count >= request.expected_count) break;
        await pause(10000);
      } while (Date.now()<deadline);
      if (["auth", "trace_auth", "log_auth"].includes(request.kind)) data = {authenticated:true, count};
      else if (request.kind === "logs") data = await logEvidence(request, count);
      else if (request.kind === "trace_spans") data = await spanRows(request, count);
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
      const result = await read("python3 - " + shellQuote(output) +
        " <<'PY'\nfrom pathlib import Path\nimport sys\nimport json\nd=json.loads((Path(sys.argv[1])/'summary.json').read_text());print(json.dumps({k:d.get(k) for k in ['run_id','state','failures','backend_bridge_timings']}))\nPY",5000);
      notify(result.output);
      return {output, exit_code:progress.exit_code};
    }
    await pause(1000);
  }
}
return runAcceptance({tools, notify, device, repo, scenario: typeof scenario === "undefined" ? undefined : scenario});
