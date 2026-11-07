# 简体中文与多架构双格式自动构建设计

## 目标

在 `liuran001/oasis` 中完成两项能力：

1. 为现有 Oasis WebUI 和 Tool Maker 提供完整的简体中文语言包。
2. 使用 GitHub Actions 自动构建 x86_64、ARM64、32 位 ARM 和 MIPS little-endian 的 IPK 与 APK 软件包，并确保缺包或编译错误会使工作流失败。

目标设备为 Spreadtrum UMS9620，OpenWrt 目标平台是 `armsr/armv8`，设备固件为 OpenWrt 25.12.5。所有 APK 均使用该版本 SDK；IPK 使用 OpenWrt 24.10.8 SDK，仅供采用 opkg 的设备使用。

## 非目标

- 不修改 AI 模型返回内容或聊天逻辑。
- 不修复上游现有安装脚本。
- 不自动提升 Oasis 核心版本号。
- 不宣称已完成真实路由器上的安装和界面验收。
- 不构建完整 OpenWrt 固件。

## 方案选择

采用官方 `openwrt/gh-action-sdk` 和官方 SDK 容器，固定 Action 的提交版本。与自行维护 SDK 下载脚本相比，该方案代码更少、构建环境由 OpenWrt 官方维护；与完整源码构建相比，它更快速且足以满足软件包构建需求。

## 简体中文语言包

新增目录 `lang/luci-i18n-oasis-zh-cn/`，结构如下：

- `Makefile`：定义 `luci-i18n-oasis-zh-cn`，依赖 `luci-app-oasis`、`luci-i18n-base-zh-cn` 和 `LUCI_LANG_zh_Hans`。
- `po/zh_Hans/luci-app-oasis.po`：覆盖共享 POT 中的全部源文本。
- 构建输出：`/usr/lib/lua/luci/i18n/oasis.zh-cn.lmo`。

`zh_Hans` 是 LuCI 的源翻译目录语言代码，`zh-cn` 是软件包和 LMO 文件名使用的别名。安装语言包并选择 LuCI 的简体中文界面后生效。

翻译保留所有源占位符、HTML、转义字符、API 名称、技术标识和模型名称。聊天、设置、工具、Agent、回滚和 Tool Maker 均属于覆盖范围。

## 翻译检查

扩展现有 `dev_tools/check_i18n.cjs`，将日语和简体中文注册为两个受检语言目录，共享同一个由源模板生成的 POT。

检查包括：

- 源文本、POT 和两个 PO 目录一一对应；
- 不存在缺失、空值、fuzzy、未翻译英文或过期条目；
- 源文本和译文中的命名占位符完全一致；
- 两个 PO 文件均通过 GNU `msgfmt --check`；
- 六个 WebUI JavaScript 字典可由两种语言的译文正确渲染；
- 日语既有行为不回退。

保留现有测试接口的兼容性；新增语言通过参数或注册表注入，不复制两套审计逻辑。

## Actions 工作流

新增 `.github/workflows/build-packages.yml`，包含主机验证、矩阵构建和可选标签发布三个阶段。

### 触发条件

- 推送到 `main`；
- 针对 `main` 的 Pull Request；
- `workflow_dispatch` 手动运行；
- 推送 `v*` 标签。

普通构建只需要读取仓库内容；标签发布任务单独获得 contents 写权限。

### 主机验证

安装 Lua 和 GNU gettext，运行翻译审计、现有 JavaScript 测试和可移植 Lua 测试。主机验证失败后不启动 SDK 构建。

### SDK 矩阵

| 格式 | SDK | 目标平台 | ARCH | 产物名 |
| --- | --- | --- | --- | --- |
| IPK | 24.10.8 | `x86/64` | `x86_64-24.10.8` | `oasis-ipk-24.10.8-x86_64` |
| IPK | 24.10.8 | `armsr/armv8` | `aarch64_generic-24.10.8` | `oasis-ipk-24.10.8-arm64` |
| IPK | 24.10.8 | `armsr/armv7` | `arm_cortex-a15_neon-vfpv4-24.10.8` | `oasis-ipk-24.10.8-arm32` |
| IPK | 24.10.8 | `ramips/mt7621` | `mipsel_24kc-24.10.8` | `oasis-ipk-24.10.8-mipsle` |
| APK | 25.12.5 | `x86/64` | `x86_64-25.12.5` | `oasis-apk-25.12.5-x86_64` |
| APK | 25.12.5 | `armsr/armv8` | `aarch64_generic-25.12.5` | `oasis-apk-25.12.5-arm64` |
| APK | 25.12.5 | `armsr/armv7` | `arm_cortex-a15_neon-vfpv4-25.12.5` | `oasis-apk-25.12.5-arm32` |
| APK | 25.12.5 | `ramips/mt7621` | `mipsel_24kc-25.12.5` | `oasis-apk-25.12.5-mipsle` |

八个矩阵任务使用 `fail-fast: false`，并行构建以下软件包：

- `oasis`
- `luci-app-oasis`
- `oasis-mod-tool`
- `oasis-mod-agent`
- `oasis-mod-retired`
- `oasis-mod-spring`
- `oasis-tool-edge`
- `oasis-tool-maker`
- `oasis-mod-test`
- `luci-i18n-oasis-ja`
- `luci-i18n-oasis-zh-cn`

`PACKAGES` 显式限定为上述列表，避免把无关依赖作为本仓库产物发布。

### 产物检查

每个矩阵任务只收集本仓库 feed 中对应格式和架构的产物。上传前检查：

- 每个预期软件包均有对应文件；
- 文件非空且扩展名与矩阵格式一致；
- 中文包内包含 `oasis.zh-cn.lmo`；
- 构建失败或缺包时任务失败；
- 构建日志在失败时保留为 Artifact。

每个架构和格式组合使用独立 Artifact，防止文件覆盖或格式混装。

### 标签发布

只有推送 `v*` 标签时才运行发布任务。发布任务等待八个矩阵任务全部成功，下载八组 Artifact 并发布到对应 GitHub Release。普通推送、PR 和手动构建只生成 Actions Artifact，不修改 Release。

## 交付方式

实施位于 `feat/zh-hans-dual-package-ci` 分支，推送到 `liuran001/oasis` 后创建面向 `main` 的 Pull Request。PR 的 Actions 用于验证工作流、四种架构和两种格式构建；实机安装 ARM64 APK 并切换简体中文是后续人工验收步骤。

## 验收标准

1. 中文 PO 覆盖全部源文本，日语和中文审计均通过。
2. 现有可移植测试及新增翻译测试通过。
3. 四种架构的 IPK 与 APK 八个矩阵任务均成功。
4. 八组 Artifact 均包含全部十一个预期软件包，中文包包含正确的 LMO 文件。
5. 缺包、翻译缺失或占位符错误会使对应任务失败。
6. 标签发布不会发生在普通分支构建中。
