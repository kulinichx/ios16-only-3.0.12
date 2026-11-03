const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');
const { mask } = require('../tests/helpers/source.cjs');

const revision = '9e12b8faa7444f6fe7f699aec6b6c96d151455d3';
const files = ['Makefile', 'src/xpf.c', 'src/common.c', 'src/ppl.c', 'src/non_ppl.c', 'src/cli/main.c'];
const removed = ['src/bad_recovery.c', 'src/bad_recovery.h', 'src/sptm_txm.c', 'src/sptm_txm.h'];

function blockEnd(source, opening) {
  const masked = mask(source);
  let depth = 0;
  for (let i = opening; i < masked.length; i++) {
    if (masked[i] === '{') depth++;
    else if (masked[i] === '}' && --depth === 0) return i + 1;
  }
  throw new Error('Unbalanced XPF block');
}

function replaceOnce(source, before, after) {
  if (!source.includes(before) || source.indexOf(before) !== source.lastIndexOf(before))
    throw new Error(`Missing or ambiguous XPF anchor: ${before}`);
  return source.replace(before, after);
}

function removeFunction(source, name) {
  const match = new RegExp(`^(?:static )?(?:uint64_t|int|bool|PFSection \\*)\\s*${name}\\([^;\\n]*\\)\\s*\\{`, 'm').exec(source);
  if (!match) throw new Error(`Missing XPF function ${name}`);
  const opening = source.indexOf('{', match.index);
  return source.slice(0, match.index) + source.slice(blockEnd(source, opening));
}

