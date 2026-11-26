# ZQBB iOS 16 范围收敛记录

本轮按照用户 2026-11-26 确认的原则整理：以 ZQBB 为基础，仅保留 iOS 16 支持及我们的既有功能；ZQBB 原有问题单独报告，不自行增加修复。

## 基线和结果

- 官方源码参照：`18049d5a81b294d3387b3af30c54558d04b8b5f5`。这是本项目已经选定的 ZQBB RootHide 3.0.12 源码，不能据此声称与发布 IPA 字节一致。
- 已有 iOS 16 裁剪参照：`7d6a3874d33225ba4c2a8a12ef916f80929f67d4`。保留其版本分支裁剪、iOS 16 偏移、六个 exploit 的版本限制、两种 dyldhook 架构和 XPF 准备脚本；保留后续必要的 pthread 声明及 Fugu14 孤立汇编删除。
- 本轮对齐 39 个生产文件（38 个完整文件和 App 中的一个方法），另撤出 `DOJailbreaker.m` 注释代码中遗留的签名错误检查。完整文件中有的恢复官方实现，有的恢复既有 iOS 16 专用版本；不是 39 个文件都回写成完整官方版本。
- 撤出本地额外编写的 fork 握手、spawn 错误/参数处理、签名/信任缓存事务、异常端口/回溯、黑名单缓存及配置、cfprefsd 请求上下文等补丁。
- 撤出此前回移的 logd_helper 排除、快照保存替代 hook、Jetsam 属性恢复和 killall 修复；保留 ZQBB 本来的 MB 增量设置及注入逻辑。
- 恢复 ZQBB 无版本门控的 `DYLD_SHARED_REGION=use` 设置（App、launchd、systemhook）及清理；恢复 `physrw.c` 中成对的物理地址偏移换算。二者均是恢复原实现，不是新写的修复。注释提到新系统，不能据此删除无版本条件的公共代码。
- App 的 `spawnJbctlAsRootWithArgs:` 恢复 ZQBB 原实现。玻璃界面的操作状态处理和已有方法签名保留。
- SpringBoard 的隐藏应用、启动请求和快照 hook 恢复 ZQBB 原实现，仅保留我们低电量/耗电记录服务的接线。服务实现和启动时序维持本轮开始时的状态。

本轮未改变玻璃主题、头像/壁纸、低电量计划、耗电记录、授权、挂载管理、中文本地化等已有产品实现。原有 `3.0.12 / 30` 版本字段保留；修订号 30 不代表继续带入官方 3.0.13 的所有修复。

## 范围检查和测试

- `AGENTS.md` 固化用户原则。
- `tests/fixtures/zqbb-ios16-baseline.json` 记录完整文件来源、规范化 SHA256，以及 ZQBB 原始 App 启动方法和 SpringBoard hook 的摘要。
- `tests/zqbb-baseline.test.cjs` 验证对齐结果，避免以后无意重新混入额外底层修复。测试使用已核对的摘要，不要求 CI 浅克隆下载历史提交。
- `tests/ios16-contracts.test.cjs` 继续检查 iOS 16 入口、exploit 元数据、Xcode 依赖、偏移模型、XPF 裁剪、公共头文件、打包范围等。
- 移除仅验证已撤出补丁的测试要求。原 `runtime-audit-regression.test.cjs` 保存到恢复目录，退出测试发现及 CI；其旧夹具作为历史文件保留，未编入产品。玻璃主题、低电量、耗电记录、授权等测试继续运行。
- 完整本地测试命令：`node --test tests/*.test.cjs`。最终 203 项：188 通过、0 失败、15 跳过，用时约 13.5 秒。跳过项包括当前平台无法运行的 Apple 原生/UI 测试及可选外部程序检查；不能计为已验证。
- `git diff --check` 和 XPF 子模块 `git diff --check` 通过。
- Windows 没有 Xcode / xcrun，未执行本轮 iOS 原生编译或实机验证。此前 `f1ef7925` 等构建带有本轮已撤出的补丁，其成功结果不能作为当前源码的验收。

## 原版问题：仅报告，等待用户决定

