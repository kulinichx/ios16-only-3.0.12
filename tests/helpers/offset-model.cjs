const assert = require('node:assert/strict');
const vm = require('node:vm');

// Model only the initializer's assignments/conditions, not kernel reads or writes.
function modelOffsets(source, input) {
  let body = source.split('void jbinfo_initialize_hardcoded_offsets(void)')[1]
    .split('void jbinfo_initialize_boot_constants(void)')[0];
  body = body.slice(body.indexOf('bool hasJitbox'));
  body = body.slice(0, body.lastIndexOf('}'));
  body = body.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, '')
    .replace(/\b(?:bool|uint32_t|uint64_t|int)\s+(\w+)/g, 'let $1')
    .replace(/\b(0x[\da-f]+|\d+)(?:ULL|LL|UL|U)\b/gi, '$1')
    .replace(/\bsizeof\(uint64_t\)/g, '8')
    .replace(/\b(ksymbol|kconstant)\((\w+)\)/g, '$1("$2")')
    .replace(/\bkoffsetof\((\w+),\s*(\w+)\)/g, 'koffsetof("$1", "$2")')
    .replace(/\(struct xnu_version\)\s*\{([^}]+)\}/g, (_, fields) =>
      `{${fields.replace(/\.(\w+)\s*=/g, '$1:')}}`);
  const state = { kernelConstant: { kernel_el: input.el, PT_INDEX_MAX: 0x800 },
    kernelStruct: { proc: { struct_size: input.procSize } } };
  for (const match of body.matchAll(/gSystemInfo\.([\w.]+)/g)) {
    const keys = match[1].split('.');
    let parent = state;
    for (const key of keys.slice(0, -1)) parent = parent[key] ||= {};
    parent[keys.at(-1)] ??= 0;
  }
  const context = {
    gSystemInfo: state, darwinVersion: input.darwin, xnuVersion: input.xnu,
    isArm64e: input.arm64e, cpuFamily: input.cpu,
    kconstant: (key) => state.kernelConstant[key] || 0,
    koffsetof: (type, field) => state.kernelStruct[type][field],
    ksymbol: () => 0,
    strcmp: (left, right) => left === right ? 0 : left > right ? 1 : -1,
    xnu_version_compare: (left, right) => {
      for (const field of ['major', 'minor', 'patch']) {
        if (left[field] !== right[field]) return left[field] > right[field] ? 1 : -1;
      }
      return 0;
    },
  };
  for (const match of body.matchAll(/\bCPUFAMILY_ARM_\w+/g)) context[match[0]] = match[0];
  vm.runInNewContext(body, context, { timeout: 1000 });
  const flat = {};
  function flatten(value, prefix = '') {
    for (const [key, child] of Object.entries(value)) {
      const name = prefix ? `${prefix}.${key}` : key;
      if (child && typeof child === 'object') flatten(child, name);
      else if (child !== 0 && child !== false) flat[name] = child;
    }
  }
  flatten(state);
  assert.ok(flat['kernelStruct.proc_ro.exists'], 'Expected the iOS 16 proc_ro layout');
  return Object.fromEntries(Object.entries(flat).sort(([a], [b]) => a.localeCompare(b, 'en')));
}

function offsetCases() {
  const versions = [
    ['22.0.0', 0, 0], ['22.1.0', 30, 0], ['22.1.0', 42, 0],
    ['22.2.0', 60, 0], ['22.3.0', 80, 0], ['22.4.0', 100, 0],
    ['22.5.0', 120, 0], ['22.6.0', 140, 0],
  ];
  const cpus = [
    ['CPUFAMILY_ARM_TWISTER', false], ['CPUFAMILY_ARM_HURRICANE', false],
    ['CPUFAMILY_ARM_MONSOON_MISTRAL', false], ['CPUFAMILY_ARM_VORTEX_TEMPEST', true],
    ['CPUFAMILY_ARM_LIGHTNING_THUNDER', true], ['CPUFAMILY_ARM_FIRESTORM_ICESTORM', true],
    ['CPUFAMILY_ARM_BLIZZARD_AVALANCHE', true], ['CPUFAMILY_ARM_EVEREST_SAWTOOTH', true],
  ];
  const cases = [];
  for (const [darwin, minor, patch] of versions) {
    for (const [cpu, arm64e] of cpus) {
      for (const el of [1, 2]) {
        for (const procSize of darwin === '22.4.0' ? [0x730, 0x780] : [0x730]) {
          cases.push({ darwin, cpu, arm64e, el, procSize,
            xnu: { major: 8792, minor, patch } });
        }
      }
    }
  }
  return cases;
}

module.exports = { modelOffsets, offsetCases };
