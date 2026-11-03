const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const crypto = require('node:crypto');
const os = require('node:os');
const vm = require('node:vm');
const { execFileSync } = require('node:child_process');
const { parseOpenStep } = require('./helpers/openstep.cjs');
const { modelOffsets, offsetCases } = require('./helpers/offset-model.cjs');
const { mask, ownedSources } = require('./helpers/source.cjs');
const { prepareXpf, revision: xpfRevision, removed: removedXpf } = require('../scripts/prepare-xpf-ios16.cjs');

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

test('iOS 16 build creates and publishes only a TIPA archive', () => {
  assert.match(makefile, /^all:\s+Dopamine\.tipa$/m);
  assert.match(makefile, /^Dopamine\.tipa:\s+build\/Build\/Products\/Debug-iphoneos\/Dopamine\.app$/m);
  assert.match(makefile, /zip -Ar Dopamine\.tipa Payload/);
  assert.doesNotMatch(makefile, /^all:\s+Dopamine\.ipa$|^Dopamine\.ipa:/m);
  assert.doesNotMatch(makefile, /zip .*Dopamine\.ipa/);

  const buildStep = workflow.slice(workflow.indexOf('      - name: Build\n'));
  assert.match(buildStep, /mv \.\/Application\/Dopamine\.tipa/);
  assert.match(buildStep, /- name: Verify TIPA/);
  assert.match(buildStep, /unzip -tq "\$tipa"/);
  assert.match(buildStep, /name: RootHide_iOS16_TIPA/);
  assert.match(buildStep, /roothide-Dopamine-\$\{\{ env\.version \}\}\.tipa/);
  assert.doesNotMatch(buildStep, /\.ipa|RootHide_iOS16_IPA/);
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
  assert.match(makefile, /FAIL: unexpected framework/);
  assert.doesNotMatch(project, /badRecovery|multicast_bytecopy|(?:path|name) = weightBufs;/);
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

const retainedExploits = ['ClearSword', 'DarkSword', 'Titan', 'dmaFail', 'kfd', 'momentarius'];
const retiredPaths = [
  ...['badRecovery', 'weightBufs', 'multicast_bytecopy', 'palera1n'].map(name => `Application/Dopamine/Exploits/${name}`),
  'BaseBin/hookd', 'BaseBin/dyldhook/src/generated/ios15', 'BaseBin/dyldhook/src/generated/ios18+',
  'BaseBin/dyldhook/src/spinlock_fix.c', 'BaseBin/dyldhook/src/fakelib_redirect.c',
  'BaseBin/roothidehooks/src/palera1n.x', 'BaseBin/forkfix/src/reimpl.c.disabled',
  ...['stock_fixes', 'txm', 'hookd', 'kcall_arm64', 'kcall_Fugu14'].flatMap(name =>
    ['c', 'h'].map(ext => `BaseBin/libjailbreak/src/${name}.${ext}`)),
  'BaseBin/libjailbreak/src/kcall_Fugu14.S',
  'BaseBin/libjailbreak/src/memory_hooks.h',
  ...['c', 'h'].map(ext => `BaseBin/launchdhook/src/hookd_provider.${ext}`),
  ...['c', 'h'].map(ext => `BaseBin/systemhook/src/common/hookd_external.${ext}`),
  'BaseBin/systemhook/src/common/memory_hooks.c',
  'Application/Dopamine/Exploits/kfd/Exploit/libkfd/krkw/IOSurface_shared.h',
  'Application/Dopamine/Exploits/kfd/Exploit/libkfd/krkw/kread/kread_IOSurface.h',
  'Application/Dopamine/Exploits/kfd/Exploit/libkfd/krkw/kwrite/kwrite_IOSurface.h',
];

test('obsolete modules are physically removed, not merely deleted after building', () => {
  for (const file of retiredPaths) assert.equal(exists(file), false, file);
  assert.deepEqual(fs.readdirSync(path.join(root, 'Application/Dopamine/Exploits')).sort(), retainedExploits);
  const allowed = makefile.match(/^IOS16_EXPLOITS = (.+)$/m)[1].split(/\s+/).sort();
  assert.deepEqual(allowed, retainedExploits);
  assert.doesNotMatch(read('BaseBin/Makefile'), /^hookd:|make\) -C hookd|launchdhook hookd/m);
});

test('libjailbreak wildcard inputs include required assembly but no retired kcall implementation', () => {
  const directory = 'BaseBin/libjailbreak/src';
  assert.match(read('BaseBin/libjailbreak/Makefile'), /\$\(wildcard src\/\*\.c src\/\*\.m src\/\*\.S /);
  const inputs = fs.readdirSync(path.join(root, directory)).filter(file => /\.(?:c|m|S)$/.test(file));
  assert.ok(inputs.includes('inline_svc.S'), 'Keep the required syscall assembly');
  for (const file of inputs) {
    assert.doesNotMatch(file, /^(?:kcall_Fugu14|kcall_arm64|hookd|stock_fixes|txm)\./, file);
    assert.doesNotMatch(mask(read(`${directory}/${file}`)), /\b_?(?:gUserReturnDidHappen|pac_loop)\b/, file);
  }
});

test('Xcode project has no dangling object references and only the intended native targets', () => {
  const parsed = parseOpenStep(project).value;
  const objects = parsed.objects;
  function visit(value) {
    if (Array.isArray(value)) return value.forEach(visit);
    if (value && typeof value === 'object') {
      for (const [key, child] of Object.entries(value)) {
        if (/^[A-F0-9]{24}$/.test(key)) assert.ok(objects[key], `Missing keyed object ${key}`);
        visit(child);
      }
    } else if (/^[A-F0-9]{24}$/.test(value)) assert.ok(objects[value], `Missing referenced object ${value}`);
  }
  visit(parsed);
  const targets = Object.values(objects).filter(object => object.isa === 'PBXNativeTarget').map(object => object.name).sort();
  assert.deepEqual(targets, [...retainedExploits, 'Dopamine'].sort());
  for (const object of Object.values(objects)) {
    if (object.buildSettings?.IPHONEOS_DEPLOYMENT_TARGET)
      assert.equal(object.buildSettings.IPHONEOS_DEPLOYMENT_TARGET, '16.0');
  }
});

test('all exploit metadata version ranges and beta exceptions are restricted to iOS 16', () => {
  for (const name of retainedExploits) {
    const plist = read(`Application/Dopamine/Exploits/${name}/Info.plist`);
    const boundaries = [...plist.matchAll(/<key>(?:Start|End)<\/key>\s*<string>([^<]+)<\/string>/g)];
    assert.ok(boundaries.length >= 2, name);
    for (const boundary of boundaries) assert.match(boundary[1], /^16\.\d+(?:\.\d+)?$/, `${name}: ${boundary[1]}`);
    for (const build of plist.matchAll(/<string>(\d{2}[A-Z]\d+[^<]*)<\/string>/g))
      assert.match(build[1], /^20[A-Z]/, `${name}: ${build[1]}`);
    assert.doesNotMatch(plist, /<string>A(?:7|8|17|18)<\/string>/);
  }
  assert.match(workflow, /plutil -lint "\$plist"/);
});

test('only the two iOS 16 dyldhook variants can be built, selected and packaged', () => {
  const dyldMake = read('BaseBin/dyldhook/Makefile');
  const baseMake = read('BaseBin/Makefile');
  const selector = read('BaseBin/libjailbreak/src/basebin_gen.m');
  for (const architecture of ['arm64', 'arm64e']) {
    const filename = `dyldhook_merge.${architecture}.iOS16-17.dylib`;
    assert.ok(dyldMake.includes(filename));
    assert.ok(baseMake.includes(`dyldhook/${filename}`));
    assert.ok(selector.includes(`@"${filename}"`));
  }
  assert.doesNotMatch(dyldMake + selector, /iOS15|iOS18|DIOS=(?:15|18)/);
  assert.doesNotMatch(baseMake, /cp dyldhook\/\*\.dylib/);
  assert.match(workflow, /unzip -p "\$tipa" Payload\/Dopamine\.app\/basebin\.tar/);
  assert.match(workflow, /expected_frameworks='ClearSword DarkSword Titan dmaFail kfd momentarius'/);
  assert.match(workflow, /expected_frameworks="\$\(printf '%s\\n' \$expected_frameworks \| sort -u \| paste -sd ' ' -\)"/);
  assert.match(workflow, /actual_frameworks="\$\(sed -nE .* \| sort -u \| paste -sd ' ' -\)"/);
  assert.match(workflow, /grep -Ec '\^basebin\/dyldhook/);
});

test('144 modeled iOS 16 offset combinations match the pre-pruning assignment baseline', () => {
  const cases = offsetCases();
  assert.equal(cases.length, 144);
  const source = read('BaseBin/libjailbreak/src/offsets_ios16.c');
  const results = cases.map(input => ({ input, offsets: modelOffsets(source, input) }));
  const digest = crypto.createHash('sha256').update(JSON.stringify(results)).digest('hex');
  assert.equal(digest, 'ab5d4bde72e285447fc4e3812e211592c7f0a4774fe4a69c372888c38be6f06b');
  assert.doesNotMatch(source, /"(?:21|23|24|25)\.\d+\.\d+"/);
  assert.match(source, /"22\.1\.0"/);
  assert.match(source, /"22\.3\.0"/);
  assert.match(source, /"22\.4\.0"/);
});

test('first-party runtime has no non-16 availability dispatch or removed module references', () => {
  for (const file of ownedSources(root)) {
    const source = mask(read(file), false);
    for (const match of source.matchAll(/(?:@available|__builtin_available)\(iOS (\d+)(?:\.\d+)?,/g))
      assert.equal(match[1], '16', `${file}: ${match[0]}`);
    assert.doesNotMatch(source, /\b(?:SPTMArgs|ksymbol_sptm|ksymbol_txm|txm_address_space|hookd_send_msg|hookd_provider_init|init_hookd_external_support|proc_fix_spinlock|jbdSpinlockFixOnly|arm64_kcall_init|fugu14_kcall_init|kread_IOSurface|kwrite_IOSurface|proc__task|SOC_A17|XNU_MAJOR_GREATER_THAN)\b/, file);
    assert.doesNotMatch(source, /major\s*>=\s*17|majorVersion\s*==\s*(?:15|17|18|19)/, file);
    assert.doesNotMatch(source, /DYLD_SHARED_REGION|__ZN5dyld45gAPIsE/, file);
    assert.doesNotMatch(source, /\b(?:IOSurface_kalloc_15|IOSurface_kalloc_getSurfacePort_15|crashBackboardd_15|isA18Device|is_a18_devices|CPUFAMILY_ARM_TYPHOON|CPUFAMILY_ARM_COLL|CPUFAMILY_ARM_TUPAI|CPUFAMILY_ARM_TAHITI|CPUFAMILY_ARM_IBIZA|CPUFAMILY_ARM_DONAN)\b/, file);
  }
});

test('settings switch styling preserves the iOS 16 tint without a higher-version branch', () => {
  const source = read('Application/Dopamine/UI/Settings/PSLists/DOPSListController.m');
  const style = source.slice(source.indexOf('+ (void)setupViewControllerStyle:'),
    source.indexOf('- (void)tableView:'));
  assert.match(style, /vc\.view\.backgroundColor = theme\.windowColor;/);
  assert.match(style, /\[UISwitch appearanceWhenContainedInInstancesOfClasses:@\[\[vc class\]\]\]\.onTintColor = \[UIColor colorWithRed: 71\.0\/255\.0 green: 169\.0\/255\.0 blue: 135\.0\/255\.0 alpha: 1\.0\];/);
  assert.doesNotMatch(mask(style), /@available|__builtin_available|\b(?:if|else)\b/);
});

test('DarkSword retains its own required IOSurface helpers without the retired kfd backend', () => {
  const exploit = read('Application/Dopamine/Exploits/DarkSword/DarkSword.m');
  const helpers = read('Application/Dopamine/Exploits/DarkSword/IOSurface_helpers.h');
  assert.match(exploit, /#include "IOSurface_helpers\.h"/);
  for (const symbol of ['surface_check_result', 'get_surface_client', 'create_surface_fast_path',
    'iosurface_get_use_count', 'set_indexed_timestamp'])
    assert.ok(helpers.includes(symbol), symbol);
  assert.doesNotMatch(exploit, /iPhone17,|pe_v2|isA18Device/);
  assert.doesNotMatch(read('Application/Dopamine/Exploits/ClearSword/exploit/poc.c'), /iPhone17,|is_a18_devices|A18/);
  // The surviving helper is derived from weightBufs; attribution is still required.
  assert.equal(exists('Application/Dopamine/Resources/LICENSE_weightBufs.md'), true);
  assert.match(project, /LICENSE_weightBufs\.md in Resources/);
});

test('IOSurface allocation and hardware selection retain only iOS 16 paths', () => {
  const allocation = read('BaseBin/libjailbreak/src/primitives_IOSurface.m');
  assert.match(allocation, /IOSurface_kalloc_16\(size, true\)/);
  assert.match(allocation, /IOSurface_kalloc_16\(size, false\)/);
  assert.match(jailbreaker, /\[self crashBackboardd\];/);
  const selection = read('Application/Dopamine/Jailbreak/DOExploit.m');
  assert.match(selection, /NSString \*thisCPU = @"unknown";/);
  assert.doesNotMatch(selection, /@"A(?:8|17|18)"/);
  assert.doesNotMatch(read('BaseBin/libroothider/src/xpc_hook.m'), /"\$\(PRODUCT_BUNDLE_IDENTIFIER\)"/);
});

test('DOJailbreaker declares the pthread API it uses', () => {
  const source = read('Application/Dopamine/Jailbreak/DOJailbreaker.m');
  assert.match(source, /#import <pthread\.h>/);
  assert.match(source, /pthread_create\(/);
  assert.match(source, /pthread_detach\(/);
});

test('remaining kernel field macros refer to the surviving serialized schema', () => {
  const fields = new Set([...info.matchAll(/iterator\(ctx,\s*([\w.]+)\)/g)].map(match => match[1]));
  assert.ok(fields.size > 150);
  for (const file of ownedSources(root)) {
    if (file === 'BaseBin/libjailbreak/src/info.h') continue;
    for (const match of mask(read(file)).matchAll(/\b(koffsetof|ksizeof|ksymbol|kgadget|kconstant)\(\s*(\w+)\s*(?:,\s*(\w+)\s*)?\)/g)) {
      const [_, kind, name, member] = match;
      const field = kind === 'koffsetof' ? `kernelStruct.${name}.${member}` :
        kind === 'ksizeof' ? `kernelStruct.${name}.struct_size` :
        `${{ ksymbol: 'kernelSymbol', kgadget: 'kernelGadget', kconstant: 'kernelConstant' }[kind]}.${name}`;
      assert.ok(fields.has(field), `${file}: ${field}`);
    }
  }
});

test('quoted includes resolve through local sources, app header maps or build include roots', () => {
  const files = ownedSources(root);
  const appHeaders = new Set(files.filter(file => file.startsWith('Application/') && file.endsWith('.h'))
    .map(file => path.basename(file)));
  const includeRoots = [
    'BaseBin/.include', 'BaseBin/_external/include', 'BaseBin/_external/modules/litehook/src',
    'BaseBin/libjailbreak/src', 'BaseBin/libroothider/src', 'BaseBin/ChOma/include', 'BaseBin/XPF/src',
    'Application/Dopamine/Headers',
  ];
  for (const file of files) {
    for (const match of mask(read(file), false).matchAll(/^\s*#(?:include|import)\s+"([^"]+)"/gm)) {
      const header = match[1];
      // The existing app uses a quoted system SDK header.
      if (header === 'spawn.h') continue;
      if (file.startsWith('Application/') && !header.includes('/') && appHeaders.has(header)) continue;
      const candidates = [path.resolve(root, path.dirname(file), header),
        ...includeRoots.map(directory => path.resolve(root, directory, header))];
      assert.ok(candidates.some(candidate => fs.existsSync(candidate)), `${file}: ${header}`);
    }
  }
});

test('source masking handles escaped newlines without hiding later compatibility branches', () => {
  const sample = '#define SOURCES "line one\\\nline two"\nif (@available(iOS 18.0, *)) { old(); }\n';
  const masked = mask(sample);
  assert.ok(masked.includes('@available(iOS 18.0, *)'));
  assert.equal(masked.includes('line two'), false);
  assert.equal(masked.split('\n').length, sample.split('\n').length);
});

const upstreamXpf = file => execFileSync('git', ['-C', path.join(root, 'BaseBin/XPF'),
  'show', `${xpfRevision}:${file}`], { encoding: 'utf8' });

test('the pinned XPF dependency is actually pruned and prepared before both native and source-only builds', () => {
  const result = prepareXpf(root, true);
  assert.equal(result.sha256, '33146b2a9e12f1f3eeba1426580e45e4e6b51dae5158f7cd60c3d1c8bd2b45c3');
  for (const file of removedXpf) assert.equal(exists(`BaseBin/XPF/${file}`), false, file);
  const xpf = read('BaseBin/XPF/src/xpf.c');
  assert.match(xpf, /strncmp\(darwinVersion, "22\.", 3\) != 0/);
  assert.match(xpf, /if \(optSptmPath \|\| optTxmPath\)/);
  assert.equal(read('BaseBin/XPF/src/xpf.h'), upstreamXpf('src/xpf.h'), 'Preserve the public ABI layout');
  const sources = ['xpf.c', 'common.c', 'ppl.c', 'non_ppl.c', 'cli/main.c']
    .map(file => read(`BaseBin/XPF/src/${file}`));
  for (const source of sources) {
    assert.doesNotMatch(mask(source, false), /badRecovery|arm64kcall|gXPF\.(?:sptm|txm)\b|xpf_supported_(?!always\b)\w+|xpf_sptm_txm_init/);
    assert.doesNotMatch(source, /iOS (?:14|15|17|18|19|26|27)\b/);
    const stack = [];
    for (const token of mask(source)) {
      if ('({['.includes(token)) stack.push(token);
      else if (')}]'.includes(token)) assert.equal(stack.pop(), { ')': '(', '}': '{', ']': '[' }[token]);
    }
    assert.equal(stack.length, 0);
  }
  assert.doesNotMatch(read('BaseBin/libroothider/src/xpf.m'), /xpf_supported_16up/);
  assert.match(read('BaseBin/Makefile'), /XPF:[^\n]*\n\t@node \.\.\/scripts\/prepare-xpf-ios16\.cjs/);
  assert.equal((workflow.match(/node scripts\/prepare-xpf-ios16\.cjs\n/g) || []).length, 2);
  assert.match(workflow, /--verify >> build-provenance\.txt/);
  assert.match(workflow, /nm -gj "\$RUNNER_TEMP\/ios16-libxpf\.dylib"/);
});

test('all ten retained XPF metric lists exactly match their upstream iOS 16 sets', () => {
  const original = upstreamXpf('src/xpf.c');
  const current = read('BaseBin/XPF/src/xpf.c');
  const names = ['gBaseSet', 'gTranslationSet', 'gPhysmapSet', 'gStructSet_18Down', 'gTrustcache16Set',
    'gSandboxSet', 'gPhysRWSet', 'gPerfKRWSet', 'gDevModeSet', 'gIOSurfaceSet'];
  assert.equal((current.match(/^XPFSet \w+ = \{/gm) || []).length, names.length);
  const metrics = (source, symbol) => {
    const block = source.split(`XPFSet ${symbol} = {`)[1]?.split('\n};')[0];
    assert.ok(block, symbol);
    return [...block.matchAll(/"(kernel[^"]+)"/g)].map(match => match[1]);
  };
  for (const symbol of names) {
    const renamed = symbol.replace('gStructSet_18Down', 'gStructSet16').replace('gTrustcache16Set', 'gTrustcacheSet16');
    assert.deepEqual(metrics(current, renamed), metrics(original, symbol), symbol);
  }
});

test('XPF PPL and non-PPL registration models preserve 28 iOS 16 architecture/version combinations', () => {
  function registrations(source, name, arm64e, darwin) {
    let body = source.slice(source.indexOf(`void ${name}(void)`));
    body = mask(body.slice(body.indexOf('{')), false)
      .replace(/\(void\s*\*\)\s*\(uint32_t\)/g, '')
      .replace(/\bbool\b/g, 'let').replace(/\bNULL\b/g, 'null');
    const results = [];
    const context = {
      gXPF: { kernelIsArm64e: arm64e, darwinVersion: darwin, sptm: null },
      strcmp: (a, b) => a === b ? 0 : a > b ? 1 : -1,
      xpf_item_register: (name, finder, context) => results.push([name, finder, context]),
    };
    for (const match of body.matchAll(/xpf_item_register\("[^"]+",\s*(\w+),/g)) context[match[1]] = match[1];
    vm.runInNewContext(body, context, { timeout: 1000 });
    return results;
  }
  for (const file of ['ppl', 'non_ppl']) {
    const original = upstreamXpf(`src/${file}.c`);
    const current = read(`BaseBin/XPF/src/${file}.c`);
    for (const arm64e of [false, true]) for (const minor of [0, 1, 2, 3, 4, 5, 6]) {
      const darwin = `22.${minor}.0`;
      assert.deepEqual(registrations(current, `xpf_${file}_init`, arm64e, darwin),
        registrations(original, `xpf_${file}_init`, arm64e, darwin), `${file}: ${arm64e}, ${darwin}`);
    }
  }
});

test('XPF preparation reproduces a pristine checkout, is idempotent and refuses unrelated edits', t => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'dopamine-xpf-ios16-'));
  t.after(() => {
    assert.ok(path.dirname(temporary) === path.resolve(os.tmpdir()));
    assert.ok(path.basename(temporary).startsWith('dopamine-xpf-ios16-'));
    fs.rmSync(temporary, { recursive: true, force: true });
  });
  const target = path.join(temporary, 'BaseBin/XPF');
  fs.mkdirSync(path.dirname(target), { recursive: true });
  execFileSync('git', ['clone', '--quiet', '--no-hardlinks', '--no-checkout',
    path.join(root, 'BaseBin/XPF'), target], { stdio: 'pipe' });
  execFileSync('git', ['-C', target, '-c', 'core.autocrlf=false', 'checkout', '--quiet', '--detach', xpfRevision], { stdio: 'pipe' });
  const first = prepareXpf(temporary);
  assert.deepEqual(prepareXpf(temporary), first);
  assert.deepEqual(prepareXpf(temporary, true), first);
  const file = path.join(target, 'src/ppl.c');
  fs.appendFileSync(file, '\n// Unrelated local modification for the refusal test.\n');
  const untouched = fs.readFileSync(file, 'utf8');
  assert.throws(() => prepareXpf(temporary), /Refusing to overwrite unexpected local XPF changes/);
  assert.equal(fs.readFileSync(file, 'utf8'), untouched);
  fs.writeFileSync(file, read('BaseBin/XPF/src/ppl.c'));
  fs.writeFileSync(path.join(target, 'src/unexpected.c'), '// Test-only unexpected source.\n');
  assert.throws(() => prepareXpf(temporary), /Unexpected XPF source file/);
});

test('removed protocol endpoints leave surviving message IDs unchanged', () => {
  const mach = read('BaseBin/libjailbreak/src/jbserver.h');
  for (const [name, id] of [['CHECKIN', 0], ['FORK_FIX', 1], ['TRUST_FILE', 2]])
    assert.match(mach, new RegExp(`#define JBSERVER_MACH_${name} ${id}\\b`));
  const header = read('BaseBin/libroothider/src/jailbreakd.h');
  assert.doesNotMatch(header + read('BaseBin/jailbreakd/src/server.m'), /SPINLOCK_FIX_ONLY/);
  for (const [name, id] of [['SPAWN_PATCH_CHILD', 1001], ['SPAWN_EXEC_START', 1002], ['SPAWN_EXEC_CANCEL', 1003]])
    assert.match(header, new RegExp(`JBD_MSG_${name}\\s*=\\s*${id}\\b`));
});

test('owned runtime source has balanced delimiters and no includes of retired modules', () => {
  const retiredNames = new Set(retiredPaths.map(file => path.basename(file)));
  for (const file of ownedSources(root)) {
    const source = read(file);
    const stack = [];
    const masked = mask(source);
    for (const [offset, token] of [...masked].entries()) {
      if ('({['.includes(token)) stack.push(token);
      else if (')}]'.includes(token))
        assert.equal(stack.pop(), ({ ')': '(', '}': '{', ']': '[' })[token], `${file}:${offset}`);
    }
    assert.equal(stack.length, 0, file);
    for (const match of source.matchAll(/^\s*#(?:include|import)\s+[<"]([^>"]+)[>"]/gm))
      assert.equal(retiredNames.has(path.basename(match[1])), false, `${file}: ${match[1]}`);
  }
});
