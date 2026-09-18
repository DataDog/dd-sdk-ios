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
  trace_id:"ffffffffffffffff1234567890abcdef", span_id:"f123456789abcdef", parent_id:"0",
  operation_name:"exp181.native-a", resource_name:"exp181.native-a",
  service:"ios-sdk-native-multi-scene-probe", status:"ok", duration:123456789,
  custom_attributes:{"probe.run_id":"run", "_dd.application.id":"app", "_dd.session.id":"session", "_dd.view.id":"view"}
});
test("span projection preserves full hex identity exact nanoseconds and captured owners", () => {
  assert.deepEqual(projectTraceRow(traceRow(), traceAt), {
    phase:"native-a", trace_id:"ffffffffffffffff1234567890abcdef", span_id:"f123456789abcdef",
    parent_id:"0000000000000000", operation:"exp181.native-a", resource:"exp181.native-a",
    service:"ios-sdk-native-multi-scene-probe", is_error:false, duration_ns:123456789,
    run_id:"run", application_id:"app", session_id:"session", view_id:"view", action_ids:[]
  });
  const wrapped = {attributes:{...traceRow(), custom:traceRow().custom_attributes}};
  delete wrapped.attributes.custom_attributes;
  assert.deepEqual(projectTraceRow(wrapped, traceAt), projectTraceRow(traceRow(), traceAt));
});
test("span projection rejects lost identity precision ambiguous fields and display durations", () => {
  for (const [key, value] of [["trace_id",123], ["span_id",null], ["parent_id",null], ["duration",1.2],
      ["duration","123456789"], ["duration",Infinity], ["duration",1e20], ["status",null]]) {
    const row = {...traceRow(), [key]:value};
    assert.throws(() => projectTraceRow(row, traceAt), undefined, key);
  }
  assert.throws(() => projectTraceRow({...traceRow(), "duration_ns":987}, traceAt), /Ambiguous/);
});
test("automatic span phase comes from declared URL while owners remain independent fields", () => {
  const row = {...traceRow(), operation_name:"urlsession.request",
    resource_name:"https://multi-scene-probe.invalid/trace-only/run/scene-A/home/url-a"};
  row.custom_attributes["_dd.view.id"] = "peer";
  row.custom_attributes["_dd.action.id"] = "foreign-action";
  const result = projectTraceRow(row, traceAt);
  assert.equal(result.phase, "url-a");
  assert.equal(result.view_id, "peer");
  assert.deepEqual(result.action_ids, ["foreign-action"]);
});
