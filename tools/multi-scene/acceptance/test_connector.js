const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const source = fs.readFileSync(path.join(__dirname, 'connector_driver.js'), 'utf8');
const {execToCompletion} = new Function(source.replace(
  'return runAcceptance({tools, notify, device, repo, scenario: typeof scenario === "undefined" ? undefined : scenario});', 'return {execToCompletion};'
))();

test('collects every yielded helper chunk before checking exit code', async () => {
  const polls = [];
  const replies = [
    {session_id: 42, output: '"state":'},
    {exit_code: 0, output: '"RUNNING"}'}
  ];
  const tools = {
    exec_command: async () => ({session_id: 42, output: '{'}),
    write_stdin: async args => { polls.push(args.session_id); return replies.shift(); }
  };
  const result = await execToCompletion(tools, {cmd: 'helper', max_output_tokens: 100});
  assert.equal(result.exit_code, 0);
  assert.deepEqual(JSON.parse(result.output), {state: 'RUNNING'});
  assert.deepEqual(polls, [42, 42]);
});

test('preserves immediate helper failure without polling', async () => {
  const result = await execToCompletion({exec_command: async () => ({exit_code: 7, output: 'failed'})}, {});
  assert.equal(result.exit_code, 7);
  assert.equal(result.output, 'failed');
});

test('rejects missing completion and missing session', async () => {
  await assert.rejects(execToCompletion({exec_command: async () => ({output: ''})}, {}), /neither completion/);
});

const {projectAttributeState} = new Function(source.replace(
  'return runAcceptance({tools, notify, device, repo, scenario: typeof scenario === "undefined" ? undefined : scenario});',
  'return {projectAttributeState};'
))();
const at = (object, key) => object[key] ?? null;
test('attribute projection preserves typed values and exact key absence', () => {
  const context = {exp178_shadow:'swift-a', exp178_process:'global-v1', exp178_integer:7,
    exp178_flag:true, exp178_nested:{value:'swift-a'}, 'probe.run_id':'unit'};
  assert.deepEqual(projectAttributeState({context}, at), {
    exp178_shadow:'swift-a', exp178_process:'global-v1', exp178_integer:7,
    exp178_flag:true, exp178_nested:{value:'swift-a'}
  });
  assert.deepEqual(projectAttributeState({context:{exp178_shadow:'global-v1', exp178_process:'global-v1'}}, at),
    {exp178_shadow:'global-v1', exp178_process:'global-v1'});
});
test('attribute projection normalizes only the known flattened nested key', () => {
  assert.deepEqual(projectAttributeState({context:{'exp178_nested.value':'objc-b'}}, at),
    {exp178_nested:{value:'objc-b'}});
  assert.deepEqual(projectAttributeState({'context.exp178_nested.value':'objc-b'}, at),
    {exp178_nested:{value:'objc-b'}});
});
test('attribute projection rejects wrong types and excludes unbounded values', () => {
  for (const context of [
    {exp178_integer:true}, {exp178_flag:1}, {exp178_integer:'7'},
    {exp178_nested:{value:'objc-b',extra:'private'}}, {exp178_shadow:'private'},
    {exp178_unknown:'private'}, {exp178_nested:null},
    {exp178_nested:{value:'objc-b'}, 'exp178_nested.value':'objc-b'}
  ]) assert.deepEqual(projectAttributeState({context}, at), {invalid:true});
});

const {projectTimingState} = new Function(source.replace(
  'return runAcceptance({tools, notify, device, repo, scenario: typeof scenario === "undefined" ? undefined : scenario});',
  'return {projectTimingState};'
))();
const nestedAt = (object, key) => {
  if (Object.hasOwn(object, key)) return object[key];
  return key.split('.').reduce((value, part) => value?.[part], object) ?? null;
};
test('timing projection keeps integer nanoseconds and initial absence', () => {
  assert.deepEqual(projectTimingState({view:{custom_timings:{exp179_shared:123,exp179_final_a:456},loading_time:300}}, nestedAt),
    {timings:{exp179_shared:123,exp179_final_a:456},loading:300});
  assert.deepEqual(projectTimingState({view:{}}, nestedAt), {timings:{},loading:null});
});
test('timing projection supports full flattened names without type conversion', () => {
  assert.deepEqual(projectTimingState({'view.custom_timings.exp179_shared':123,'view.loading_time':300}, nestedAt),
    {timings:{exp179_shared:123},loading:300});
});
test('timing projection rejects booleans strings nested durations and invalid numbers', () => {
  for (const value of [true, '123', {value:123}, 0, -1, 1.5, Number.MAX_SAFE_INTEGER+1, null]) {
    assert.deepEqual(projectTimingState({view:{custom_timings:{exp179_shared:value}}}, nestedAt), {invalid:true});
  }
  for (const loading_time of [true, '123', 0, -1, 1.5]) {
    assert.deepEqual(projectTimingState({view:{loading_time}}, nestedAt), {invalid:true});
  }
});

