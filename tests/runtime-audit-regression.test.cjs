const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const {execFileSync} = require('node:child_process');
const {mask} = require('./helpers/source.cjs');
const root = path.resolve(__dirname, '..');
const read = f => fs.readFileSync(path.join(root, f), 'utf8');
function productionFunction(file, signature) {
  const source = read(file), masked = mask(source), start = source.indexOf(signature);
  assert.ok(start >= 0, signature);
  const brace = masked.indexOf('{', start + signature.length);
  let depth = 1;
  for (let i = brace + 1; i < masked.length; i++) {
    if (masked[i] === '{') depth++;
    if (masked[i] === '}' && --depth === 0) return source.slice(start, i + 1);
  }
  assert.fail(`Unclosed function ${signature}`);
}

function argumentArrays() {
  const directory = 'BaseBin/launchdhook/src/jbserver';
  const files = fs.readdirSync(path.join(root, directory)).filter(f => /^jbdomain_.*\.c$/.test(f))
    .map(f => `${directory}/${f}`).concat('BaseBin/libjailbreak/src/jbserver_boomerang.c');
  return files.flatMap(file => [...read(file).matchAll(/\.handler\s*=\s*(\w+),\s*\.args\s*=\s*\(jbserver_arg\[\]\)\s*(\{[\s\S]*?\n\s*\}),/g)]
    .map(match => ({file, handler:match[1], source:match[2]})));
}

test('all production pointer argument arrays terminate within their own allocation', () => {
  const arrays = argumentArrays();
  assert.equal(arrays.length, 38, 'review all current domain argument declarations');
  for (const {file, handler, source} of arrays) {
    assert.match(mask(source), /\{\s*0\s*\},?\s*\}$/, `${file}: ${handler}`);
    const entries = [...source.matchAll(/\.name\s*=/g)].length;
    assert.ok(entries < 8, `${handler} must leave room for its terminator`);
  }
});

