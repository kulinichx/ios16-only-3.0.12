const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFile } = require('node:child_process');
const execFileAsync = require('node:util').promisify(execFile);

const root = path.resolve(__dirname, '../..');
const ui = 'Application/Dopamine/UI/';
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
function section(source, start, end) {
  const a = source.indexOf(start);
  const b = source.indexOf(end, a + start.length);
  assert.ok(a >= 0 && b > a, `Missing production section ${start}`);
  return source.slice(a, b);
}

function harnessSource() {
  const base = read(ui + 'Settings/PSLists/DOPSListController.m');
  const settings = read(ui + 'Settings/DOSettingsController.m');
  const credits = read(ui + 'Settings/DOCreditsViewController.m');
  const material = read(ui + 'DOCustomGlassView.m');
  const replacements = {
    MATERIAL_HEADER: read(ui + 'DOCustomGlassView.h'),
    MATERIAL: section(material, '@implementation DOCustomLiquidGlassView', '\n@end') + '\n@end',
    BASE: section(base, '- (void)viewDidLayoutSubviews', '#pragma mark'),
    SETTINGS_BACKGROUND: section(settings, '    UIView *glassBackground =', '    _table.separatorStyle'),
    SETTINGS_REFRESH: section(settings, '- (void)customGlassRefreshSectionBackdrops', '- (void)customGlassRefreshPageAppearance'),
    SETTINGS_LAYOUT: section(settings, '- (void)viewDidLayoutSubviews', '- (void)tableView:'),
    CREDITS_BACKGROUND: section(credits, '    UIView *glassBackground =', '    // The shared navigation bar'),
    CREDITS_REFRESH: section(credits, '- (void)customGlassRefreshPageBackdrop', '- (void)customGlassRefreshPageAppearance'),
    CREDITS_LAYOUT: section(credits, '- (void)viewDidLayoutSubviews', '- (void)customGlassStyleContent:'),
  };
  return read('tests/fixtures/preferences-ui-harness.m').replace(/\/\* PRODUCTION_(\w+) \*\//g, (_, key) => {
    assert.ok(replacements[key], `Missing harness replacement ${key}`);
    return replacements[key];
  });
}

