# 简体中文与多架构双格式构建实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为 Oasis 增加完整简体中文界面，并用 GitHub Actions 构建四种 ARM/x86/MIPS 架构的 IPK 与 APK。

**架构：** 复用现有 POT 和翻译审计，将日语专用注册表扩展为日语、简体中文双语。CI 先运行主机测试，再用官方 OpenWrt SDK Action 并行执行 4 架构 × 2 格式矩阵；独立校验脚本确保每个产物包含全部十一个软件包及中文 LMO。

**技术栈：** LuCI gettext PO/LMO、Node.js `node:test`、Shell、GNU gettext、Lua 5.1、GitHub Actions、OpenWrt SDK。

---

## 文件结构

- 创建 `lang/luci-i18n-oasis-zh-cn/Makefile`：中文语言包的 OpenWrt 构建定义。
- 创建 `lang/luci-i18n-oasis-zh-cn/po/zh_Hans/luci-app-oasis.po`：完整简体中文目录。
- 修改 `dev_tools/check_i18n.cjs`：双语注册、审计和 msgfmt 检查。
- 修改 `dev_tools/tests/test_i18n.cjs`：双语回归与渲染测试。
- 创建 `dev_tools/verify_packages.sh`：检查包数量、命名、格式、非空文件和中文 LMO。
- 创建 `dev_tools/tests/test_build_workflow.cjs`：检查八个矩阵目标、显式包列表和发布条件。
- 创建 `.github/workflows/build-packages.yml`：主机测试、SDK 矩阵、Artifact 和标签 Release。

### 任务 1：先让多语言测试失败

**文件：** 修改 `dev_tools/tests/test_i18n.cjs`。

- [ ] **步骤 1：注册中文目录并增加完整性断言**

在现有日语目录之外加载中文 PO，并添加测试：

```javascript
const catalogs = {
    Japanese: parsePo(fs.readFileSync(path.join(root, 'lang/luci-i18n-oasis-ja/po/ja/luci-app-oasis.po'), 'utf8')),
    'Simplified Chinese': parsePo(fs.readFileSync(path.join(root, 'lang/luci-i18n-oasis-zh-cn/po/zh_Hans/luci-app-oasis.po'), 'utf8')),
};

test('both language catalogs cover every source message', () => {
    for (const [language, catalog] of Object.entries(catalogs)) {
        assert.deepEqual(audit(source, catalog, pot, language), []);
        assert.equal(catalog.size, source.messages.size);
    }
});
```

- [ ] **步骤 2：运行测试并确认失败原因正确**

运行：`node dev_tools/tests/test_i18n.cjs`
预期：FAIL，提示找不到 `lang/luci-i18n-oasis-zh-cn/po/zh_Hans/luci-app-oasis.po`，而不是日语既有测试失败。

- [ ] **步骤 3：提交失败测试**

```bash
git add dev_tools/tests/test_i18n.cjs
git commit -m "test: require simplified Chinese translations"
```

### 任务 2：实现双语审计和完整中文语言包

**文件：**
- 修改 `dev_tools/check_i18n.cjs`
- 创建 `lang/luci-i18n-oasis-zh-cn/Makefile`
- 创建 `lang/luci-i18n-oasis-zh-cn/po/zh_Hans/luci-app-oasis.po`

- [ ] **步骤 1：把审计接口扩展为语言参数**

保留默认语言为 Japanese，避免破坏既有调用：

```javascript
const LANGUAGES = [
    { name: 'Japanese', catalog: 'lang/luci-i18n-oasis-ja/po/ja/luci-app-oasis.po' },
    { name: 'Simplified Chinese', catalog: 'lang/luci-i18n-oasis-zh-cn/po/zh_Hans/luci-app-oasis.po' },
];

function audit(scanResult, catalog, potSource, language = 'Japanese') {
    // 在原有错误前使用传入语言名；其他规则保持不变。
}
```

`main()` 遍历 `LANGUAGES`，逐个调用 `audit()` 和 `msgfmt --check`，任一语言失败即退出非零。