const {projectFlagValues, projectFlagState, hasInternalFlagAttribute} = new Function(source.replace(
  'return runAcceptance({tools, notify, device, repo, scenario: typeof scenario === "undefined" ? undefined : scenario});',
  'return {projectFlagValues, projectFlagState, hasInternalFlagAttribute};'
))();
const flagAt = (object, path) => {
  const parts = path.split('.');
  let value = object;
  for (let i = 0; i < parts.length; i++) {
    if (value == null) return null;
    if (Object.hasOwn(value, parts.slice(i).join('.'))) return value[parts.slice(i).join('.')];
    value = value[parts[i]];
  }
  return value ?? null;
};
test('flag projection preserves supported typed replacements and absence', () => {
  for (const value of [true, 7, 'B', {enabled:false,weights:[2,4]}]) {
    assert.deepEqual(projectFlagValues({feature_flags:{exp180_shared:value}}, flagAt), {exp180_shared:value});
  }
  assert.deepEqual(projectFlagState({view:{}}, flagAt),
    {flags:{},build:null,fbc:null,leakedInternalAttribute:false});
});
test('flag projection accepts only declared flattened nested fields', () => {
  for (const payload of [
    {feature_flags:{'exp180_shared.enabled':false,'exp180_shared.weights':[2,4]}},
    {'feature_flags.exp180_shared.enabled':false,'feature_flags.exp180_shared.weights':[2,4]}
  ]) assert.deepEqual(projectFlagValues(payload, flagAt), {exp180_shared:{enabled:false,weights:[2,4]}});
});
test('flag projection rejects type conversion unknown fields and ambiguous nesting', () => {
  for (const feature_flags of [
    {exp180_shared:1}, {exp180_shared:'7'}, {exp180_shared:false}, {exp180_shared:null},
    {exp180_shared:{enabled:0,weights:[2,4]}}, {exp180_shared:{enabled:false,weights:[true,4]}},
    {exp180_shared:{enabled:false,weights:[2,4],extra:'private'}},
    {'exp180_shared.enabled':false}, {exp180_unknown:'private'},
    {exp180_shared:{enabled:false,weights:[2,4]},'exp180_shared.enabled':false},
    {exp180_final_a:'B-final'}
  ]) assert.deepEqual(projectFlagValues({feature_flags}, flagAt), {invalid:true});
  assert.deepEqual(projectFlagValues({feature_flags:{exp180_shared:7},
    'feature_flags.exp180_shared':7}, flagAt), {invalid:true});
});
test('flag metrics preserve aggregate values and FBC in nested and flat payloads', () => {
  const expected = {flags:{exp180_shared:7},build:{min:32,max:52,average:42},
    fbc:101,leakedInternalAttribute:false};
  assert.deepEqual(projectFlagState({feature_flags:{exp180_shared:7},
    view:{flutter_build_time:{min:32,max:52,average:42},performance:{fbc:{timestamp:101}}}}, flagAt), expected);
  assert.deepEqual(projectFlagState({'feature_flags.exp180_shared':7,
    'view.flutter_build_time.min':32,'view.flutter_build_time.max':52,'view.flutter_build_time.average':42,
    'view.performance.fbc.timestamp':101}, flagAt), expected);
});
test('flag metrics reject malformed present aggregates and FBC types', () => {
  for (const build of [null, {}, {min:null,max:null,average:null}, {min:32,max:52},
    {min:true,max:52,average:42}, {min:'32',max:52,average:42},
    {min:NaN,max:52,average:42}, {min:0,max:52,average:42}]) {
    assert.deepEqual(projectFlagState({view:{flutter_build_time:build}}, flagAt), {invalid:true});
  }
  for (const timestamp of [null,true,'101',0,-1,1.5]) {
    assert.deepEqual(projectFlagState({view:{performance:{fbc:{timestamp}}}}, flagAt), {invalid:true});
  }
});
test('internal mutation key leakage is visible even for null and flattened values', () => {
  for (const payload of [
    {context:{'_dd.performance.first_build_complete':null}},
    {'context._dd.performance.first_build_complete':101},
    {context:{_dd:{performance:{first_build_complete:101}}}}
  ]) {
    assert.equal(hasInternalFlagAttribute(payload), true);
    assert.equal(projectFlagState(payload, flagAt).leakedInternalAttribute, true);
  }
  assert.equal(hasInternalFlagAttribute({context:{other:101}}), false);
});