async function run({ execute = execFileAsync, output = path.join(root, '.audit-artifacts/preferences-ui'), logger = console } = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-uikit-'));
  fs.mkdirSync(output, { recursive: true });
  // Evidence collection must never replace the original command/assertion error.
  const save = (name, contents) => {
    try { fs.appendFileSync(path.join(output, name), contents); }
    catch (error) { logger.error('[UIKit] Cannot save evidence:', error.message); }
  };
  const command = async (args, timeout = 60000) => {
    logger.log('[UIKit]', args.join(' '));
    const started = Date.now();
    try {
      const { stdout, stderr } = await execute('xcrun', args, { encoding: 'utf8', timeout, maxBuffer: 8 * 1024 * 1024 });
      save('commands.log', `${args.join(' ')}\nelapsedMs=${Date.now() - started}, timeoutMs=${timeout}, code=0\n${stdout || ''}\n${stderr || ''}\n`);
      return stdout.trim();
    } catch (error) {
      const metadata = JSON.stringify({ elapsedMs: Date.now() - started, timeoutMs: timeout,
        code: error.code ?? null, signal: error.signal ?? null, killed: !!error.killed });
      const details = `${args.join(' ')}\n${metadata}\n${error.stdout || ''}\n${error.stderr || ''}\n${error.message}\n`;
      logger.error('[UIKit] Command failed:\n' + details);
      save('commands.log', details);
      throw error;
    }
  };
  const initializeSimulator = async () => {
    for (let attempt = 1; attempt <= 2; attempt++) {
      try {
        // The first simctl call initializes CoreSimulator, before a device exists.
        return JSON.parse(await command(['simctl', 'list', 'runtimes', '-j'], 180000)).runtimes;
      } catch (error) {
        // Only retry our own timeout of this read-only discovery command.
        // Nonzero exits, malformed JSON and later test failures remain failures.
        if (attempt === 2 || !error.killed || error.signal !== 'SIGTERM' || error.code !== null) throw error;
        const message = 'CoreSimulator discovery timed out; retrying once with a 180-second deadline.\n';
        logger.error('[UIKit] ' + message);
        save('commands.log', message);
      }
    }
  };
  let device;
  let documents;
  const copyEvidence = () => {
    if (!documents || !fs.existsSync(documents)) return;
    for (const name of fs.readdirSync(documents))
      if (/^(?:report\.json|(?:settings|credits)-.*\.png)$/.test(name))
        fs.copyFileSync(path.join(documents, name), path.join(output, name));
  };
  try {
    save('runner.json', JSON.stringify({ arch: process.arch, node: process.version,
      developerDir: process.env.DEVELOPER_DIR || null, requestedRuntime: process.env.DORH_SIMULATOR_RUNTIME || null }, null, 2));
    const runtimes = await initializeSimulator();
    const runtime = runtimes.find(item => item.isAvailable && item.identifier.includes('.iOS-') &&
      (!process.env.DORH_SIMULATOR_RUNTIME || item.version === process.env.DORH_SIMULATOR_RUNTIME));
    assert.ok(runtime, 'No available iOS Simulator runtime; UIKit check cannot be replaced with source checks.');
    const miniTypes = JSON.parse(await command(['simctl', 'list', 'devicetypes', '-j'])).devicetypes
      .filter(item => item.name.startsWith('iPad mini'));
    const type = miniTypes.find(item => item.name === 'iPad mini (6th generation)') || miniTypes.at(-1);
    assert.ok(type, 'No iPad mini simulator device type.');
    const app = path.join(directory, 'RHLayout.app');
    fs.mkdirSync(app);
    const file = path.join(directory, 'harness.m');
    fs.writeFileSync(file, harnessSource());
    const sdk = await command(['--sdk', 'iphonesimulator', '--show-sdk-path']);
    fs.writeFileSync(path.join(output, 'environment.json'), JSON.stringify({ runtime, type, sdk, arch: process.arch }, null, 2));
    await command(['--sdk', 'iphonesimulator', 'clang', '-fobjc-arc', '-fmodules', '-isysroot', sdk,
      '-target', `${process.arch === 'arm64' ? 'arm64' : 'x86_64'}-apple-ios16.0-simulator`,
      '-framework', 'UIKit', '-framework', 'QuartzCore', file, '-o', path.join(app, 'RHLayout')], 120000);
    fs.writeFileSync(path.join(app, 'Info.plist'), `<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>test.roothide.preferences-layout</string>
<key>CFBundleExecutable</key><string>RHLayout</string>
<key>CFBundleName</key><string>RHLayout</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>MinimumOSVersion</key><string>16.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
</dict></plist>`);
    device = await command(['simctl', 'create', `RHLayout-${process.pid}`, type.identifier, runtime.identifier]);
    assert.match(device, /^[A-F0-9-]{36}$/i);
    await command(['simctl', 'boot', device]);
    await command(['simctl', 'bootstatus', device, '-b'], 180000);
    await command(['simctl', 'install', device, app], 120000);
    const data = await command(['simctl', 'get_app_container', device, 'test.roothide.preferences-layout', 'data']);
    documents = path.join(data, 'Documents');
    // A cold CI simulator can take over a minute to acknowledge the first launch.
    // Keep a bounded launch deadline, separate from the harness's report deadline.
    await command(['simctl', 'launch', device, 'test.roothide.preferences-layout'], 180000);
    const report = path.join(documents, 'report.json');
    const deadline = Date.now() + 90000;
    while (!fs.existsSync(report) && Date.now() < deadline)
      await new Promise(resolve => setTimeout(resolve, 1000));
    assert.ok(fs.existsSync(report), 'UIKit harness timed out or crashed before writing its report.');
    copyEvidence();
    const result = JSON.parse(fs.readFileSync(report, 'utf8'));
    assert.equal(result.status, 'passed', JSON.stringify(result));
    assert.equal(result.viewports, 12);
    assert.equal(result.scrollChecks, 2400);
    logger.log(`UIKit: ${runtime.version}; 12 page/viewport cases, 2400 offset checks; evidence: ${output}`);
  } catch (error) {
    save('failure.log', `${error.stack || error.message}\n`);
    // Preserve reports/screenshots even if launch acknowledgement or an assertion fails.
    try { copyEvidence(); } catch (copyError) { logger.error('[UIKit] Cannot copy evidence:', copyError.message); }
    try {
      const args = device ? [
        'simctl', 'spawn', device, 'log', 'show', '--last', '5m', '--style', 'compact',
        '--predicate', 'eventMessage CONTAINS[c] "test.roothide.preferences-layout" OR eventMessage CONTAINS[c] "RHLayout" OR process == "RHLayout"'
      ] : [
        'show', '--last', '5m', '--style', 'compact', '--predicate',
        'process CONTAINS[c] "CoreSimulator" OR process == "simctl" OR subsystem CONTAINS[c] "CoreSimulator"'
      ];
      const { stdout, stderr } = await execute(device ? 'xcrun' : '/usr/bin/log', args,
        { encoding: 'utf8', timeout: 30000, maxBuffer: 8 * 1024 * 1024 });
      const diagnostics = [stdout, stderr].filter(Boolean).join('\n');
      save('launch-diagnostics.log', diagnostics);
      logger.error('[UIKit] Simulator log (last 24000 characters):\n' + diagnostics.slice(-24000));
    } catch (diagnosticError) {
      save('launch-diagnostics.log', `${diagnosticError.stdout || ''}\n${diagnosticError.stderr || ''}\n${diagnosticError.message}\n`);
    }
    throw error;
  } finally {
    if (device) {
      try { await command(['simctl', 'shutdown', device], 15000); } catch {}
      try { await command(['simctl', 'delete', device], 15000); } catch {}
    }
    try { fs.rmSync(directory, { recursive: true, force: true }); }
    catch (error) { logger.error('[UIKit] Cannot remove temporary harness:', error.message); }
  }
}

module.exports = { run, harnessSource };