function selectBranch(source, condition, keep) {
  const start = source.indexOf(condition);
  if (start < 0) throw new Error(`Missing XPF branch: ${condition}`);
  const opening = source.indexOf('{', start + condition.length);
  const end = blockEnd(source, opening);
  const next = source.slice(end).match(/^\s*else\s*\{/);
  const otherOpening = next ? end + next[0].lastIndexOf('{') : -1;
  const otherEnd = next ? blockEnd(source, otherOpening) : end;
  const replacement = keep ? source.slice(opening, end) :
    next ? source.slice(otherOpening, otherEnd) : '';
  return source.slice(0, start) + replacement + source.slice(otherEnd);
}

function between(source, start, end, replacement) {
  const a = source.indexOf(start);
  const b = source.indexOf(end, a + start.length);
  if (a < 0 || b < 0) throw new Error(`Missing XPF interval: ${start}`);
  return source.slice(0, a) + replacement + source.slice(b);
}

function transformRaw(file, original) {
  let source = original;
  if (file === 'Makefile') return replaceOnce(source, '-miphoneos-version-min=15.0', '-miphoneos-version-min=16.0');
  if (file === 'src/cli/main.c') {
    source = between(source, '\t\tconst char *sptmPath =', '\t\tif (xpf_start_with_kernel_path', '')
      .replace('xpf_start_with_kernel_path(argv[1], sptmPath, txmPath)', 'xpf_start_with_kernel_path(argv[1], NULL, NULL)');
    for (const name of ['badRecovery', 'arm64kcall', 'trigon'])
      source = selectBranch(source, `if (xpf_set_is_supported("${name}"))`, false);
    return source;
  }
  if (file === 'src/xpf.c') {
    const names = [
      ['gBaseSet', 'base'], ['gTranslationSet', 'translation'], ['gPhysmapSet', 'physmap'],
      ['gStructSet_18Down', 'struct'], ['gTrustcache16Set', 'trustcache'], ['gSandboxSet', 'sandbox'],
      ['gPhysRWSet', 'physrw'], ['gPerfKRWSet', 'perfkrw'], ['gDevModeSet', 'devmode'], ['gIOSurfaceSet', 'IOSurface'],
    ];
    const sets = names.map(([symbol]) => {
      const start = source.indexOf(`XPFSet ${symbol} = {`);
      if (start < 0) throw new Error(`Missing XPF set ${symbol}`);
      const end = blockEnd(source, source.indexOf('{', start));
      return source.slice(start, end + 1).replace(/gStructSet_18Down/g, 'gStructSet16')
        .replace(/gTrustcache16Set/g, 'gTrustcacheSet16')
        .replace(/xpf_supported_(?:non_sptm|18_down_incl_26b1|16up_no_sptm|15up|1516)/g, 'xpf_supported_always');
    });
    const imports = source.slice(0, source.indexOf('bool xpf_supported_always(void)'))
      .replace('#include "sptm_txm.h"\n', '').replace('#include "bad_recovery.h"\n', '');
    const heading = `${imports}bool xpf_supported_always(void)\n{\n\treturn true;\n}\n\n` +
      sets.join('\n\n') + '\n\nXPFSet *gSets[] = {\n' +
      names.map(([name]) => `\t&${name.replace('gStructSet_18Down', 'gStructSet16').replace('gTrustcache16Set', 'gTrustcacheSet16')},`).join('\n') +
      '\n};\n\n';
    source = heading + source.slice(source.indexOf('XPF gXPF ='));
    for (const name of ['xpf_sptm_pfsec_init', 'xpf_txm_pfsec_init', 'xpf_load_img4'])
      source = removeFunction(source, name);
    source = between(source, '\tif (optSptmPath) {', '\txpf_ppl_init();', '');
    source = source.replace('\txpf_sptm_txm_init();\n', '').replace('\txpf_bad_recovery_init();\n', '');
    source = replaceOnce(source, '\tgXPF.kernelFd = open(kernelPath, O_RDONLY);',
      '\tif (optSptmPath || optTxmPath) {\n\t\txpf_set_error("This build accepts a kernelcache only");\n\t\treturn -1;\n\t}\n\tgXPF.kernelFd = open(kernelPath, O_RDONLY);');
    source = replaceOnce(source, '\t\tgXPF.darwinVersion = strdup(darwinVersion);',
      '\t\tif (strncmp(darwinVersion, "22.", 3) != 0) {\n\t\t\txpf_set_error("This build requires an iOS 16 kernelcache");\n\t\t\treturn -1;\n\t\t}\n\t\tgXPF.darwinVersion = strdup(darwinVersion);');
    return source;
  }
  if (file === 'src/ppl.c' || file === 'src/non_ppl.c') {
    source = removeFunction(source, 'xpf_find_pmap_image4_trust_caches');
    source = selectBranch(source, 'if (strcmp(gXPF.darwinVersion, "22.0.0") >= 0)', true);
    source = source.replace('// iOS >=16', '// iOS 16');
    source = source.replace('gXPF.kernelIsArm64e && !gXPF.sptm', 'gXPF.kernelIsArm64e');
    source = source.replace('\t\tbool iOS14 = strcmp(gXPF.darwinVersion, "21.0.0") < 0;\n', '')
      .replace('iOS14 ? (void*)(uint32_t)2 : (void*)(uint32_t)1', '(void*)(uint32_t)1')
      .replace('iOS14 ? (void*)(uint32_t)1 : (void*)(uint32_t)2', '(void*)(uint32_t)2');
    return source;
  }
  if (file === 'src/common.c') {
    for (const name of ['xpf_find_task_security_config', 'xpf_find_str_x8_x0_gadget',
      'xpf_find_exception_return', 'xpf_find_kcall_return', 'xpf_find_thread_machine_CpuDatap',
      'xpf_find_thread_machine_kstackptr', 'xpf_find_thread_machine_contextData', 'xpf_find_iorvbar',
      'xpf_find_proc_apply_sandbox', 'xpf_find_mac_label_set']) {
      source = removeFunction(source, name);
      source = source.replace(new RegExp(`^\\s*xpf_item_register\\([^\\n]*, ${name},[^\\n]*\\);\\n`, 'm'), '\n');
    }
    source = selectBranch(source, 'if (!gXPF.sptm)', true);
    source = selectBranch(source, 'if (strcmp(gXPF.darwinVersion, "22.0.0") >= 0)', true);
    source = selectBranch(source, 'if (!corpseReleasedStringAddr)', false);
    source = replaceOnce(source, '\tPFXrefMetric *corseReleasedXrefMetric =',
      '\tXPF_ASSERT(corpseReleasedStringAddr);\n\tPFXrefMetric *corseReleasedXrefMetric =');
    source = selectBranch(source, 'if (!task_collect_crash_info)', false);
    source = between(source, '\t// Handle outlining on iOS 18.4+', '\treturn task_collect_crash_info;', '');
    source = selectBranch(source, 'if (imm == 0)', false);
    source = between(source, '\t__block uint64_t stringAddr = 0;\n\tPFStringMetric *stringMetric = pfmetric_string_init("%s invoked on sleep-mode',
      '\tuint32_t ldrAny = 0, ldrAnyMask = 0;', (() => {
        const a = original.indexOf('static uint64_t xpf_find_vm_reference(');
        const b = original.indexOf('static uint64_t xpf_find_vm_map_pmap(', a);
        let body = original.slice(a, b);
        const c = body.indexOf('\t\tuint32_t inst = 0x120a6d28;');
        const d = body.indexOf('\n\tuint32_t ldrAny = 0', c);
        body = body.slice(c, d);
        body = selectBranch(body, 'if (!andAddr)', false);
        body = body.replace('\t\trefSearchStartAddr = andAddr;', '\t\tuint64_t refSearchStartAddr = andAddr;');
        return body.replace(/\n\t\}\s*$/, '\n').replace(/^\t\t/gm, '\t') + '\n';
      })());
    // Remove the old-only string fallback inside vm_map.pmap, not unrelated generic fallbacks.
    const mapStart = source.indexOf('static uint64_t xpf_find_vm_map_pmap(');
    const mapEnd = source.indexOf('static uint64_t xpf_find_proc_struct_size(', mapStart);
    let map = source.slice(mapStart, mapEnd);
    map = selectBranch(map, 'if (!stringAddr)', false);
    source = source.slice(0, mapStart) + map + source.slice(mapEnd);
    source = selectBranch(source, 'if (!syscallMasksStringAddr)', false);
    source = selectBranch(source, 'if (!syscallMasksStringAddr && gXPF.kernelStringSection && !gXPF.kernelSandboxStringSection)', false);
    source = source.replace('// iOS >=16', '// iOS 16');
    source = source.replace('// The latter is caused by a compiler optimization enabled for some devices on iOS 27.0+',
      '// Keep both instruction encodings as generic size-discovery logic.');
    return source;
  }
  throw new Error(`Unexpected XPF input ${file}`);
}