const {projectTraceRow} = new Function(source.replace(
  'return runAcceptance({tools, notify, device, repo, scenario: typeof scenario === "undefined" ? undefined : scenario});',
  'return {projectTraceRow};'
))();
const traceAt = (object, path) => {
  const parts = path.split(".");
  let value = object;
  for (let i = 0; i < parts.length; i++) {
    if (value == null) return null;
    if (Object.hasOwn(value, parts.slice(i).join("."))) return value[parts.slice(i).join(".")];
    value = value[parts[i]];
  }
  return value ?? null;
};
const traceRow = () => ({
  traceid:"ffffffffffffffff1234567890abcdef",
  spanid:BigInt("0xf123456789abcdef").toString(), parentid:"0",
  operationname:"exp181.native_a", resourcename:"exp181.native-a",
  service:"ios-sdk-native-multi-scene-probe", status:"ok",
  custom:{"probe.run_id":"run", duration:123456789}
});
const traceDetail = row => ({
  span_id:row.spanid, parent_id:row.parentid, name:row.operationname,
  resource:row.resourcename, service:row.service, duration_ms:123.456792,
  meta:{"probe.run_id":"run", "_dd.p.ftid":row.traceid, "_dd.application.id":"app",
    "_dd.session.id":"session", "_dd.view.id":"view"}
});
test("span projection joins exact decimal identities and private owners without display rounding", () => {
  const row = traceRow();
  assert.deepEqual(projectTraceRow(row, [traceDetail(row)], traceAt), {
    phase:"native-a", trace_id:"ffffffffffffffff1234567890abcdef", span_id:"f123456789abcdef",
    parent_id:"0000000000000000", operation:"exp181.native_a", resource:"exp181.native-a", http_url:null,
    service:"ios-sdk-native-multi-scene-probe", is_error:false, duration_ns:123456789,
    run_id:"run", application_id:"app", session_id:"session", view_id:"view", action_ids:[]
  });
});
test("span projection rejects numeric rounded hexadecimal and overflowing decimal identities", () => {
  for (const [key, value] of [["traceid",123], ["spanid",null], ["parentid",null],
      ["spanid",12345678901234567000], ["spanid","f123456789abcdef"],
      ["spanid","18446744073709551616"], ["spanid","0"], ["parentid","-1"]]) {
    const row = {...traceRow(), [key]:value};
    assert.throws(() => projectTraceRow(row, [traceDetail(row)], traceAt), undefined, key);
  }
  for (const value of [1.2, "123456789", Infinity, 1e20, null, true]) {
    const row = traceRow(); row.custom.duration = value;
    assert.throws(() => projectTraceRow(row, [traceDetail(row)], traceAt), /nanosecond/);
  }
});
test("span projection rejects missing duplicate foreign and mismatching trace detail records", () => {
  const row = traceRow();
  for (const details of [[], [traceDetail(row),traceDetail(row)]]) {
    assert.throws(() => projectTraceRow(row, details, traceAt), /inventory/);
  }
  for (const [key,value] of [["span_id","3"],["parent_id","3"],["name","other"],["resource","other"],["service","other"]]) {
    assert.throws(() => projectTraceRow(row,[{...traceDetail(row),[key]:value}],traceAt), /mismatch/);
  }
  for (const key of ["_dd.application.id","_dd.session.id","_dd.view.id","_dd.p.ftid","probe.run_id"]) {
    const detail = traceDetail(row); delete detail.meta[key];
    assert.throws(() => projectTraceRow(row,[detail],traceAt), undefined, key);
  }
  const detail = traceDetail(row); detail.meta["_dd.p.ftid"] = "e".repeat(32);
  assert.throws(() => projectTraceRow(row,[detail],traceAt), /identity mismatch/);
});
test("automatic resource normalization keeps the exact original URL and independently captured owner", () => {
  const row = {...traceRow(), operationname:"urlsession.request",
    resourcename:"https://multi-scene-probe.invalid/trace-only/run-{num}/scene-A/home/url-a"};
  row.custom["http.url"] = "https://multi-scene-probe.invalid/trace-only/run-123/scene-A/home/url-a";
  const detail = traceDetail(row);
  detail.meta["http.url"] = row.custom["http.url"];
  detail.meta["_dd.view.id"] = "peer";
  detail.meta["_dd.action.id"] = "foreign-action";
  const result = projectTraceRow(row,[detail],traceAt);
  assert.equal(result.phase, "url-a");
  assert.equal(result.resource, row.resourcename);
  assert.equal(result.http_url, row.custom["http.url"]);
  assert.equal(result.view_id, "peer");
  assert.deepEqual(result.action_ids, ["foreign-action"]);
  detail.meta["http.url"] = "https://other.invalid";
  assert.throws(() => projectTraceRow(row,[detail],traceAt), /URL mismatch/);
});
test("undeclared operation and missing status are never synthesized from local evidence", () => {
  const row = {...traceRow(), operationname:"exp181.other"};
  assert.throws(() => projectTraceRow(row,[traceDetail(row)],traceAt), /Undeclared/);
  const missing = traceRow(); delete missing.status;
  assert.throws(() => projectTraceRow(missing,[traceDetail(missing)],traceAt), /status/);
});


