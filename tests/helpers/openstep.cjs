const assert = require('node:assert/strict');

// Keep source spans so project edits need not reformat unrelated Xcode objects.
function parseOpenStep(source) {
  let cursor = 0;
  function whitespace() {
    while (cursor < source.length) {
      if (/\s/.test(source[cursor])) cursor++;
      else if (source.startsWith('//', cursor)) {
        const end = source.indexOf('\n', cursor);
        cursor = end < 0 ? source.length : end + 1;
      } else if (source.startsWith('/*', cursor)) {
        const end = source.indexOf('*/', cursor + 2);
        assert.ok(end >= 0, 'Unterminated OpenStep comment');
        cursor = end + 2;
      } else break;
    }
  }
  function take(character) {
    whitespace();
    assert.equal(source[cursor++], character, `Expected ${character} at ${cursor - 1}`);
  }
  function atom() {
    whitespace();
    const start = cursor;
    if (source[cursor] === '"') {
      cursor++;
      let value = '';
      while (cursor < source.length && source[cursor] !== '"') {
        let char = source[cursor++];
        if (char === '\\') {
          char = source[cursor++];
          value += ({ n: '\n', r: '\r', t: '\t' })[char] ?? char;
        } else value += char;
      }
      take('"');
      return { start, end: cursor, value };
    }
    while (cursor < source.length && !/[\s{}()=;,"]/.test(source[cursor])) cursor++;
    assert.ok(cursor > start, `Expected OpenStep atom at ${cursor}`);
    return { start, end: cursor, value: source.slice(start, cursor) };
  }
  function node() {
    whitespace();
    const start = cursor;
    if (source[cursor] === '{') {
      cursor++;
      const value = {};
      const entries = new Map();
      whitespace();
      while (source[cursor] !== '}') {
        const key = atom();
        take('=');
        const child = node();
        take(';');
        assert.ok(!entries.has(key.value), `Duplicate OpenStep key ${key.value}`);
        value[key.value] = child.value;
        entries.set(key.value, { start: key.start, end: cursor, node: child });
        whitespace();
      }
      cursor++;
      return { start, end: cursor, value, entries };
    }
    if (source[cursor] === '(') {
      cursor++;
      const items = [];
      whitespace();
      while (source[cursor] !== ')') {
        const item = node();
        whitespace();
        if (source[cursor] === ',') cursor++;
        else assert.equal(source[cursor], ')', `Expected array separator at ${cursor}`);
        items.push({ ...item, end: cursor });
        whitespace();
      }
      cursor++;
      return { start, end: cursor, value: items.map((item) => item.value), items };
    }
    return atom();
  }
  const result = node();
  whitespace();
  assert.equal(cursor, source.length, 'Trailing OpenStep input');
  return result;
}

module.exports = { parseOpenStep };
