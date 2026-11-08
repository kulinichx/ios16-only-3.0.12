# RootHide 3.0.13-30 与 zqbb 更新对照

核对日期：2026-11-08，Asia/Shanghai。

状态：对照后按用户要求继续，仅实现官方 `logd_helper` 插件加载
避让及针对性回归，其余条目仍为候选。没有修改应用身份、版本、
玻璃主题、MB 算法或构建流程。既有未提交的首页草稿、测试、
记录及 XPF 裁剪状态均予保留，本轮没有修改 RC9。
原生构建与真机结果必须独立记录，不能由源码测试推断。

## 一、固定参照与来源

本轮更新前的精简版已提交基线：

- 仓库：`kulinichx/ios16-only-3.0.12`。
- 分支：`ios16-roothide-3.0.12`。
- HEAD：`be6cb36ab93767d67fcb7857b33376832bdd50b8`。
- 用户此前报告 `roothide-Dopamine-3.0.12-be6cb36.tipa`
  安装、越狱及越狱后使用正常。该反馈不等于本轮新候选已验收。

官方对照：

| 参照 | 固定提交 |
| --- | --- |
| `roothide/Dopamine-roothide` tag `29` | `02d6e8f6b6eee471de0f4c791058c060a65df643` |
| 同仓库 tag `30`，发布名 `3.0.13-30` | `9617d75f476423fdfd33477299c8a1349eb6f375` |

官方发布于 **2026-11-06 10:18:04 北京时间**。发布说明只有
“bug fixes and stability enhancements”，本报告的具体结论来自
固定 Git 对象差异，不是从这句说明推断。

zqbb 对照：

| 公开分支 | 本次读取的提交 |
| --- | --- |
| `w2599/Dopamine` 的 `3.x_roothide` | `18049d5a81b294d3387b3af30c54558d04b8b5f5`，仍是旧基线 |
| `3.x_roothide_AI_review_fix` | `d37a79f58a93fb1f26a7c445ef4c21221c8ac3de` |

zqbb 沿用已有的 `3.0.13` release 页面，于 11 月 6 日更新 RootHide
附件，现有文件名为：
`Dopamine_roothide_zqbb_3.0.13-30_20261106_103030.ipa`。
附件大小为 36,484,550 字节；未下载或解包该附件。
页面最初发布日期仍是 11 月 4 日，不能将它误认为附件没有更新。

Git merge-base 验证：官方 tag `30` 是该审查修复分支的祖先。
因此目前有可核对的、包含官方 30 增量的公开 RootHide 源码。
但分支包含相应代码，不等于已证明发布二进制由该精确提交构建；
也不能从分支名称推断其全部改动已经过本项目验证。

来源：

- https://github.com/roothide/Dopamine-roothide/releases/tag/30
- https://api.github.com/repos/roothide/Dopamine-roothide/releases/latest
- https://github.com/w2599/Dopamine/releases/tag/3.0.13
- https://api.github.com/repos/w2599/Dopamine/releases/latest
- https://api.github.com/repos/w2599/Dopamine/branches

本地只拉取对象，未 checkout 或 merge：

```text
refs/upstream-audit/20261108/official-29
refs/upstream-audit/20261108/official-30
refs/upstream-audit/20261108/zqbb-roothide
refs/upstream-audit/20261108/zqbb-review
```

后续分支可能变动，应按上述提交重现本次结论。

## 二、官方 29 到 30：完整净差异分类

固定两端的净差异共 13 个文件。提交日志中的旧功能条目可能来自
历史重放，不能把每个日志标题都算成相对于 29 的新增内容。

### A. 明确适用于 iOS 16、本轮实现：logd_helper 插件加载避让

来源提交：
`473d52e44d14e3ccc7cf4e86d1095d26be2e6987`。

文件：`BaseBin/systemhook/src/main.c`。

官方在 `should_enable_tweaks()` 的 `iOS16TweaksDisabledPaths` 中增加：

```c
"/usr/libexec/logd_helper",
```

上游注释说明了在 iOS 16 观察到的循环等待链：

```text
logd -> logd_helper -> TweakLoader -> CFBundleGetMainBundle -> logd
```

对照时本项目只排除了 `logd`、`notifyd`、`usermanagerd`，没有
`logd_helper`。本轮仅在原有列表新增这个精确路径，其他三个排除项不变。

边界：

- 只让该系统进程跳过插件加载器，不是杀掉或禁用日志服务。
- 不是把整个进程加入普通 RootHide 黑名单，也不应取消基础钩子。
- 当前控制流在 `roothide_init_with_executable()` 之后才根据
  `should_enable_tweaks()` 决定是否 dlopen TweakLoader。
- 不能承诺它解决用户未报告的所有卡顿、提高越狱成功率或缩短启动时间。

新增源码回归检查实际列表、精确匹配和基础初始化先于插件加载。
另增加提取实际 `should_enable_tweaks()` 函数的 C harness，
验证四个系统排除项、原有 xpcproxy 后缀、普通应用、相似路径、
两种安全模式环境变量、禁用插件变量、Dopamine 自身与安全模式文件。
harness 的平台依赖为 stub，不等于设备执行或真实 dlopen。
Windows 跳过 C 编译，Linux/macOS 的现有 CI 会运行该测试。

### B. iOS 16 相关、但已处理：spawn/Jetsam 参数恢复

官方 `BaseBin/systemhook/src/common/common.c` 的增量包含：

- 内存限制备份与恢复。
- 高版本 persona、UID/GID 和临时挂起标志恢复。