test("Trace projection works in a tool sandbox without browser URL globals", () => {
  const vm = require("node:vm");
  const sandboxProject = vm.runInNewContext(source.replace(
    'return runAcceptance({tools, notify, device, repo, scenario: typeof scenario === "undefined" ? undefined : scenario});',
    'projectTraceRow;'
  ), {});
  const row = {...traceRow(), operationname:"urlsession.request",
    resourcename:"https://multi-scene-probe.invalid/trace-only/run-{num}/scene-A/home/url-a"};
  row.custom["http.url"] = "https://multi-scene-probe.invalid/trace-only/run-123/scene-A/home/url-a";
  const detail = traceDetail(row); detail.meta["http.url"] = row.custom["http.url"];
  assert.equal(sandboxProject(row, [detail], traceAt).phase, "url-a");
});

const {collectTraceDetails} = new Function(source.replace(
  'return runAcceptance({tools, notify, device, repo, scenario: typeof scenario === "undefined" ? undefined : scenario});',
  'return {collectTraceDetails};'
))();

test("independent detail requests all start before decoding and preserve response identity", async () => {
  const rows = [traceRow(), {...traceRow(), traceid:"a".repeat(32), spanid:"8"}];
  const pending = [];
  let decodes = 0;
  const task = collectTraceDetails(rows, traceID => new Promise(resolve => pending.push({traceID, resolve})),
    async responses => { decodes++; return responses.map(response => [response]); }, traceAt);
  assert.equal(pending.length, 2);
  assert.equal(decodes, 0);
  pending[1].resolve(traceDetail(rows[1]));
  pending[0].resolve(traceDetail(rows[0]));
  const results = await task;
  assert.equal(decodes, 1);
  assert.deepEqual(results.map(result => result.trace_id), rows.map(row => row.traceid));
});

test("failed or missing detail batch results cannot produce a partial acceptance", async () => {
  const rows = [traceRow(), {...traceRow(), traceid:"a".repeat(32), spanid:"8"}];
  let reads = 0;
  await assert.rejects(collectTraceDetails(rows, async traceID => {
    reads++;
    if (traceID === rows[0].traceid) throw Error("unavailable");
    return traceDetail(rows[1]);
  }, async () => { throw Error("decoder must not accept partial reads"); }, traceAt), /Incomplete trace detail reads/);
  assert.equal(reads, 2);
  await assert.rejects(collectTraceDetails(rows, async () => ({}), async () => [], traceAt), /Incomplete trace detail decoding/);
});


