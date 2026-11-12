const assert = require('node:assert/strict');
const fs = require('node:fs');

const applicationIdentifier = 'cn.zqbb.dopaRH';

function verifyAppEntitlements(entitlements, info) {
  assert.ok(entitlements && typeof entitlements === 'object');
  assert.equal(info.CFBundleIdentifier, applicationIdentifier,
    'packaged bundle identity must remain stable');
  assert.equal(entitlements['application-identifier'], applicationIdentifier,
    'signed application identity must match the existing bundle');
  assert.deepEqual(entitlements['keychain-access-groups'], [applicationIdentifier],
    'the app must have exactly its own stable keychain access group');
  assert.equal(entitlements['platform-application'], true,
    'preserve the existing platform application entitlement');
  assert.equal(entitlements['com.apple.private.security.no-sandbox'], true,
    'preserve the existing sandbox exemption');
  assert.equal(entitlements['com.apple.developer.team-identifier'], undefined,
    'do not invent a signing team for the TrollStore build');
}

if (require.main === module) {
  const [entitlementsPath, infoPath] = process.argv.slice(2);
  assert.ok(entitlementsPath && infoPath,
    'usage: node verify-app-entitlements.cjs entitlements.json Info.json');
  verifyAppEntitlements(
    JSON.parse(fs.readFileSync(entitlementsPath, 'utf8')),
    JSON.parse(fs.readFileSync(infoPath, 'utf8')),
  );
  console.log(`Verified signed app identity and scoped keychain group: ${applicationIdentifier}`);
}

module.exports = { verifyAppEntitlements };
