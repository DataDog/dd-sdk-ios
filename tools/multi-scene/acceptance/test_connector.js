const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const source = fs.readFileSync(path.join(__dirname, 'connector_driver.js'), 'utf8');
const {execToCompletion} = new Function(source.replace(
  'return runAcceptance({tools, notify, device, repo});', 'return {execToCompletion};'
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