const {parseLogCount, parseLogGroups, validateLogInventory, logGroupColumns, projectLogRow, hasPrivateMirrorMetadata} = new Function(source.replace(
  'return runAcceptance({tools, notify, device, repo, scenario: typeof scenario === "undefined" ? undefined : scenario});',
  'return {parseLogCount, parseLogGroups, validateLogInventory, logGroupColumns, projectLogRow, hasPrivateMirrorMetadata};'
))();
const logRow = () => ({
  id:'backend-182', service:'probe', status:'info', message:'log-info-a',
  attributes:{
    'custom.application_id':'application', 'custom.session_id':'session',
    'custom.view.id':'view-a', 'custom.user_action.id':'action-a',
    'custom.probe.run_id':'run', 'custom.probe.phase':'log-info-a',
    'custom.probe.source_scene':'scene-A'
  }
});
test('Logs aggregate requires one exact integer count', () => {
  assert.equal(parseLogCount('<TSV_DATA>\nevents\n6\n</TSV_DATA>'), 6);
  assert.equal(parseLogCount('<TSV_DATA>\nevents\n0\n</TSV_DATA>'), 0);
  for (const value of ['6\n7', '6.0', 'true', '-1', '101', '6\t7']) {
    assert.throws(() => parseLogCount('<TSV_DATA>\nevents\n' + value + '\n</TSV_DATA>'));
  }
  assert.throws(() => parseLogCount('<TSV_DATA>\ncount\n6\n</TSV_DATA>'));
});
test('Logs projection preserves actual record identity and emission correlation', () => {
  assert.deepEqual(projectLogRow(logRow()), {
    log_id:'backend-182', run_id:'run', phase:'log-info-a', application_id:'application',
    session_id:'session', view_id:'view-a', action_id:'action-a', source_scene:'scene-A',
    service:'probe', status:'info', message:'log-info-a', leaked_internal_attribute:false
  });
});
test('Logs projection rejects missing selected fields without borrowing labels', () => {
  for (const key of ['service','status','message']) {
    const row = logRow(); delete row[key];
    assert.throws(() => projectLogRow(row));
  }
  for (const key of Object.keys(logRow().attributes)) {
    for (const value of [null, true, 182, '', []]) {
      const row = logRow(); row.attributes[key] = value;
      assert.throws(() => projectLogRow(row));
    }
  }
});
test('Logs projection rejects duplicate namespace or flat/nested ownership', () => {
  for (const key of ['custom.view.id', 'attributes.view.id']) {
    const row = logRow();
    if (key === 'custom.view.id') row.attributes.custom = {view:{id:'view-a'}};
    else row.attributes[key] = 'view-a';
    assert.throws(() => projectLogRow(row), /Ambiguous/);
  }
});
test('Logs projection accepts the documented alternate attribute namespace', () => {
  const row = logRow();
  row.attributes = Object.fromEntries(Object.entries(row.attributes).map(([key,value]) =>
    [key.replace(/^custom\./,'attributes.'),value]));
  assert.equal(projectLogRow(row).action_id,'action-a');
});
test('Logs and mirror private metadata is detected across wire shapes', () => {
  for (const key of ['target_view_id','target_action_id','target_scene_id','context_captured']) {
    const row = logRow(); row.attributes['custom._dd.internal.rum.error.' + key] = null;
    assert.equal(projectLogRow(row).leaked_internal_attribute,true);
    assert.equal(hasPrivateMirrorMetadata({['_dd.internal.rum.error.' + key]:null}),true);
    assert.equal(hasPrivateMirrorMetadata({_dd:{internal:{rum:{error:{[key]:'value'}}}}}),true);
  }
  assert.equal(hasPrivateMirrorMetadata({_dd:{device:{architecture:'arm64'}}}),false);
});

test("Logs absent backend IDs remain null and malformed exposed IDs fail", () => {
  const row = logRow(); delete row.id;
  assert.equal(projectLogRow(row).log_id, null);
  for (const id of ["", true, 182, []]) assert.throws(() => projectLogRow({...row, id}));
});
const logGroup = row => Object.fromEntries([
  ...Object.keys(logGroupColumns).map(key => [key, row[key]]), ["events", 1]
]);
const groupBody = groups => '<METADATA><displayed_columns>11</displayed_columns>' +
  '<displayed_rows>' + groups.length + '</displayed_rows><total_rows>' + groups.length +
  '</total_rows></METADATA><TSV_DATA>\n' +
  [...Object.keys(logGroupColumns), 'events'].join('\t') + '\n' +
  groups.map(row => [...Object.keys(logGroupColumns), 'events'].map(key => row[key]).join('\t')).join('\n') +
  '\n</TSV_DATA>';
