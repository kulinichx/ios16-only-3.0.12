# 3.0.13 对当前 iOS 16 分支的移植评估

评估日期：2026-11-26（北京时间）。

用户本轮要求判断移植价值。本轮仅核对源码、来源和历史补丁并记录建议，没有实施补丁、改测试期望、提交、推送或构建。

当前候选为 `cd5f9390862815b862bb14210010f73b423bc9f1`，版本字段为 `3.0.12 / 30`。该版本号不表示已经包含官方 RootHide 30 的全部代码。当前生产源码中的三项历史移植均已在上一轮对齐中撤回。

## 判断结果

**3.0.13 有适用于当前 iOS 16 分支的改动，但应逐项引入。建议第一批考虑 logd_helper 插件避让和 spawn 内存参数恢复；第二批独立评估快照写入。**

| 项目 | 来源性质 | 当前状态 | 对 iOS 16 的判断 | 建议 |
| --- | --- | --- | --- | --- |
| logd_helper 跳过 TweakLoader | 官方 RootHide 30 | 未包含 | 上游明确记录在 iOS 16 观察到循环等待，当前相同加载路径存在 | 优先考虑，改动范围最小 |
| spawn 内存限制保存/恢复 | Dopamine 3.0.13；RootHide 30 继承 | 未包含 | 当前代码修改调用者的属性结构且不恢复；复用时可能累计 MB 增量 | 优先考虑，只移植内存字段部分 |
| SpringBoard 快照保存 hook | Dopamine 3.0.13；RootHide 30 继承 | 当前仍是旧 fcntl hook | 有可复用的改进，但我们实际加载 roothidehooks，需适配路径与私有接口 | 第二批，独立构建及实机验收 |
| killall 参数缓冲区边界 | ZQBB 审查分支 | 未包含 | 当前有容量不一致，且存在真实调用点 | 有修复价值；作为额外候选单独决定 |
| 解包、签名、trustcache、配置缓存、fork/IPC | ZQBB 审查分支等 | 不能视为整体保留或整体通过 | 部分有用，但跨调用链，不能由版本号判断适配 | 不并入首批，分别立项 |
| SPTM、TXM、高版本 persona 修正 | 上游的其他系统路径 | 当前相应高版本路径已裁剪 | 不属于当前 iOS 16 的有效实现 | 不移植、不恢复相关系统支持 |
| 版本号、发布命名、官方构建流程 | 发行工程 | 当前自有实现 | 不带来 iOS 16 运行时修复 | 保持现有方案 |

## 参照与来源边界

| 参照 | 固定提交 |
| --- | --- |
| 本项目 ZQBB 底座 | `18049d5a81b294d3387b3af30c54558d04b8b5f5` |
| Dopamine 3.0.13 | `5b1d2c1c3bf54dd8e3641d29c60cd3a0c13cde88` |
| w2599 的 3.0.13 标签 | `6522285754fd9c4574e9afc352dc31fe548567fc` |
| 官方 RootHide 29 | `02d6e8f6b6eee471de0f4c791058c060a65df643` |
| 官方 RootHide 30 | `9617d75f476423fdfd33477299c8a1349eb6f375` |
| ZQBB 审查分支历史快照 | `d37a79f58a93fb1f26a7c445ef4c21221c8ac3de` |

本次重新打开三个官方发布页面和三项核心补丁页面，并读取本地固定 Git 对象。官方 RootHide 29 到 30 的完整净差异为 13 个文件；其中运行时代码变化是快照、spawn、logd_helper、SPTM 写入宽度和 TXM availability，其他是版本/构建/发行文件。没有把提交日志的全部历史重放当作新增功能。

w2599 的 3.0.13 标签与本项目 RootHide 底座并非可以整树互换：实际差异涉及删除 libroothider、roothidehooks 等本项目依赖的目录。标签、官方 RootHide 版本和 ZQBB 审查分支必须分别对待，也不能据源码分支推定某个发布 IPA 的精确构建来源。

## A. logd_helper：建议第一批

- 官方补丁：`473d52e44d14e3ccc7cf4e86d1095d26be2e6987`。
- 位置：`BaseBin/systemhook/src/main.c` 的 `should_enable_tweaks()`。
- 上游在 iOS 16 排除列表新增精确路径 `/usr/libexec/logd_helper`，注释描述 `logd -> logd_helper -> TweakLoader -> CFBundleGetMainBundle -> logd` 循环等待。
- 当前列表仅有 logd、notifyd、usermanagerd，未包含 logd_helper。当前初始化仍先调用 `roothide_init_with_executable()`，之后才决定是否加载 TweakLoader。

用途明确、适配较直接：仅对该进程跳过插件加载器，保留 RootHide 基础初始化，不杀进程、不关闭日志服务，也不扩展为模糊路径黑名单。直接影响是插件不能再通过这个加载入口注入 logd_helper。

