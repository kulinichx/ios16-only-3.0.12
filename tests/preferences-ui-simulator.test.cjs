const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const { run } = require('./helpers/preferences-ui-simulator.cjs');

// Exercise the runner's control flow on every platform. This does not replace UIKit.
function fixture(t, { launchError, diagnosticError, plistError, failedReport = false, outputUnavailable = false,
  missingHomeReport = false, missingScheduleReport = false, runtimeErrors = [], runtimeOutput } = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-simulator-test-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const output = path.join(directory, 'evidence');
  const data = path.join(directory, 'data');
  fs.mkdirSync(path.join(data, 'Documents'), { recursive: true });
  const calls = [];
  const messages = [];
  const logger = {
    log: (...args) => messages.push(args.join(' ')),
    error: (...args) => messages.push(args.join(' ')),
  };
  let runtimeAttempts = 0;
  const execute = async (file, args, options) => {
    calls.push({ file, args, options });
    if (file === '/usr/bin/log') {
      if (diagnosticError) throw diagnosticError;
      return { stdout: 'CoreSimulator host diagnostics', stderr: 'host diagnostic stderr' };
    }
    if (file === '/usr/bin/plutil') {
      assert.ok(fs.existsSync(args[1]), 'validate the actual generated bundle');
      if (plistError) throw plistError;
      return { stdout: `${args[1]}: OK`, stderr: '' };
    }
    assert.equal(file, 'xcrun');
    let stdout = '';
    let stderr = '';
    if (args[0] === 'simctl') {
      switch (args[1]) {
        case 'list':
          if (args[2] === 'runtimes') {
            const error = runtimeErrors[runtimeAttempts++];
            if (error) throw error;
            if (runtimeOutput !== undefined) return { stdout: runtimeOutput, stderr: '' };
          }
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
            : { status: 'passed', viewports: 12, scrollChecks: 2400, homeFocusCases: missingHomeReport ? undefined : 6, scheduleUICases: missingScheduleReport ? undefined : 6 }));
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
  return { output, execute, calls, logger, messages };
}

test('cold CoreSimulator discovery retries its timeout once and then runs the real report checks', async t => {
  const error = Object.assign(new Error('discovery timed out'), { killed: true, signal: 'SIGTERM', code: null });
  const context = fixture(t, { runtimeErrors: [error] });
  await run(context);
  const queries = context.calls.filter(call => call.args[2] === 'runtimes');
  assert.equal(queries.length, 2);
  assert.ok(queries.every(call => call.options.timeout === 180000));
  assert.match(fs.readFileSync(path.join(context.output, 'commands.log'), 'utf8'), /retrying once/);
  assert.ok(context.calls.some(call => call.args[1] === 'launch'));
  assert.equal(JSON.parse(fs.readFileSync(path.join(context.output, 'report.json'))).status, 'passed');
});

test('installed harness declares phone and iPad orientations and validates its plist before boot', async t => {
  const context = fixture(t);
  let installedPlist;
  const execute = async (file, args, options) => {
    if (file === 'xcrun' && args[1] === 'install')
      installedPlist = fs.readFileSync(path.join(args[3], 'Info.plist'), 'utf8');
    return context.execute(file, args, options);
  };
  await run({ ...context, execute });
  const orientations = key => {
    const array = installedPlist.match(new RegExp(`<key>${key}</key><array>([\\s\\S]*?)</array>`));
    assert.ok(array, `missing ${key}`);
    return [...array[1].matchAll(/<string>([^<]+)<\/string>/g)].map(match => match[1]);
  };
  assert.deepEqual(orientations('UISupportedInterfaceOrientations'), [
    'UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight',
  ]);
  assert.deepEqual(orientations('UISupportedInterfaceOrientations~ipad'), [
    'UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown',
    'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight',
  ]);
  assert.equal(fs.readFileSync(path.join(context.output, 'harness-Info.plist'), 'utf8'), installedPlist);
  const validation = context.calls.findIndex(call => call.file === '/usr/bin/plutil');
  const creation = context.calls.findIndex(call => call.args[1] === 'create');
  assert.ok(validation >= 0 && validation < creation);
});

test('invalid bundle plist fails before creating a simulator and retains the validation error', async t => {
  const error = new Error('invalid harness Info.plist');
  const context = fixture(t, { plistError: error });
  await assert.rejects(run(context), caught => caught === error);
  assert.ok(!context.calls.some(call => ['create', 'install', 'launch'].includes(call.args[1])));
  assert.ok(fs.existsSync(path.join(context.output, 'harness-Info.plist')));
});

test('repeated discovery timeouts fail after two attempts and collect host logs without a device', async t => {
  const errors = [1, 2].map(i => Object.assign(new Error(`discovery timeout ${i}`), { killed: true, signal: 'SIGTERM', code: null }));
  const context = fixture(t, { runtimeErrors: errors });
  await assert.rejects(run(context), caught => caught === errors[1]);
  assert.equal(context.calls.filter(call => call.args[2] === 'runtimes').length, 2);
  assert.equal(context.calls.at(-1).file, '/usr/bin/log');
  assert.equal(context.calls.at(-1).options.timeout, 30000);
  assert.ok(!context.calls.some(call => ['create', 'launch', 'delete'].includes(call.args[1])));
  const diagnostic = fs.readFileSync(path.join(context.output, 'launch-diagnostics.log'), 'utf8');
  assert.match(diagnostic, /CoreSimulator host diagnostics/);
  assert.match(diagnostic, /host diagnostic stderr/);
});

test('recovering discovery does not turn a failed UIKit assertion into success', async t => {
  const error = Object.assign(new Error('discovery timed out'), { killed: true, signal: 'SIGTERM', code: null });
  const context = fixture(t, { runtimeErrors: [error], failedReport: true });
  await assert.rejects(run(context), /geometry assertion failed/);
  assert.equal(context.calls.filter(call => call.args[2] === 'runtimes').length, 2);
  assert.equal(context.calls.filter(call => call.args[1] === 'launch').length, 1);
});

test('non-timeout discovery errors and malformed JSON fail immediately without retry', async t => {
  for (const properties of [
    { killed: false, code: 1, signal: null },
    { killed: true, code: 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER', signal: 'SIGTERM' },
  ]) {
    const error = Object.assign(new Error('discovery error'), properties);
    const context = fixture(t, { runtimeErrors: [error] });
    await assert.rejects(run(context), caught => caught === error);
    assert.equal(context.calls.filter(call => call.args[2] === 'runtimes').length, 1);
  }
  const context = fixture(t, { runtimeOutput: 'invalid JSON' });
  await assert.rejects(run(context), SyntaxError);
  assert.equal(context.calls.filter(call => call.args[2] === 'runtimes').length, 1);
});

test('host diagnostic failure preserves the initialization error', async t => {
  const error = Object.assign(new Error('CoreSimulator unavailable'), { code: 1 });
  const context = fixture(t, { runtimeErrors: [error], diagnosticError: new Error('host logs unavailable') });
  await assert.rejects(run(context), caught => caught === error);
  assert.match(fs.readFileSync(path.join(context.output, 'launch-diagnostics.log'), 'utf8'), /host logs unavailable/);
});

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

test('a passing settings report cannot substitute for the new native home gesture cases', async t => {
  const context = fixture(t, { missingHomeReport: true });
  await assert.rejects(run(context), /undefined !== 6/);
  assert.ok(fs.existsSync(path.join(context.output, 'report.json')));
});

test('a passing home report cannot substitute for the shared schedule page cases', async t => {
  const context = fixture(t, { missingScheduleReport: true });
  await assert.rejects(run(context), /undefined !== 6/);
});
