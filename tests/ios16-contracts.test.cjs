const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const exists = (file) => fs.existsSync(path.join(root, file));
const bootstrap = read('Application/Dopamine/Jailbreak/DOBootstrapper.m');
const settings = read('Application/Dopamine/UI/Settings/DOSettingsController.m');
const environment = read('Application/Dopamine/Jailbreak/DOEnvironmentManager.m');
const jailbreaker = read('Application/Dopamine/Jailbreak/DOJailbreaker.m');
const runtime = read('Application/Dopamine/Jailbreak/DORuntimeConfiguration.m');
const project = read('Application/Dopamine.xcodeproj/project.pbxproj');
const makefile = read('Application/Makefile');
const launchd = read('BaseBin/launchdhook/src/roothider.m');
const jbsettings = read('BaseBin/launchdhook/src/jbserver/jbsettings.c');
const info = read('BaseBin/libjailbreak/src/info.h');
const workflow = read('.github/workflows/build.yml');

test('native builds pin Intel macOS and the previously tested Xcode generation', () => {
  assert.match(workflow, /runs-on: macos-26-intel/);
  assert.doesNotMatch(workflow, /runs-on: macos-latest|xcode-version: latest-stable/);
  assert.match(workflow, /XCODE_VERSION: '26\.6'/);
  assert.match(workflow, /xcode-version: \$\{\{ env\.XCODE_VERSION \}\}/);
  assert.match(workflow, /test "\$RUNNER_ARCH" = 'X64'/);
  assert.match(workflow, /test "\$actual_xcode" = "\$XCODE_VERSION"/);
});

test('build provenance records the selected machine and actual toolchain', () => {
  for (const key of [
    'runner_arch', 'runner_image', 'runner_image_version',
    'xcode_requested', 'xcode_selected', 'developer_dir', 'xcode_iphoneos_sdk',
  ]) assert.match(workflow, new RegExp(`echo "${key}=`), key);
  assert.ok(workflow.indexOf('- name: Checkout') < workflow.indexOf('- name: Verify runner and toolchain'));
  assert.ok(workflow.indexOf('- name: Verify runner and toolchain') < workflow.indexOf('- name: Install Procursus'));
  assert.match(workflow, /key: theos-roothide-\$\{\{ runner\.os \}\}-\$\{\{ runner\.arch \}\}/);
});

test('Sileo is the only bundled package-manager choice', () => {
  const choices = read('Application/Dopamine/UI/PkgManagers/PkgManagers.plist');
  assert.equal((choices.match(/<key>Package<\/key>/g) || []).length, 1);
  assert.match(choices, /<string>sileo\.deb<\/string>/);
  for (const source of [choices, bootstrap, settings, project,
    read('Application/Dopamine/UI/Settings/DOLicenseViewController.m')]) {
    assert.doesNotMatch(source, /zebra/i);
  }
  assert.equal(exists('Application/Dopamine/Resources/zebra.deb'), false);
  assert.equal(exists('Application/Dopamine/Resources/LICENSE_Zebra.md'), false);
  assert.equal(exists('Application/Dopamine/Assets.xcassets/Package Managers/Zebra.imageset/Contents.json'), false);
});

test('only the three intended prebuilt debs are copied', () => {
  const allowed = makefile.match(/^IOS16_DEBS = (.+)$/m);
  assert.ok(allowed);
  const packages = allowed[1].split(/\s+/);
  assert.deepEqual(packages, ['sileo.deb', 'roothideapp.deb', 'roothideWhite.deb']);
  for (const file of packages) {
    assert.equal(exists(`Application/Dopamine/Resources/${file}`), true);
  }
  assert.doesNotMatch(makefile, /cp[^\n]*Resources\/\*\.deb/);
  for (const file of ['libkrw-dopamine.deb', 'basebin-link.deb', 'libroot.deb']) {
    assert.ok(project.includes(`${file} in Resources`), `${file} must remain in the Xcode resources`);
  }
});

