// Host-only package artifact verification tests. Requires sh, ar and tar.
const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '../..');
const verifier = path.join(root, 'dev_tools/verify_packages.sh');
const packages = [
    'oasis', 'luci-app-oasis', 'oasis-mod-tool', 'oasis-mod-agent',
    'oasis-mod-retired', 'oasis-mod-spring', 'oasis-tool-edge',
    'oasis-tool-maker', 'oasis-mod-test', 'luci-i18n-oasis-ja',
    'luci-i18n-oasis-zh-cn',
];

function run(command, args, options = {}) {
    const result = spawnSync(command, args, { encoding: 'utf8', ...options });
    assert.equal(result.status, 0, result.stderr || result.error?.message);
}

function packageName(name, ext, version = '1.0.0-r1') {
    return ext === 'ipk' ? `${name}_${version}_all.ipk` : `${name}-${version}.apk`;
}

function createChinesePackage(directory, ext, withLmo = true, ipkContainer = 'ar') {
    const staging = fs.mkdtempSync(path.join(os.tmpdir(), 'oasis-package-staging-'));
    const data = path.join(staging, 'data');
    const lmoDirectory = path.join(data, 'usr/lib/lua/luci/i18n');
    fs.mkdirSync(lmoDirectory, { recursive: true });
    if (withLmo) fs.writeFileSync(path.join(lmoDirectory, 'oasis.zh-cn.lmo'), 'fixture-lmo');
    run('tar', ['-czf', path.join(staging, 'data.tar.gz'), '-C', data, '.']);
    const destination = path.join(directory, packageName('luci-i18n-oasis-zh-cn', ext));
    if (ext === 'apk') {
        fs.writeFileSync(path.join(data, 'PKGINFO'), 'pkgname = luci-i18n-oasis-zh-cn\n');
        if (ipkContainer === 'raw') {
            run('tar', ['-cf', destination, '-C', data, '.']);
        } else if (ipkContainer === 'zstd') {
            run('tar', ['--zstd', '-cf', destination, '-C', data, '.']);
        } else {
            run('tar', ['-czf', destination, '-C', data, '.']);
        }
    } else {
        fs.writeFileSync(path.join(staging, 'debian-binary'), '2.0\n');
        const control = path.join(staging, 'control');
        fs.mkdirSync(control);
        fs.writeFileSync(path.join(control, 'control'), 'Package: luci-i18n-oasis-zh-cn\n');
        run('tar', ['-czf', path.join(staging, 'control.tar.gz'), '-C', control, '.']);
        if (ipkContainer === 'tar') {
            run('tar', ['-czf', destination, '-C', staging, './debian-binary', './data.tar.gz', './control.tar.gz']);
        } else {
            run('ar', ['r', destination, path.join(staging, 'debian-binary'), path.join(staging, 'control.tar.gz'), path.join(staging, 'data.tar.gz')]);
        }
    }
    fs.rmSync(staging, { recursive: true, force: true });
}

function fixture(t, ext, options = {}) {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'oasis-packages-'));
    t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
    for (const name of packages) {
        if (name === 'luci-i18n-oasis-zh-cn') {
            if (!options.missingChinese) createChinesePackage(directory, ext, options.withLmo !== false, options.container || 'ar');
        } else {
            fs.writeFileSync(path.join(directory, packageName(name, ext)), 'fixture');
        }
    }
    return directory;
}

function verify(directory, ext, environment = {}) {
    return spawnSync('sh', [verifier, directory, ext, ...packages], {
        encoding: 'utf8',
        env: { ...process.env, ...environment },
    });
}

function createApkTool(t) {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'oasis-apk-tool-'));
    t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
    const tool = path.join(directory, 'apk');
    const argumentsFile = path.join(directory, 'arguments');
    fs.writeFileSync(tool, `#!/bin/sh
set -eu
printf '%s\\n' "$@" > "$OASIS_TEST_APK_ARGS"
[ "$1" = "--allow-untrusted" ]
[ "$2" = "extract" ]
[ "$3" = "--destination" ]
[ -d "$4" ]
[ -f "$5" ]
mkdir -p "$4/usr/lib/lua/luci/i18n"
printf 'fixture-lmo' > "$4/usr/lib/lua/luci/i18n/oasis.zh-cn.lmo"
`);
    fs.chmodSync(tool, 0o755);
    return { tool, argumentsFile };
}

for (const ext of ['ipk', 'apk']) {
    test(`accepts a complete ${ext} set and validates the Chinese LMO`, t => {
        const result = verify(fixture(t, ext), ext);
        assert.equal(result.status, 0, result.stderr);
        assert.match(result.stdout, /Verified 11 ipk packages|Verified 11 apk packages/);
    });

    test(`rejects a ${ext} Chinese package without its LMO`, t => {
        const result = verify(fixture(t, ext, { withLmo: false }), ext);
        assert.notEqual(result.status, 0);
        assert.match(result.stderr, /oasis\.zh-cn\.lmo/);
    });
}

test('accepts an OpenWrt tar-gzip IPK package', t => {
    const result = verify(fixture(t, 'ipk', { container: 'tar' }), 'ipk');
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Verified 11 ipk packages/);
});

test('accepts a raw tar APK package', t => {
    const result = verify(fixture(t, 'apk', { container: 'raw' }), 'apk');
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Verified 11 apk packages/);
});

test('accepts a zstd-compressed APK package', t => {
    const result = verify(fixture(t, 'apk', { container: 'zstd' }), 'apk');
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Verified 11 apk packages/);
});

test('extracts an unsigned APK v3 package with the SDK tool when tar cannot read it', t => {
    const directory = fixture(t, 'apk');
    const packageFile = path.join(directory, packageName('luci-i18n-oasis-zh-cn', 'apk'));
    fs.writeFileSync(packageFile, 'opaque APK v3 fixture');
    const { tool, argumentsFile } = createApkTool(t);
    const result = verify(directory, 'apk', {
        OASIS_APK_TOOL: tool,
        OASIS_TEST_APK_ARGS: argumentsFile,
    });
    assert.equal(result.status, 0, result.stderr);
    const args = fs.readFileSync(argumentsFile, 'utf8').trim().split('\n');
    assert.deepEqual(args.slice(0, 3), ['--allow-untrusted', 'extract', '--destination']);
    assert.equal(args[4], packageFile);
    assert.match(result.stdout, /Verified 11 apk packages/);
});

test('rejects an unreadable APK when the SDK tool is not provided', t => {
    const directory = fixture(t, 'apk');
    fs.writeFileSync(path.join(directory, packageName('luci-i18n-oasis-zh-cn', 'apk')), 'opaque APK v3 fixture');
    const result = verify(directory, 'apk', { OASIS_APK_TOOL: '' });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /OASIS_APK_TOOL/);
});

test('rejects a missing expected package', t => {
    const result = verify(fixture(t, 'ipk', { missingChinese: true }), 'ipk');
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /missing luci-i18n-oasis-zh-cn/);
});

test('rejects duplicate package versions and unexpected package counts', t => {
    const directory = fixture(t, 'ipk');
    fs.writeFileSync(path.join(directory, packageName('oasis', 'ipk', '9.9.9-r9')), 'duplicate');
    const result = verify(directory, 'ipk');
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /duplicate oasis|expected 11 ipk packages/);
});
