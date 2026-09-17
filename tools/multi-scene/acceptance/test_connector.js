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