建议实现边界为一项精确路径排除及其针对性测试；是否保留上游解释注释不影响行为。过去的本地提交是 `cc81d3d87912a6addb1a49044848c67726cd1987`，可作参考，但不恢复整份旧测试文件。

验收：静态检查初始化顺序；提取真实判断函数验证精确匹配、相似路径不匹配、安全模式和原有排除项；构建/包验证；实机检查日志服务及普通插件应用。上游已观察到问题不等于已经证明本用户的 watchdog 就由此导致。

## B. spawn 内存字段恢复：建议第一批，只取 iOS 16 部分

- 官方补丁：`f3cd2b82af8d5fa3baea193384ac61b50d2e44bb`。
- 位置：`BaseBin/systemhook/src/common/common.c` 的 `spawn_exec_hook_common()`。
- 当前实际路径：RootHide prehook -> `posix_spawn_hook_shared()` -> 公共函数 -> RootHide posthook -> 系统 spawn。
- 当前公共函数直接修改 `desc->attrp` 的 active/inactive memlimit。两条 orig 调用路径返回后均没有恢复这两个值。RootHide posthook 恢复的是临时 flags，不能替代内存字段恢复。

由源码推导：如果调用者复用属性结构，当前 MB 加法会把前一次写回的值当成下一次基础值，导致增量累积；一次 spawn 失败后也可能留下改过的值。这是条件性行为，不代表已经在用户设备上捕获到此故障。

发布说明以 iOS 17.6+ 的 Zebra 为典型表现，但该补丁的内存字段部分没有该版本前提。我们 iOS 16 的有效路径同样修改这些字段，因此有移植价值。这里是进程内存限制，与低电量开关和耗电记录不是同一项功能，不能宣称会直接省电。

建议仅保存本次实际改动前的 active/inactive 值，在 orig 返回后恢复；保留 ZQBB 现有 MB 加法、无限额 `-1`、默认值及饱和处理。不要引入上游的倍数策略、iOS 17.6+ persona UID/GID 或新的挂起协议。过去 `be6cb36ab93767d67fcb7857b33376832bdd50b8` 的这部分是约 12 行的局部适配，可供参考。

验收必须覆盖：orig 实际收到调整值、调用者返回后看到原值；成功/失败；同一结构复用；两条 orig 分支；无限额、零值、饱和、无注入、无属性场景。只验证最终值还原，不足以证明子进程拿到了正确限制。实机再验证正常应用启动及现有 MB 设置行为。

## C. 快照写入：建议第二批，有价值但需要适配

- 官方补丁：`26d95449d25d176a31ae7bc475fd85ee3403498c`。
- 官方位置：`BaseBin/rootlesshooks/SpringBoard.x`。
- 当前有效位置：`BaseBin/roothidehooks/src/springboard.x`，由 systemhook 实际加载的 `roothidehooks.dylib` 提供。

上游将宽泛的 fcntl hook 替换为 `XBApplicationSnapshotManifestImpl` 的 `_imageAccessQueue_saveData:forSnapshot:`，在目标快照的保存入口处理写入。当前仍保留旧 fcntl hook，因此并非“当前已经拥有，只需重新打开”。

潜在价值是缩小快照处理范围，改善越狱应用快照保存的兼容性。不能据此推定提高越狱成功率，或根治注销、watchdog、界面黑屏等所有现象。

该实现不能直接复制到我们树中：需要使用随机 `jbroot` 路径，保留 Apple-internal 标识例外、隐藏应用及打开应用逻辑，并保留 `rcScheduleServicesStartAfterLaunch()` 接线。旧 `be6cb36a` 适配还增加了 bundleIdentifier 空值及目标路径范围检查，这些属于本地适配，不能宣称整个实现与官方逐字一致。

验收：先测试路径分流和失败返回，再原生构建；最终必须在实际支持的 iOS 16 设备上检查该私有 selector 是否存在、是否进入新 hook、应用切换器快照是否正确保存/更新、系统应用是否维持原逻辑，以及锁屏解锁、注销、低电量/记录服务是否正常。现有 iOS 18.5 UIKit 布局模拟器不能验证这条 iOS 16 系统私有调用链。

因此建议独立补丁、独立候选，避免与前两项混在一个不可区分的实机测试包中。

## D. killall：有价值，但必须另列来源

- 参考补丁：ZQBB 审查分支 `04c18e40ef2a04f666a705d9c0361515f1afc318`；对应历史快照 `d37a79f5`。
- 位置：`BaseBin/libjailbreak/src/util.c`。
- 当前实现按进程列表 `length` 分配 buffer，却把 `maxArgumentSize` 作为 `KERN_PROCARGS2` 可写容量。两种容量没有相等保证，存在越界风险；路径终止符也未作有界验证。
- 当前保留了 launchdhook/jbctl 对 backboardd、systemwide 对 kbd 的真实调用点。