- [ ] **步骤 2：创建中文 Makefile**

```make
include $(TOPDIR)/rules.mk

PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_BUILD_DEPENDS:=po2lmo/host
PO2LMO:=$(STAGING_DIR_HOSTPKG)/bin/po2lmo

include $(INCLUDE_DIR)/package.mk

define Package/luci-i18n-oasis-zh-cn
  SECTION:=utakamo
  CATEGORY:=utakamo
  SUBMENU:=Translations
  TITLE:=Simplified Chinese translation for luci-app-oasis
  DEPENDS:=+luci-app-oasis +luci-i18n-base-zh-cn @LUCI_LANG_zh_Hans
  PKGARCH:=all
endef

define Build/Compile
endef

define Package/luci-i18n-oasis-zh-cn/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	$(PO2LMO) $(CURDIR)/po/zh_Hans/luci-app-oasis.po $(1)/usr/lib/lua/luci/i18n/oasis.zh-cn.lmo
endef

$(eval $(call BuildPackage,luci-i18n-oasis-zh-cn))
```

- [ ] **步骤 3：创建完整中文 PO**

使用现有 POT 的每个 `msgid`，保持源引用、换行、转义和占位符不变，为每条填写自然简体中文 `msgstr`。PO 头必须包含：

```po
"Language: zh_Hans\n"
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Content-Transfer-Encoding: 8bit\n"
"Plural-Forms: nplurals=1; plural=0;\n"
```

技术标识、API 名称和 `{name}` 占位符不翻译；不得留下空 `msgstr`、fuzzy 或多余条目。

- [ ] **步骤 4：运行双语测试**

运行：`node dev_tools/tests/test_i18n.cjs`
预期：PASS，日语和中文条目数都等于源文本数，六个 JS 字典均渲染成功。

- [ ] **步骤 5：提交语言包和审计实现**

```bash
git add dev_tools/check_i18n.cjs dev_tools/tests/test_i18n.cjs lang/luci-i18n-oasis-zh-cn
git commit -m "feat: add simplified Chinese WebUI translation"
```

### 任务 3：编写并测试产物校验器

**文件：** 创建 `dev_tools/verify_packages.sh`。

- [ ] **步骤 1：实现严格的命令行接口**

接口：`dev_tools/verify_packages.sh <directory> <ipk|apk> <package> [package...]`。

IPK 使用 `<name>_*.ipk`，APK 使用 `<name>-<数字开头版本>.apk` 匹配。每个预期包必须恰好有一个非空文件；目录内对应格式文件总数必须等于预期包数。发现缺失、重复、空文件或格式不符时打印错误并退出 1。

- [ ] **步骤 2：检查中文 LMO**

找到 `luci-i18n-oasis-zh-cn` 后执行：

```sh
case "$EXT" in
  ipk) ar p "$ZH_PACKAGE" data.tar.gz | tar -tzf - ;;
  apk) tar -tzf "$ZH_PACKAGE" ;;
esac
```

输出必须包含 `usr/lib/lua/luci/i18n/oasis.zh-cn.lmo`，否则退出 1。使用 `set -eu` 和管道错误检查，不能在解包失败时误判成功。

- [ ] **步骤 3：用临时假包验证缺包会失败**

创建临时目录并放入十个非空 IPK 假文件，运行十一个包的校验；预期退出 1 并报告缺少 `luci-i18n-oasis-zh-cn`。补入有效中文测试包后再验证通过；LMO 检查可用测试夹具模拟，真实解包由 SDK 构建再次验证。

- [ ] **步骤 4：提交校验器**

```bash
git add dev_tools/verify_packages.sh
git commit -m "ci: add strict OpenWrt package artifact checks"
```

### 任务 4：先添加工作流结构测试，再实现 Actions

**文件：**
- 创建 `dev_tools/tests/test_build_workflow.cjs`
- 创建 `.github/workflows/build-packages.yml`

- [ ] **步骤 1：编写失败的工作流测试**

