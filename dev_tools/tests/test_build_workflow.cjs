// Structural checks for the multi-architecture OpenWrt package workflow.
const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');

const workflow = fs.readFileSync(path.resolve(__dirname, '../../.github/workflows/build-packages.yml'), 'utf8');
const expectedSdks = [
    'x86_64-24.10.8',
    'aarch64_generic-24.10.8',
    'arm_cortex-a15_neon-vfpv4-24.10.8',
    'mipsel_24kc-24.10.8',
    'x86_64-25.12.5',
    'aarch64_generic-25.12.5',
    'arm_cortex-a15_neon-vfpv4-25.12.5',
    'mipsel_24kc-25.12.5',
];
const expectedPackages = [
    'oasis', 'luci-app-oasis', 'oasis-mod-tool', 'oasis-mod-agent',
    'oasis-mod-retired', 'oasis-mod-spring', 'oasis-tool-edge',
    'oasis-tool-maker', 'oasis-mod-test', 'luci-i18n-oasis-ja',
    'luci-i18n-oasis-zh-cn',
];

test('workflow builds all four architectures in both package formats', () => {
    const actualSdks = [...workflow.matchAll(/^[ \t]+-[ \t]+sdk:[ \t]*["']?([^\s"']+)/gm)].map(match => match[1]);
    assert.deepEqual(actualSdks.sort(), [...expectedSdks].sort());
    assert.match(workflow, /fail-fast:\s*false/);
    assert.equal((workflow.match(/format:\s*ipk/g) || []).length, 4);
    assert.equal((workflow.match(/format:\s*apk/g) || []).length, 4);
});

test('workflow downloads prebuilt official SDK archives and all expected packages', () => {
    assert.match(workflow, /dev_tools\/build_openwrt_packages\.sh/);
    assert.match(workflow, /actions\/cache@v4/);
    assert.match(workflow, /timeout-minutes:\s*30/);
    assert.doesNotMatch(workflow, /openwrt\/gh-action-sdk/);
    assert.doesNotMatch(workflow, /IGNORE_ERRORS:\s*(?:1|true)/);
    for (const name of expectedPackages) assert.match(workflow, new RegExp(`(^|\\s)${name}(?=\\s|$)`, 'm'));
});

test('workflow verifies and uploads independent artifacts', () => {
    assert.match(workflow, /dev_tools\/verify_packages\.sh/);
    assert.match(workflow, /name:\s*\$\{\{\s*matrix\.artifact\s*\}\}/);
    assert.match(workflow, /if-no-files-found:\s*error/);
    assert.match(workflow, /if:\s*failure\(\)/);
});

test('host tests run before SDK builds and releases are tag-only', () => {
    assert.match(workflow, /node dev_tools\/check_i18n\.cjs/);
    assert.match(workflow, /run_host_tests/);
    assert.match(workflow, /needs:\s*host-tests/);
    assert.match(workflow, /startsWith\(github\.ref, 'refs\/tags\/v'\)/);
    assert.match(workflow, /softprops\/action-gh-release@v2/);
});

test('browser tests install pinned Playwright and Chromium', () => {
    assert.match(workflow, /playwright@1\.65\.0/);
    assert.match(workflow, /playwright" install --with-deps chromium/);
    assert.match(workflow, /NODE_PATH:\s*\$\{\{\s*runner\.temp\s*\}\}\/oasis-tests\/node_modules/);
});

test('SDK build script invokes config through sh and only installs the repository feed', () => {
    const script = fs.readFileSync(path.resolve(__dirname, '../../dev_tools/build_openwrt_packages.sh'), 'utf8');
    assert.match(script, /sh \.\/scripts\/config --enable CONFIG_LUCI_LANG_ja/);
    assert.match(script, /sh \.\/scripts\/config --enable CONFIG_LUCI_LANG_zh_Hans/);
    assert.match(script, /\.\/scripts\/feeds install -p oasis -f "\$package"/);
    assert.doesNotMatch(script, /\.\/scripts\/feeds install -a/);
    assert.match(script, /make -j1 V=s package\/index/);
});