以下代码与固定 ZQBB 参照保持一致，属于原版问题或原版行为，不在本轮自行修复：

| 位置 | 源码观察和可能影响 |
| --- | --- |
| `BaseBin/libjailbreak/src/primitives.c` 的 `proc_vwritebuf` | 尾部再次调用自身并把 ttep 作为 proc 参数；该路径存在递归/错误寻址风险。是否触发取决于实际调用。 |
| `BaseBin/libjailbreak/src/util.c` 的 `killall` | 按进程列表 length 分配参数缓冲，却按 maxArgumentSize 传入 KERN_PROCARGS2；存在容量不一致问题。 |
| `BaseBin/libjailbreak/src/signatures.c` 的 `macho_is_mappable` | `isLibrary` 使用 `MH_EXECUTE` 判断；库与可执行文件分类的语义存在问题。 |
| `BaseBin/libjailbreak/src/trustcache.c` 的 `jb_trustcache_add_entries` | 多页循环始终从输入 `entries[i]` 起读；输入跨页时可能重复前段条目。 |
| `Application/Dopamine/Jailbreak/DOEnvironmentManager.m` 的 `spawnJbctlAsRootWithArgs:` | 旧版本比较、pipe/spawn 检查和子进程返回处理仍使用 ZQBB 原写法。 |
| `BaseBin/libroothider/src/launchd.m` 的 `fix__iosConnect` | 继续使用 ZQBB 的 ElleKit 私有符号查找；此前会话已记录相关崩溃线索，当前未带入替代查找补丁。 |
| exec 跟踪、旧进程退出和若干同步 RPC | 原有等待协议保留，不能据此宣称注销等待或 watchdog 故障已经解决。 |

此表不表示上述所有路径在实机必然触发，也不把它们认定为此前 SpringBoard watchdog 的根因。用户决定修复时，再逐项单独实现和验证。

## 恢复资料

目录：`.audit-artifacts/zqbb-baseline-alignment-20261126/`。

- `before.patch`：本轮开始时相对 HEAD 的完整工作树补丁。
- `before-index.patch`：本轮开始时已暂存的补丁；本轮未改动暂存区。
- `before/`、`DOJailbreaker.before.m`：被本轮覆盖的生产文件副本。
- `manifest.json`：恢复源和改前/改后散列。散列按实际保存文件计算；测试清单使用规范化换行/行末空白后的散列。
- 三份旧测试源码和 `build.yml`：本轮改测试及工作流前的副本。
- `full-tests.log`：初轮完整检查；`final-tests.log`：最终检查。

原暂存区前后补丁 SHA256 同为 `55330fe01d7e74f7ed2545f413ae239f83a21046498bc8d55891d624575e4c20`，确认本轮未改变原暂存状态。XPF 测试最初遇到沙箱用户与仓库所有者不同，最终仅为该次测试进程传入两个明确路径的 `safe.directory`，未修改全局 Git 配置。

本轮只在当前工作树整理源码，未创建发布提交、推送、触发云构建或替换设备安装包。

## 2026-11-26 续审

续审记录见 `ZQBB-IOS16-CONTINUATION-2026-11-26.md`。另恢复 Titan 的原 XNU 主版本判断、IOSurface 分配函数的原名/外部可见性，以及 DOExploit 的原变量声明；继续保留对应的非 iOS 16 分支删除。本次新增核对 4 个生产文件，基线清单累计覆盖 42 个完整文件和 App 的一个原版方法。上文 39 个文件及 38 个完整文件的数字是首轮记录。

续审保留所有既有产品功能。没有新增原版问题修复。当前仍未完成该源码的原生构建、TIPA 实包检查和实机验收。

续审后完整本地测试：203 项，188 通过、0 失败、15 跳过（约 12.5 秒）。跳过项仍未验证，不计为通过。根仓库和 XPF 的 `git diff --check` 均通过；暂存区前后摘要仍同为 `55330fe01d7e74f7ed2545f413ae239f83a21046498bc8d55891d624575e4c20`。日志位于 `.audit-artifacts/zqbb-continuation-20261126/full-tests.log`。