使用 Node 读取 `.github/workflows/build-packages.yml`，断言八个 SDK 标签全部存在：

```javascript
const expected = [
  'x86_64-24.10.8', 'aarch64_generic-24.10.8',
  'arm_cortex-a15_neon-vfpv4-24.10.8', 'mipsel_24kc-24.10.8',
  'x86_64-25.12.5', 'aarch64_generic-25.12.5',
  'arm_cortex-a15_neon-vfpv4-25.12.5', 'mipsel_24kc-25.12.5',
];
for (const sdk of expected) assert.match(workflow, new RegExp(sdk));
```

同时断言中文包在 `PACKAGES` 中、使用 `fail-fast: false`、每个矩阵上传独立 Artifact、Release 仅在 `startsWith(github.ref, 'refs/tags/v')` 时运行。

- [ ] **步骤 2：运行工作流测试并确认失败**

运行：`node dev_tools/tests/test_build_workflow.cjs`
预期：FAIL，提示工作流文件不存在。

- [ ] **步骤 3：实现主机测试任务**

工作流在 Ubuntu 上安装 `lua5.1 gettext`，检出代码后运行：

```bash
node dev_tools/check_i18n.cjs
for test in dev_tools/tests/test_*.cjs; do node "$test"; done
OASIS_TEST_LUA=lua5.1 ./oasis-mod-test/run_host_tests
python3 -B -m unittest discover -s dev_tools/tests -p 'test_*.py'
```

- [ ] **步骤 4：实现八项 SDK 矩阵**

矩阵显式包含以下 SDK：

```text
x86_64-24.10.8
aarch64_generic-24.10.8
arm_cortex-a15_neon-vfpv4-24.10.8
mipsel_24kc-24.10.8
x86_64-25.12.5
aarch64_generic-25.12.5
arm_cortex-a15_neon-vfpv4-25.12.5
mipsel_24kc-25.12.5
```

调用固定提交的 `openwrt/gh-action-sdk`，设置 `FEEDNAME=oasis`、`BUILD_LOG=1`、显式十一包 `PACKAGES`。根据矩阵的架构、格式和版本调用 `dev_tools/verify_packages.sh`，再用 `actions/upload-artifact` 上传独立目录；失败时上传日志。

- [ ] **步骤 5：实现标签发布**

发布任务只在 `startsWith(github.ref, 'refs/tags/v')` 时运行，等待全部矩阵成功，下载八个 Artifact，使用 `softprops/action-gh-release` 发布到当前标签。普通任务权限为 `contents: read`，发布任务为 `contents: write`。

- [ ] **步骤 6：运行测试并提交 CI**

运行：`node dev_tools/tests/test_build_workflow.cjs`
预期：PASS。

```bash
git add .github/workflows/build-packages.yml dev_tools/tests/test_build_workflow.cjs
git commit -m "ci: build IPK and APK for four OpenWrt architectures"
```

### 任务 5：完整验证与交付

- [ ] **步骤 1：运行全部本地检查**

依次运行任务 4 的 Node、Lua、Python 命令以及 `git diff --check`。所有命令必须退出 0；若本机缺少 msgfmt 或 Lua，记录环境限制，并用 CI 主机任务完成对应验证，不能宣称本地已通过。

- [ ] **步骤 2：推送功能分支并创建 PR**

```bash
git push -u origin feat/zh-hans-dual-package-ci
```

在 `liuran001/oasis` 创建目标为 `main` 的 PR，说明中文包、八项矩阵、产物检查和实机验收限制。

- [ ] **步骤 3：检查 Actions 并修复失败**

读取 PR 检查运行，确认主机测试及八个 SDK 任务全部完成。若失败，按日志做最小修复、重跑相关测试并更新 PR；最终报告每项真实状态，不把未运行或失败描述为成功。

- [ ] **步骤 4：提交最终验证记录**

```bash
git status --short
git log --oneline origin/main..HEAD
```

工作树应为空，提交均位于功能分支。最终回复提供 PR 链接、构建矩阵结果及 APK 实机安装提示。