function nativeFixture(t, name, fixture, substitutions, options = {}) {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), `rh-${name}-`));
  t.after(() => fs.rmSync(temp, {recursive:true, force:true}));
  let source = read(`tests/fixtures/${fixture}`);
  for (const [marker, value] of Object.entries(substitutions)) {
    assert.ok(source.includes(marker), marker);
    source = source.replace(marker, value);
  }
  const sourcePath = path.join(temp, fixture), binary = path.join(temp, 'test');
  if (options.directory) fs.mkdirSync(path.join(temp,'files'));
  fs.writeFileSync(sourcePath, source);
  const objc = fixture.endsWith('.m');
  execFileSync('xcrun', ['clang', '-fblocks', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
    '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
    ...(objc ? ['-fobjc-arc'] : ['-std=gnu11']), sourcePath,
    ...(objc ? ['-framework', 'Foundation'] : []), ...(options.flags || []), '-o', binary], {stdio:'pipe'});
  execFileSync(binary, options.directory ? [path.join(temp, 'files')] : [], {stdio:'pipe', timeout:30000});
}
const darwinOnly = {skip: process.platform !== 'darwin' ? 'Requires macOS native libraries and compiler.' : false};
test('production process virtual writes call the page-table writer rather than recursing', darwinOnly, t => {
  nativeFixture(t,'proc-vwrite','proc-vwrite-harness.c', {
    '/* PRODUCTION_PROC_VWRITE */': productionFunction('BaseBin/libjailbreak/src/primitives.c','int proc_vwritebuf('),
  });
});
test('production spawn pre/post hooks preserve initialization and syscall failures across cleanup', darwinOnly, t => {
  nativeFixture(t,'spawn-posthook','spawn-posthook-harness.c', {
    '/* PRODUCTION_ENVBUF */': read('BaseBin/systemhook/src/common/envbuf.c'),
    '/* PRODUCTION_POSTHOOK */': ['int roothide_systemhook___posix_spawn_prehook(', 'int roothide_systemhook___posix_spawn_posthook(']
      .map(s => productionFunction('BaseBin/systemhook/src/roothider_main.c',s)).join('\n'),
  });
});
test('production basebin trust collection never uploads a partial result after a file or allocation failure', darwinOnly, t => {
  nativeFixture(t, 'basebin-collection', 'basebin-collection-harness.m', {
    '/* PRODUCTION_BASEBIN */': productionFunction('BaseBin/libroothider/src/common.m', 'int randomizeAndLoadBasebinTrustcache('),
  }, {directory:true});
});
test('production spawn preserves errno after cleanup and suspended-child debug IPC', darwinOnly, t => {
  const file = 'BaseBin/systemhook/src/common/common.c';
  const offsets = read('BaseBin/systemhook/src/common/private.h')
    .match(/^#define POSIX_SPAWNATTR_OFF_MEMLIMIT_(?:ACTIVE|INACTIVE) .+$/gm).join('\n');
  nativeFixture(t, 'spawn-errno', 'spawn-errno-harness.c', {
    '/* PRODUCTION_ENVBUF */': read('BaseBin/systemhook/src/common/envbuf.c'),
    '/* PRODUCTION_SPAWN */': offsets + '\n' + ['void string_enumerate_components(', 'static int spawn_exec_hook_common(', 'int posix_spawn_hook_shared(']
      .map(s => productionFunction(file,s)).join('\n'),
  });
});
test('production job cache bounds retention and keeps active UTF8String owners alive during concurrent eviction', darwinOnly, t => {
  nativeFixture(t, 'job-cache', 'job-cache-harness.m', {
    '/* PRODUCTION_CACHE */': productionFunction('BaseBin/libroothider/src/xpc_hook.m','NSDictionary* cachedJobInfo('),
  });
});
test('production App and jbctl synchronize a real child after privilege restoration and reject broken handshakes', darwinOnly, t => {
  const jbctl = read('BaseBin/jbctl/src/main.m');
  const start = jbctl.indexOf("char release = 0;"), end = jbctl.indexOf("if (received != sizeof(release) || release != 'w') return 1;", start);
  assert.ok(start >= 0 && end > start);
  nativeFixture(t, 'jbctl-launch', 'jbctl-launch-harness.m', {
    '/* PRODUCTION_LAUNCH */': productionFunction('Application/Dopamine/Jailbreak/DOEnvironmentManager.m','- (int)spawnJbctlAsRootWithArgs:'),
    '/* PRODUCTION_WAIT */': jbctl.slice(start, end) + "if (received != sizeof(release) || release != 'w') return 1;",
  });
});
test('production libarchive extraction preserves supported links and propagates traversal and writer errors', darwinOnly, t => {
  const util = 'BaseBin/libjailbreak/src/util.c';
  const prefix = execFileSync('brew',['--prefix','libarchive'],{encoding:'utf8'}).trim();
  nativeFixture(t, 'archive-extraction', 'archive-extraction-harness.c', {
    '/* PRODUCTION_ARCHIVE */': 'static int\n' + productionFunction(util,'copy_data(') + '\n' +
      productionFunction(util,'static int prepare_extraction_path(') + '\n' + productionFunction(util,'int libarchive_unarchive('),
  }, {directory:true, flags:['-I',path.join(prefix,'include'),'-L',path.join(prefix,'lib'),'-larchive']});
});

test('spawn inputs use independent token state and owned configuration values', () => {
  const source = read('BaseBin/systemhook/src/common/common.c');
  assert.doesNotMatch(mask(source), /\bstrtok\s*\(|static\s+xpc_object_t\s+configDict|jbuserconfig_get_value/);
  assert.match(source, /#include <libroothider\/_configuration.h>/);
  assert.match(source, /if \(blacklistedPath && !strcmp/);
});

test('production spawn inputs survive nested enumeration, atomic replacement and concurrent readers', {
  skip: process.platform !== 'darwin' ? 'Requires macOS clang/Blocks/XPC; no process hooks are installed.' : false,
}, t => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-spawn-inputs-'));
  t.after(() => fs.rmSync(temp, {recursive:true, force:true}));
  const file = 'BaseBin/systemhook/src/common/common.c';
  const functions = ['void string_enumerate_components(',
    'static XPC_RETURNS_RETAINED xpc_object_t jbuserconfig_copy_value(',
    'static kSpawnConfig spawn_config_for_executable('];
  const source = read('tests/fixtures/spawn-input-harness.c').replace('/* PRODUCTION_INPUTS */',
    functions.map(s => productionFunction(file, s)).join('\n'));
  const cfile = path.join(temp, 'test.c'), binary = path.join(temp, 'test');
  fs.writeFileSync(cfile, source);
  execFileSync('xcrun', ['clang', '-std=gnu11', '-fblocks', '-Wall', '-Wextra', '-Werror',
    '-Wno-unused-parameter', '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
    '-I', path.join(root, 'BaseBin/libroothider/src'), cfile, '-o', binary], {stdio:'pipe'});
  execFileSync(binary, [temp], {stdio:'pipe', timeout:30000});
});
test('production signature transaction restores partial writes and repairs stale branded files', {
  skip: process.platform !== 'darwin' ? 'Requires macOS clang/Blocks/CommonCrypto and initialized ChOma headers.' : false,
}, t => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-signature-transaction-'));
  t.after(() => fs.rmSync(temp, {recursive:true, force:true}));
  const file = 'BaseBin/libroothider/src/recdhash.m';
  const signatures = ['Fat* fat_init_for_writing(', 'int calc_cdhash(', 'MachO* fat_find_slice_by_offset(',
    'static int recdhash_prepare_page_hash(', 'int ensure_randomized_cdhash_for_slice('];
  const source = read('tests/fixtures/recdhash-transaction-harness.c').replace('/* PRODUCTION_FUNCTIONS */',
    signatures.map(s => productionFunction(file, s)).join('\n'));
  const cfile = path.join(temp,'test.c'), binary = path.join(temp,'test'), dummy = path.join(temp,'dummy');
  fs.writeFileSync(cfile, source); fs.writeFileSync(dummy, 'stat/access only');
  execFileSync('xcrun', ['clang','-std=gnu11','-fblocks','-Wall','-Wextra','-Werror',
    '-Wno-deprecated-declarations','-I',path.join(root,'BaseBin/ChOma/src'),cfile,'-o',binary], {stdio:'pipe'});
  execFileSync(binary,[dummy],{stdio:'pipe',timeout:20000});
});
test('production fork handshake handles interrupted IO and peer failure without releasing an unpatched child', {
  skip: process.platform !== 'darwin' ? 'Requires macOS clang and Darwin pipe flags; syscalls are fault-injected.' : false,
}, t => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-fork-handshake-'));
  t.after(() => fs.rmSync(temp, {recursive:true, force:true}));
  const original = read('BaseBin/forkfix/src/main.c');
  const source = read('tests/fixtures/fork-handshake-harness.c').replace('/* PRODUCTION_FORK */',
    original.slice(original.indexOf('struct fork_pipes {'), original.indexOf('void apply_fork_hook(void)')));
  const cfile = path.join(temp,'test.c'), binary = path.join(temp,'test');
  fs.writeFileSync(cfile,source);
  execFileSync('xcrun',['clang','-std=gnu11','-Wall','-Wextra','-Werror',cfile,'-o',binary],{stdio:'pipe'});
  execFileSync(binary,[],{stdio:'pipe',timeout:20000});
});
test('production exec records reject stale events and release exited or failed registrations', {
  skip: process.platform !== 'darwin' ? 'Requires macOS Foundation and kevent declarations; kernel events are simulated.' : false,
}, t => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'rh-exec-events-'));
  t.after(() => fs.rmSync(temp, {recursive:true, force:true}));
  const file = 'BaseBin/libroothider/src/exec_patch.m';
  const functions = ['static int change_exec_patch_event(', 'static void handle_exec_patch_event(',
    'int spawnExecPatchAdd(', 'int spawnExecPatchDel('];
  const source = read('tests/fixtures/exec-event-harness.m').replace('/* PRODUCTION_EXEC */',
    functions.map(s=>productionFunction(file,s)).join('\n'));
  const mfile=path.join(temp,'test.m'), binary=path.join(temp,'test'); fs.writeFileSync(mfile,source);
  execFileSync('xcrun',['clang','-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror',mfile,'-framework','Foundation','-o',binary],{stdio:'pipe'});
  execFileSync(binary,[],{stdio:'pipe',timeout:20000});
});
test('production signature collection discards partial results and preserves borrowed descriptor ownership', {
  skip: process.platform !== 'darwin' ? 'Requires macOS clang/Blocks and initialized ChOma headers; parser faults are simulated.' : false,
}, t => {
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'rh-signature-collection-'));
  t.after(()=>fs.rmSync(temp,{recursive:true,force:true}));
  const file='BaseBin/libjailbreak/src/signatures.c';
  const signatures=['int macho_collect_adhoc_cdhash(', 'int fat_collect_untrusted_cdhashes(',
    'int file_collect_untrusted_cdhashes(', 'int file_collect_untrusted_cdhashes_by_path('];
  const source=read('tests/fixtures/signature-collection-harness.c').replace('/* PRODUCTION_COLLECTION */',
    signatures.map(s=>productionFunction(file,s)).join('\n'));
  const cfile=path.join(temp,'test.c'),binary=path.join(temp,'test'); fs.writeFileSync(cfile,source);
  execFileSync('xcrun',['clang','-std=gnu11','-fblocks','-Wall','-Wextra','-Werror',
    '-I',path.join(root,'BaseBin/ChOma/src'),cfile,'-o',binary],{stdio:'pipe'});
  execFileSync(binary,[],{stdio:'pipe',timeout:20000});
});
test('production XPC dispatch preserves fields after DATA and validates layouts before side effects', {
  skip: process.platform !== 'darwin' ? 'Requires macOS clang; XPC transport is simulated.' : false,
}, t => {
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'rh-xpc-dispatch-'));
  t.after(()=>fs.rmSync(temp,{recursive:true,force:true}));
  const header=read('BaseBin/libjailbreak/src/jbserver.h');
  const types=header.slice(header.indexOf('typedef enum {'),header.indexOf('extern struct jbserver_impl'));
  const source=read('tests/fixtures/xpc-dispatch-harness.c').replace('/* PRODUCTION_TYPES */',types)
    .replace('/* PRODUCTION_ARGUMENT_ARRAYS */', argumentArrays().map(({source}, i) =>
      `{ const jbserver_arg actual[] = ${source}; assert(actual[sizeof(actual)/sizeof(*actual)-1].name == NULL); }`).join('\n'))
    .replace('/* PRODUCTION_DISPATCH */',productionFunction('BaseBin/libjailbreak/src/jbserver.c','int jbserver_received_xpc_message('));
  const cfile=path.join(temp,'test.c'),binary=path.join(temp,'test'); fs.writeFileSync(cfile,source);
  execFileSync('xcrun',['clang','-std=gnu11','-Wall','-Wextra','-Werror',
    '-fsanitize=address,undefined','-fno-omit-frame-pointer',cfile,'-o',binary],{stdio:'pipe'});
  execFileSync(binary,[],{stdio:'pipe',timeout:20000});
});