它是当前 iOS 16 可达的通用代码问题，修复价值明确，但不是 Dopamine 3.0.13 或官方 RootHide 29->30 新增的那几项。不能将其标为“官方 3.0.13 必带修复”。我们历史本地提交 `2e1bd1e3` 还增加了额外检查，不能不区分来源整段回灌。

建议用户单独决定是否加入。若批准，范围限定于容量分离和有界读取，保持完整路径匹配及调用者信号；使用替身 sysctl/kill 和边界测试验证，不在开发 PC 上执行真实 killall。此问题尚未被证明是实际设备故障原因。

## E. 其他审查分支改动：暂不批量移植

| 类别 | 本次判断 | 需要的独立验证 |
| --- | --- | --- |
| 归档解包及错误传播 | 安装/更新调用链有效，有价值但可能影响合法链接、路径别名和权限 | 用当前 bootstrap/basebin 的实际格式测试合法软硬链接、权限、失败清理及上层返回处理 |
| 签名、Mach-O 分类、trustcache | 当前存在源码问题，多个 API 和调用者受影响 | 分项核对 ABI、失败传播、跨页添加、真实包签名与信任加载 |
| 配置缓存、fork 握手、exec/RPC | 跨进程、线程和所有权协议，变更范围显著 | 独立审计全部相关端点与失败路径，并做实机压力/重启测试 |
| proc_vwritebuf 自调用 | 当前实现有问题，本树检索未见函数外直接调用；外部消费者不能仅靠检索排除 | 单独决定，不能把修复效果归因到没有证据的当前设备症状 |

这部分评估只给出类别与门槛，没有完成审查分支每一处改动的语义验证；不能把分支净差异 68 个文件说成 68 项已经批准或必须移植的修复。

## F. 不移植的范围

官方 SPTM frame level 从 16 位写入改成 8 位、TXM 中 iOS availability 文本调整，以及 spawn 的高版本 persona 修正，对当前已裁剪的 iOS 16 路径没有直接价值。不要为了这些补丁恢复 SPTM、TXM 或其他系统支持。

官方发行工作流、产物命名、版本数字、issue 模板也不作为运行时修复引入。保持当前 TIPA、包标识、玻璃主题、低电量与记录、授权、挂载管理和已有依赖固定方式。palera1n/palehide、TrollStoreLite 主动修复继续排除。

## 若用户决定实施，建议顺序

1. 第一批：logd_helper 精确排除、spawn 内存字段恢复；两个独立提交，针对性测试及完整构建后验收。
2. 第二批：RootHide 快照保存适配，独立候选及 iOS 16 实机验收。
3. 额外候选：用户单独选择 killall 或其他审查分支修复；不以“升级 3.0.13”作为整批授权。

批准的补丁应在基线清单中记录来源和允许偏差，只调整相关测试；不能删除整个 ZQBB 基线检查来让补丁通过。此时可以保持版本字段不变，用提交号与补丁清单识别候选；不能仅改版本号声称完整升级。

## 本轮验证与证据

本轮验证是固定 Git 差异、当前有效调用链、历史移植与当前状态对照。没有执行新补丁的回归测试、构建或实机验证，因为本轮没有实施补丁。

证据目录：`.audit-artifacts/upstream-3.0.13-assessment-20261126/`。

- `official-29-to-30.patch`：完整官方版本净差异。
- `zqbb-review.patch`：审查分支相对固定 ZQBB 底座的差异。
- `previous-backport.patch`、`previous-logd-backport.patch`、`previous-killall-backport.patch`：历史本地移植，作为来源对照而非待自动执行的补丁。
- `before-working.patch` / `after-working.patch` 和 `before-index.patch` / `after-index.patch`：证明本轮未改已有跟踪文件及暂存区。新评估报告与证据文件除外。

公开一手来源：

- Dopamine 3.0.13：https://github.com/opa334/Dopamine/releases/tag/3.0.13
- RootHide 3.0.13-30：https://github.com/roothide/Dopamine-roothide/releases/tag/30
- ZQBB 3.0.13：https://github.com/w2599/Dopamine/releases/tag/3.0.13
- spawn 补丁：https://github.com/opa334/Dopamine/commit/f3cd2b82af8d5fa3baea193384ac61b50d2e44bb
- 快照补丁：https://github.com/opa334/Dopamine/commit/26d95449d25d176a31ae7bc475fd85ee3403498c
- logd_helper 补丁：https://github.com/roothide/Dopamine-roothide/commit/473d52e44d14e3ccc7cf4e86d1095d26be2e6987

公开网页本轮未能读取 ZQBB 审查提交页面；该部分依据本地已经存在的固定 Git 对象与完整差异，没有据不可访问网页推断其内容。
