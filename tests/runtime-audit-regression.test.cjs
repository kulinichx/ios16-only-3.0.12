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
    .replace('/* PRODUCTION_DISPATCH */',productionFunction('BaseBin/libjailbreak/src/jbserver.c','int jbserver_received_xpc_message('));
  const cfile=path.join(temp,'test.c'),binary=path.join(temp,'test'); fs.writeFileSync(cfile,source);
  execFileSync('xcrun',['clang','-std=gnu11','-Wall','-Wextra','-Werror',cfile,'-o',binary],{stdio:'pipe'});
  execFileSync(binary,[],{stdio:'pipe',timeout:20000});
});