function transform(file, original) {
  return transformRaw(file, original).replace(/[ \t]+$/gm, '').replace(/\n{3,}/g, '\n\n');
}

function prepareXpf(repository, verifyOnly = false) {
  const directory = path.resolve(repository, 'BaseBin/XPF');
  const git = (...args) => execFileSync('git', ['-C', directory, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  if (git('rev-parse', 'HEAD').trim() !== revision) throw new Error(`XPF must stay pinned to ${revision}`);
  const upstreamFiles = new Set(git('ls-tree', '-r', '--name-only', revision, 'src').trim().split('\n'));
  function inspectSource(relative) {
    for (const entry of fs.readdirSync(path.join(directory, relative), { withFileTypes: true })) {
      const file = `${relative}/${entry.name}`;
      if (entry.isSymbolicLink()) throw new Error(`Unexpected XPF source symlink: ${file}`);
      if (entry.isDirectory()) inspectSource(file);
      else if (/\.(?:c|h|S)$/.test(file) && !upstreamFiles.has(file))
        throw new Error(`Unexpected XPF source file: ${file}`);
    }
  }
  inspectSource('src');
  for (const file of upstreamFiles) {
    if (files.includes(file) || removed.includes(file)) continue;
    const current = fs.readFileSync(path.join(directory, file), 'utf8');
    if (current !== git('show', `${revision}:${file}`))
      throw new Error(`Refusing to overwrite unexpected local XPF changes: ${file}`);
  }
  const outputs = new Map();
  for (const file of [...files, ...removed]) {
    const original = git('show', `${revision}:${file}`);
    const expected = removed.includes(file) ? null : transform(file, original);
    const target = path.resolve(directory, file);
    const current = fs.existsSync(target) ? fs.readFileSync(target, 'utf8') : null;
    if (current !== original && current !== expected)
      throw new Error(`Refusing to overwrite unexpected local XPF changes: ${file}`);
    if (verifyOnly && current !== expected) throw new Error(`XPF is not prepared: ${file}`);
    outputs.set(file, { target, current, expected });
  }
  // Validate every input before mutating any dependency file.
  if (!verifyOnly) for (const { target, current, expected } of outputs.values()) {
    if (current === expected) continue;
    if (expected === null) fs.unlinkSync(target);
    else fs.writeFileSync(target, expected);
  }
  const digest = crypto.createHash('sha256');
  for (const [file, { expected }] of outputs) digest.update(`${file}\0${expected ?? '<removed>'}\0`);
  return { revision, files: outputs.size, sha256: digest.digest('hex') };
}

if (require.main === module) {
  try {
    console.log(JSON.stringify(prepareXpf(path.resolve(__dirname, '..'), process.argv.includes('--verify'))));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = { prepareXpf, transform, revision, files, removed };