test('the iOS 16 bootstrap remains and non-16 packages are removed', () => {
  assert.equal(exists('Application/Dopamine/Resources/bootstrap_1900.tar.zst'), true);
  for (const file of [
    'Application/Dopamine/Resources/bootstrap_1800.tar.zst',
    'Application/Dopamine/Resources/launchctl_1_1.2.0_iphoneos-arm64e.deb',
    'Packages/additional/launchctl_1_1.2.0_iphoneos-arm64.deb',
  ]) {
    assert.equal(exists(file), false, file);
  }
  assert.doesNotMatch(project, /bootstrap_1800|launchctl_1_1\.2\.0/);
  assert.doesNotMatch(bootstrap, /shouldInstallLaunchctl|LAUNCHCTL_BUNDLED_VERSION/);
  assert.match(bootstrap, /int getCFMajorVersion\(void\)\s*\{\s*return 1900;/);
  assert.match(makefile, /rm -rf[^\n]*badRecovery\.framework/);
});

test('custom mount entry and automatic restore are absent', () => {
  const header = read('Application/Dopamine/Jailbreak/DORuntimeConfiguration.h');
  for (const source of [settings, runtime, header, jailbreaker]) {
    assert.doesNotMatch(source, /HelloMnt|restoreCustomMounts|installMountAppPressed|cn\.zqbb\.hello\.mnt|\.zqbbJailbreak/);
  }
  assert.match(runtime, /cn\.zqbb\.inject\.system\.plist/);
  assert.match(runtime, /cn\.zqbb\.jetsam\.addend\.plist/);
});

test('TrollStoreLite active fix and standalone TXM modules are absent', () => {
  for (const source of [settings, jailbreaker, launchd, jbsettings, info]) {
    assert.doesNotMatch(source, /trollstore_lite_|trollStoreLiteFix|TrollStoreLite Fix/);
  }
  assert.deepEqual(
    fs.readdirSync(path.join(root, 'BaseBin/launchdhook/src'))
      .filter((file) => file.startsWith('trollstore_lite_')),
    [],
  );
  for (const file of ['txm_trust.c', 'txm_trust.h', 'txm_trust_policy.c']) {
    assert.equal(exists(`BaseBin/libjailbreak/src/${file}`), false);
  }
});

test('normal TrollStore classification and required signing remain', () => {
  assert.match(environment, /stringByAppendingPathComponent:@"_TrollStore"/);
  assert.match(makefile, /ldid -SDopamine\/Dopamine\.entitlements/);
  assert.match(launchd, /roothide_launchd_trust_executable/);
  assert.match(launchd, /roothide_trust_executable_recurse/);
  // Passive recognition avoids treating old Lite apps as ordinary App Store apps.
  assert.match(read('BaseBin/libroothider/src/common.m'), /_TrollStoreLite/);
});

test('UI and activation both reject a non-16 major version', () => {
  assert.match(environment, /isSupported\s*\{\s*if \(NSProcessInfo\.processInfo\.operatingSystemVersion\.majorVersion != 16\) return NO;/);
  const activation = jailbreaker.slice(jailbreaker.indexOf('- (void)runWithError:'));
  const guard = activation.indexOf('operatingSystemVersion.majorVersion != 16');
  assert.ok(guard >= 0 && guard < activation.indexOf('exec_set_patch(false)'));
  assert.match(activation, /This build supports iOS 16 only/);
});

test('app and project Debug/Release deployment targets are iOS 16', () => {
  for (const id of ['8C71982C', '8C71982D', '8C71982F', '8C719830']) {
    const block = project.match(new RegExp(`\\b${id}[A-F0-9]* /\\* (?:Debug|Release) \\*/ = \\{[\\s\\S]*?\\n\\t\\t\\};`));
    assert.ok(block, `${id} configuration missing`);
    assert.match(block[0], /IPHONEOS_DEPLOYMENT_TARGET = 16\.0;/);
  }
  assert.equal((makefile.match(/IPHONEOS_DEPLOYMENT_TARGET=16\.0/g) || []).length, 2);
});

test('ordinary spawn patching and blacklist handling remain connected', () => {
  assert.match(launchd, /jbdSpawnPatchChild\(pid, should_resume\)/);
  assert.match(launchd, /if \(roothideBlacklisted\)/);
  assert.match(launchd, /ret = __posix_spawn_orig_wrapper\(blacklistedPidp, path, desc, argv, envc\)/);
  assert.match(launchd, /commitBlacklistProcessId\(blacklistedPidp\)/);
  assert.match(launchd, /return __posix_spawn_hook\(pidp, path, desc, argv, envp\);/);
  assert.doesNotMatch(launchd, /iOS15Arm64e|choicyBlocked|spinlock_fix_only|SPINLOCK_FIX_DISABLED/);
});

test('RootHide identity and bootstrap migration markers remain intact', () => {
  assert.match(bootstrap, /@implementation DOBootstrapper\(roothide\)/);
  assert.match(bootstrap, /@implementation DOEnvironmentManager\(roothide\)/);
  assert.match(bootstrap, /#define DOPAMINE_INSTALL_VERSION\s+3/);
  assert.match(bootstrap, /ReRandomizeBootstrap/);
  assert.match(bootstrap, /\/var\/containers\/Bundle\/Application\//);
  assert.match(makefile, /Dopamine\.roothide/);
  assert.match(makefile, /cn\.zqbb\.dopaRH/);
});

test('all local quoted includes in modified launchd code still resolve', () => {
  const directory = path.join(root, 'BaseBin/launchdhook/src');
  for (const match of launchd.matchAll(/^\s*#include "([^"]+)"/gm)) {
    assert.ok(fs.existsSync(path.resolve(directory, match[1])), match[1]);
  }
});