test("Logs grouped projection requires complete metadata and exact typed columns", () => {
  const group = logGroup(projectLogRow(logRow()));
  const body = groupBody([group]);
  assert.deepEqual(parseLogGroups(body), [group]);
  for (const changed of [
    body.replace('total_rows>1', 'total_rows>2'),
    body.replace('displayed_rows>1', 'displayed_rows>0'),
    body.replace('displayed_columns>11', 'displayed_columns>10'),
    body.replace('run_id\t', 'run\t'),
    body.replace('<total_rows>1</total_rows>', ''),
    body.replace('view-a\t', '\t')
  ]) assert.throws(() => parseLogGroups(changed));
  for (const events of [0, 2, true, '1.0', '01', '-1']) {
    assert.throws(() => parseLogGroups(groupBody([{...group, events}])));
  }
});
test("Logs independent counts bind every raw row to one exact grouped owner", () => {
  const first = projectLogRow(logRow()); first.log_id = null;
  const rows = [first, {...first, phase:'log-info-b', message:'log-info-b', view_id:'view-b'}];
  const groups = rows.map(logGroup).reverse();
  assert.deepEqual(validateLogInventory(2, rows, groups), {count:2, rows, groups});
  for (const count of [true, 1, 3, 2.1]) assert.throws(() => validateLogInventory(count, rows, groups));
  assert.throws(() => validateLogInventory(2, rows.slice(1), groups));
  assert.throws(() => validateLogInventory(2, rows, groups.slice(1)));
  assert.throws(() => validateLogInventory(2, [rows[0], rows[0]], groups));
  assert.throws(() => validateLogInventory(2, rows, [groups[0], groups[0]]));
  for (const key of Object.keys(logGroupColumns)) {
    const changed = groups.map(row => ({...row}));
    changed[0][key] = 'wrong';
    assert.throws(() => validateLogInventory(2, rows, changed), undefined, key);
  }
  for (const events of [0, 2, true]) {
    assert.throws(() => validateLogInventory(2, rows, [{...groups[0], events}, groups[1]]));
  }
  const withIDs = rows.map(row => ({...row, log_id:'same'}));
  assert.throws(() => validateLogInventory(2, withIDs, groups), /Duplicate/);
});

const {projectWebView} = new Function(source.replace(
  'return runAcceptance({tools, notify, device, repo, scenario: typeof scenario === "undefined" ? undefined : scenario});',
  'return {projectWebView};'
))();
test('WebView projection preserves native replacement and exact container fields', () => {
  const value = projectWebView({application:{id:'native-app'}, session:{id:'native-session',has_replay:true},
    view:{id:'browser-id',name:'web-a-original',url:'https://multi-scene-probe.invalid/run/A/initial',
      is_active:false,time_spent:1000000,action:{count:0},resource:{count:0},error:{count:0}},
    context:{probe:{run_id:'run',phase:'web-a-original',source_scene:'scene-A',document_id:'run/A/initial'}},
    container:{source:'ios',view:{id:'native-view'}}, source:'browser'});
  assert.equal(value.application_id, 'native-app');
  assert.equal(value.session_id, 'native-session');
  assert.equal(value.container_id, 'native-view');
  assert.equal(value.container_source, 'ios');
  assert.equal(value.container_present, true);
  assert.equal(value.leaked_internal_attribute, false);
  assert.equal(value.time_spent, 1000000);
});
test('WebView detached absence differs from an empty or null container', () => {
  assert.equal(projectWebView({view:{id:'browser'}}).container_present, false);
  assert.equal(projectWebView({container:null}).container_present, true);
  assert.equal(projectWebView({container:{}}).container_present, true);
  assert.equal(projectWebView({'container.view.id':'native'}).container_present, true);
});
test('WebView projection supports nested flat and partially flat source fields', () => {
  for (const payload of [{context:{probe:{run_id:'run'}}}, {'context.probe.run_id':'run'},
                         {context:{'probe.run_id':'run'}}, {'context.probe':{run_id:'run'}}]) {
    assert.equal(projectWebView(payload).run_id, 'run');
  }
});
test('WebView projection detects private scene keys including null and context forms', () => {
  for (const payload of [{'_dd.internal.native_scene_id':'spoof'},
    {_dd:{internal:{native_scene_id:'spoof'}}}, {context:{'_dd.internal.native_scene_id':null}},
    {'context._dd.internal':{native_scene_id:'spoof'}}]) {
    assert.equal(projectWebView(payload).leaked_internal_attribute, true);
  }
});
test('WebView projection preserves malformed types for rejection by semantic oracle', () => {
  const value = projectWebView({view:{action:{count:false},time_spent:'1000000'},
    session:{has_replay:1},container:{view:{id:true}}});
  assert.equal(value.action_count, false);
  assert.equal(value.time_spent, '1000000');
  assert.equal(value.has_replay, 1);
  assert.equal(value.container_id, true);
});
test('WebView projection rejects ambiguous source representations', () => {
  for (const payload of [
    {container:{view:{id:'native'}},'container.view.id':'native'},
    {context:{probe:{run_id:'run'},'probe.run_id':'run'}},
    {source:'browser',view:{id:'browser'},'view.id':'browser'}
  ]) assert.throws(() => projectWebView(payload), /Ambiguous WebView/);
});

