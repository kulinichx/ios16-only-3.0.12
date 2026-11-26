# 已批准的 iOS 16 官方补丁：第一批

用户在 2026-11-26 的评估后要求继续，本批落实评估优先推荐的两项。快照、killall 和其他审查分支补丁未进入本批。

## 改动及来源

1. `BaseBin/systemhook/src/main.c`：按官方 RootHide 补丁 `473d52e44d14e3ccc7cf4e86d1095d26be2e6987`，只在原有列表加入 `/usr/libexec/logd_helper`。保留基础初始化和精确匹配，不改普通应用或系统日志服务的启动方式。
2. `BaseBin/systemhook/src/common/common.c`：按 Dopamine 3.0.13 补丁 `f3cd2b82af8d5fa3baea193384ac61b50d2e44bb` 的内存字段部分，恢复历史 `be6cb36a` 的局部适配。保存本次修改前的 active/inactive 限制，在两条 orig 路径返回后还原；保留 MB 加法、无限额及饱和处理，不引入高版本 persona/UID/GID 改动。

第一项独立提交为 `6f31c65`。第二项与其测试独立提交，具体提交号及构建结果以本文后续交付记录为准。

版本仍为 3.0.12 / RootHide 30。玻璃主题、低电量计划、耗电记录、授权和挂载管理均未修改。

## 基线约束

`tests/fixtures/zqbb-ios16-baseline.json` 保留 42 个文件原有摘要，新增 `approvedBackports`，逐文件记录原始摘要、补丁来源、授权范围及新摘要。测试不放弃基线检查，其他文件仍要求原摘要。这两项现在属于明确批准的例外，不能再将其误判为应撤回的未授权修复。

## 验证设计与本地结果

- `tests/upstream-ios16-backports.test.cjs` 验证 logd_helper 精确匹配、已有排除项和基础初始化先于插件加载。
- 在 Linux/macOS 提取真实 `should_enable_tweaks()` 编译运行，覆盖普通应用、相似路径、安全模式及禁用插件入口；依赖使用替身，不加载真实插件。
- macOS 编译真实完整 `spawn_exec_hook_common()`，配合真实 envbuf 与字符串枚举实现；仅外部系统条件和 orig 使用替身。启用 AddressSanitizer、UndefinedBehaviorSanitizer。
- spawn 用例计划执行 8,640 次调用，检查 orig 收到的临时内存限制、成功/失败返回值、属性结构完整字节还原、重复复用、两种环境路径、空属性、无注入、DriverKit、缺失 hook、无限额、零值、非有限配置、饱和及未相关环境值。此测试不是设备真实 spawn 或 Jetsam 测试。
- 两个 CI 入口均明确包含新增测试文件，避免只在 Windows 看见静态测试通过。
- Windows 完整测试：207 项，190 通过、0 失败、17 跳过。其中新增两个原生用例留待云端；不能把计划覆盖当成已经执行通过。
- `git diff --check` 通过；本批生产改动仅上述两个文件。

本地证据：`.audit-artifacts/upstream-ios16-backports-20261126/`。已有 `HEALTH-AUDIT-2026-11-12.md` 暂存及 XPF 准备状态保留。

## 交付状态

本节初始状态：源码与本地验证完成，等待当前候选的云端原生测试、构建和 TIPA 校验。获得结果后追加具体提交、运行及产物信息。

最终仍需 iOS 16 实机验收普通应用启动、日志服务、插件和 MB 设置行为。不能据此宣称 watchdog 已根治或整体升级到官方 3.0.13。
