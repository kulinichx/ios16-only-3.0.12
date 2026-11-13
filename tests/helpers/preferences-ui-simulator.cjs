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

async function run() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-uikit-'));
  const output = path.join(root, '.audit-artifacts/preferences-ui');
  fs.mkdirSync(output, { recursive: true });
  const command = async (args, timeout = 60000) => {
    console.log('[UIKit]', args.join(' '));
    try {
      const { stdout } = await execFileAsync('xcrun', args, { encoding: 'utf8', timeout, maxBuffer: 8 * 1024 * 1024 });
      return stdout.trim();
    } catch (error) {
      fs.appendFileSync(path.join(output, 'commands.log'), `${args.join(' ')}\n${error.stdout || ''}\n${error.stderr || ''}\n${error.message}\n`);
      throw error;
    }
  };
  let device;
  try {
    const runtimes = JSON.parse(await command(['simctl', 'list', 'runtimes', '-j'])).runtimes;
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
    await command(['simctl', 'launch', device, 'test.roothide.preferences-layout']);
    const data = await command(['simctl', 'get_app_container', device, 'test.roothide.preferences-layout', 'data']);
    const documents = path.join(data, 'Documents');
    const report = path.join(documents, 'report.json');
    const deadline = Date.now() + 90000;
    while (!fs.existsSync(report) && Date.now() < deadline)
      await new Promise(resolve => setTimeout(resolve, 1000));
    assert.ok(fs.existsSync(report), 'UIKit harness timed out or crashed before writing its report.');
    fs.mkdirSync(output, { recursive: true });
    for (const name of fs.readdirSync(documents))
      if (/^(?:report\.json|(?:settings|credits)-.*\.png)$/.test(name))
        fs.copyFileSync(path.join(documents, name), path.join(output, name));
    const result = JSON.parse(fs.readFileSync(report, 'utf8'));
    assert.equal(result.status, 'passed', JSON.stringify(result));
    assert.equal(result.viewports, 12);
    assert.equal(result.scrollChecks, 2400);
    console.log(`UIKit: ${runtime.version}; 12 page/viewport cases, 2400 offset checks; evidence: ${output}`);
  } finally {
    if (device) {
      try { await command(['simctl', 'shutdown', device], 15000); } catch {}
      try { await command(['simctl', 'delete', device], 15000); } catch {}
    }
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

module.exports = { run, harnessSource };
