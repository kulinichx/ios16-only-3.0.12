const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const { run } = require('./helpers/preferences-ui-simulator.cjs');

// Exercise the runner's control flow on every platform. This does not replace UIKit.
function fixture(t, { launchError, diagnosticError, failedReport = false, outputUnavailable = false } = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-simulator-test-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const output = path.join(directory, 'evidence');
  const data = path.join(directory, 'data');
  fs.mkdirSync(path.join(data, 'Documents'), { recursive: true });
  const calls = [];
  const execute = async (file, args, options) => {
    assert.equal(file, 'xcrun');
    calls.push({ args, options });
    let stdout = '';
    let stderr = '';
    if (args[0] === 'simctl') {
      switch (args[1]) {
        case 'list':
          stdout = JSON.stringify(args[2] === 'runtimes' ? { runtimes: [{
            isAvailable: true, version: process.env.DORH_SIMULATOR_RUNTIME || '18.5',
            identifier: 'com.apple.CoreSimulator.SimRuntime.iOS-18-5'
          }] } : { devicetypes: [{ name: 'iPad mini (6th generation)', identifier: 'test-ipad' }] });
          break;
        case 'create': stdout = '11111111-2222-3333-4444-555555555555'; break;
        case 'get_app_container': stdout = data; break;
        case 'launch':
          // The app can write its report before simctl acknowledges the launch.
          fs.writeFileSync(path.join(data, 'Documents', 'report.json'), JSON.stringify(failedReport
            ? { status: 'failed', reason: 'geometry assertion failed' }
            : { status: 'passed', viewports: 12, scrollChecks: 2400 }));
          fs.writeFileSync(path.join(data, 'Documents', 'settings-portrait.png'), 'test screenshot');
          if (outputUnavailable) {
            fs.renameSync(output, path.join(directory, 'old-evidence'));
            fs.writeFileSync(output, 'file blocking the evidence directory');
          }
          if (launchError) throw launchError;
          stdout = 'test.roothide.preferences-layout: 123';
          break;
        case 'spawn':
          if (diagnosticError) throw diagnosticError;
          stdout = 'simulator system output';
          stderr = 'simulator error output';
          break;
      }
    } else if (args.includes('--show-sdk-path')) stdout = '/test-sdk';
    return { stdout, stderr };
  };
  return { output, execute, calls };
}

test('simulator runner allows a bounded three-minute launch and still requires passing UIKit results', async t => {
  const context = fixture(t);
  await run(context);
  const launch = context.calls.find(call => call.args[1] === 'launch');
  assert.equal(launch.options.timeout, 180000);
  assert.equal(JSON.parse(fs.readFileSync(path.join(context.output, 'report.json'))).scrollChecks, 2400);
  assert.deepEqual(context.calls.slice(-2).map(call => call.args[1]), ['shutdown', 'delete']);
});

test('launch timeout retains kill metadata, both diagnostic streams and evidence before deleting the device', async t => {
  const error = Object.assign(new Error('launch timed out'), { killed: true, signal: 'SIGTERM', code: null });
  const context = fixture(t, { launchError: error });
  await assert.rejects(run(context), caught => caught === error);
  const log = fs.readFileSync(path.join(context.output, 'commands.log'), 'utf8');
  assert.match(log, /"timeoutMs":180000/);
  assert.match(log, /"signal":"SIGTERM","killed":true/);
  const diagnostics = fs.readFileSync(path.join(context.output, 'launch-diagnostics.log'), 'utf8');
  assert.match(diagnostics, /simulator system output/);
  assert.match(diagnostics, /simulator error output/);
  assert.ok(fs.existsSync(path.join(context.output, 'report.json')));
  assert.ok(fs.existsSync(path.join(context.output, 'settings-portrait.png')));
  assert.deepEqual(context.calls.slice(-3).map(call => call.args[1]), ['spawn', 'shutdown', 'delete']);
});

test('diagnostic collection failure preserves the original launch rejection', async t => {
  const error = Object.assign(new Error('launch rejected'), { code: 1, stderr: 'launch service denied request' });
  const context = fixture(t, { launchError: error, diagnosticError: new Error('log service unavailable') });
  await assert.rejects(run(context), caught => caught === error);
  assert.match(fs.readFileSync(path.join(context.output, 'commands.log'), 'utf8'), /launch service denied request/);
  assert.match(fs.readFileSync(path.join(context.output, 'launch-diagnostics.log'), 'utf8'), /log service unavailable/);
  assert.deepEqual(context.calls.slice(-2).map(call => call.args[1]), ['shutdown', 'delete']);
});

test('evidence write failure cannot replace the original command failure or prevent device cleanup', async t => {
  const error = new Error('original launch error');
  const context = fixture(t, { launchError: error, outputUnavailable: true });
  await assert.rejects(run(context), caught => caught === error);
  assert.deepEqual(context.calls.slice(-2).map(call => call.args[1]), ['shutdown', 'delete']);
});

test('a launched app with a failed geometry assertion continues to fail the required check', async t => {
  const context = fixture(t, { failedReport: true });
  await assert.rejects(run(context), /geometry assertion failed/);
  assert.equal(JSON.parse(fs.readFileSync(path.join(context.output, 'report.json'))).status, 'failed');
  assert.deepEqual(context.calls.slice(-2).map(call => call.args[1]), ['shutdown', 'delete']);
});