test('WebView source comes from actual detailed event envelope when absent from custom payload', () => {
  assert.equal(projectWebView({view:{id:'browser'}}, {source:'browser'}).source, 'browser');
  assert.equal(projectWebView({view:{id:'native'}}, {source:'ios'}).source, 'ios');
  assert.equal(projectWebView({source:'browser'}, {source:'browser'}).source, 'browser');
});
test('WebView source conflicts fail without replacing actual evidence', () => {
  assert.throws(() => projectWebView({source:'browser'}, {source:'ios'}), /Conflicting/);
});
test('WebView missing or malformed source is preserved for oracle rejection', () => {
  assert.equal(projectWebView({view:{id:'browser'}}).source, null);
  assert.equal(projectWebView({view:{id:'browser'}}, {source:17}).source, 17);
});

const {projectFatal} = new Function(source.replace(
  'return runAcceptance({tools, notify, device, repo, scenario: typeof scenario === "undefined" ? undefined : scenario});',
  'return {projectFatal};'
))();
test('fatal projection keeps original owner, incident and actual source envelope', () => {
  const result = projectFatal({
    session:{id:'old-session'}, view:{id:'old-view',error:{count:1},crash:{count:1}},
    context:{probe:{run_id:'old-run',phase:'fatal-original'}},
    error:{id:'error',source:'source',type:'SIGABRT (#0)',is_crash:true,
      meta:{incident_identifier:'incident',exception_type:'SIGABRT',process:'Probe [184]'}}
  }, {source:'ios'});
  assert.equal(result.source, 'ios');
  assert.equal(result.run_id, 'old-run');
  assert.equal(result.session_id, 'old-session');
  assert.equal(result.view_id, 'old-view');
  assert.equal(result.incident_id, 'incident');
  assert.equal(result.crashed_process, 'Probe [184]');
  assert.equal(result.crash_count, 1);
  assert.equal(result.is_crash, true);
  assert.equal(result.action_present, false);
  assert.equal(result.container_present, false);
});
test('fatal projection preserves malformed types and unexpected association for rejection', () => {
  const result = projectFatal({'error.is_crash':'true','view.crash.count':'1','action.id':'unexpected',
    'container.view.id':'unexpected','source':'browser'});
  assert.equal(result.is_crash, 'true');
  assert.equal(result.crash_count, '1');
  assert.equal(result.action_present, true);
  assert.equal(result.container_present, true);
  assert.equal(result.source, 'browser');
  assert.throws(() => projectFatal({source:'browser'}, {source:'ios'}), /Conflicting/);
});
test('fatal projection accepts flattened metadata without inventing absent origin', () => {
  const result = projectFatal({'error.meta.incident_identifier':'incident','error.meta.exception_type':'SIGABRT'});
  assert.equal(result.incident_id, 'incident');
  assert.equal(result.exception_type, 'SIGABRT');
  assert.equal(result.run_id, null);
  assert.equal(result.view_id, null);
  assert.equal(result.source, null);
});

test('fatal projection separates observed SDK revision from backend document counter', () => {
  const result = projectFatal({_dd:{document_version:56}, context:{exp184_sdk_document_version:2}});
  assert.equal(result.document_version, 56);
  assert.equal(result.sdk_document_version, 2);
  assert.equal(projectFatal({_dd:{document_version:56}}).sdk_document_version, null);
  assert.throws(() => projectFatal({context:{exp184_sdk_document_version:2},
    'context.exp184_sdk_document_version':3}), /Ambiguous/);
});
