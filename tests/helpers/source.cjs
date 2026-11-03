const fs = require('node:fs');
const path = require('node:path');

function mask(source, strings = true) {
  return source.replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*|"(?:\\[\s\S]|[^"\\])*"|'(?:\\[\s\S]|[^'\\])*'/g,
    token => !strings && /^["']/.test(token) ? token : token.replace(/[^\r\n]/g, ' '));
}

function ownedSources(root) {
  const files = [];
  function visit(relative) {
    for (const entry of fs.readdirSync(path.join(root, relative), { withFileTypes: true })) {
      const file = `${relative}/${entry.name}`;
      if (entry.isSymbolicLink()) continue;
      if (entry.isDirectory()) {
        if (/\/(?:ChOma|XPF|opainject|_external|external|Headers|Frameworks|build|\.build|\.theos|generated)$/.test(file)) continue;
        visit(file);
      } else if (/\.(?:c|m|mm|h|x)$/.test(file)) files.push(file);
    }
  }
  visit('Application/Dopamine');
  visit('BaseBin');
  return files.sort();
}

module.exports = { mask, ownedSources };