本项目在 `be6cb36a` 已回移适用的内存限制恢复，并保留 zqbb MB
加法策略。不得将这次官方 diff 再整段覆盖过来，导致恢复为倍数算法、
重复实现或恢复已裁剪的高版本 persona 子系统。

当前测试已有参数复用、恢复顺序和 MB 策略保护。
此次没有重新实现或改变这项算法。

### C. 已有本项目适配：应用快照写入

官方变动路径为 `BaseBin/rootlesshooks/SpringBoard.x`。
本项目实际加载 `roothidehooks.dylib`，此前已经把对应处理适配到
`BaseBin/roothidehooks/src/springboard.x`，保留随机根目录和
Apple-internal 标识例外。

仅复制官方 rootlesshooks 文件不能代替验证实际加载的 RootHide 路径。
当前不需要重复移植；快照专项运行时覆盖仍不能由一般越狱成功反馈推断。

### D. 当前 iOS 16 精简范围不适用

- `BaseBin/libjailbreak/src/util.c` 中 SPTM frame level 写入从
  16 位改为 8 位：该 SPTM 分支已不在本项目的 iOS 16 路径中，
  不为获得这项修复而恢复非目标系统代码。
- `BaseBin/libjailbreak/src/txm.c` 的 availability 条件文字由
  `iOS 26` 改为 `iOS 19.0`：上游该文件确有此字样，但不是
  Settings 适配。本项目已移除该 TXM 文件，不合入。

### E. 发行与打包，不是设备稳定性修复

- `.version`、`.version-roothide`、Xcode marketing version。
- `Application/Makefile` 与官方 workflow 的产物命名调整。
- `Application/.gitignore` 和 issue templates。

本项目已有独立 TIPA-only 打包和包身份校验，不照搬官方 IPA/TIPA
双产物，不仅通过改版本号宣称完成整体升级。
29 到 30 的净差异没有新增 bootstrap/Sileo 资源替换。

## 三、zqbb 审查分支：另行评估，不能与官方修复混为一谈

相对 zqbb 旧基线，该分支净差异为 68 个文件，其中包括官方增量。
这不是“68 项 iOS 16 必须修复”，本轮也没有完成该分支全量安全审计。

已对照、具有后续评估价值的类别：

| 类别 | 当前证据与范围 | 建议 |
| --- | --- | --- |
| `killall` 路径缓冲区 | 本地仍用进程列表 `length` 分配缓冲区，却以 `maxArgumentSize` 作为读取容量；实际有 backboardd/kbd 调用 | 第二批小补丁候选，补大小、终止符、分配失败测试 |
| 归档解包边界和错误传播 | bootstrap、jbctl 与更新流程实际调用 `libarchive_unarchive`；审查分支增加路径/链接限制及清理 | 有价值但影响真实 payload 解包，需用 RootHide 包内合法链接和权限回归，不能整文件照搬 |
| 签名与 trustcache 错误传播 | 涉及 cdhash 收集、目录遍历和原有调用者的错误处理 | 作为完整调用链单独审查，不能只改单个返回类型或假设真机已修复 |
| 配置快照、fork 握手和 IPC | 跨多个动态库、进程、缓存及接口 | 高耦合专项，暂不与一行死锁修复捆绑 |
| `proc_vwritebuf` 错误自调用 | 当前函数末尾确为 `proc_vwritebuf(ttep, ...)`，审查分支改为 `vwritebuf(ttep, ...)` | 明确函数实现差异，但当前保留代码中未找到函数外直接调用；不把它宣称为本机故障根因 |

审查分支同时还含既有 zqbb 功能、高版本兼容和不同结构的代码。
整分支合并会带回本项目不需要的 TrollStoreLite/TXM 等内容。
保留 iOS 16 精简范围、玻璃主题、MB 加法、RootHide 身份和 TIPA-only
流程，不以该分支覆盖当前 BaseBin。

以上条目是源码候选与边界分析，不代表都在 11 月 6 日首次提出，
也不代表已运行其 `worker` 测试、原生构建或真机验证。

## 四、本轮检查与建议执行顺序

本轮执行现有本地回归：

```text
node --test --test-reporter=spec tests/ios16-contracts.test.cjs tests/glass-ui-contracts.test.cjs
```

对照阶段结果：77 项，76 通过，0 失败，1 项跳过。
实现后新增 2 项测试；2026-11-08 在 Windows 工作树实际运行结果：
79 项，77 通过，0 失败，2 项跳过。跳过的是新增插件加载策略和
原有 spawn/Jetsam 的 C 编译测试，需由 Linux/macOS CI 独立执行，
不能将本地跳过记为 C 测试已通过。`git diff --check` 通过。
已将实际暂存内容导出到独立临时副本，并按索引固定提交重新
检出四个子模块，再执行 XPF 裁剪和上述测试：同样为 79 项，
77 通过、0 失败、2 跳过。导出副本的首页控制器及玻璃测试
对象哈希均与更新前 HEAD 一致，确认未混入未提交的首页草稿。
本轮只暂存运行时代码、针对性测试及本报告三个文件；
CI 原生编译和包校验结果仍需在实际运行后核实。

本记录不宣称已取得新增安装包或真机通过结果。

建议顺序：

1. 本轮只回移官方 `logd_helper` 避让；完成针对性回归后独立构建。
2. 第二批核对 `killall` 缓冲区与归档错误处理，分补丁测试。
3. 配置缓存、fork/IPC、签名及 trustcache 作为独立专项，不整批追版本。
4. RC9 若需要对应维护，应在其可写工作区重新检查最新实现，
   不以 11 月 4 日的交接状态假设它仍缺少同样修复。

没有来源或调用链证据的条目不合入；源码测试、原生编译、
包身份检查与用户真机反馈分别记录。
