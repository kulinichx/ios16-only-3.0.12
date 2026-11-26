# ZQBB iOS 16 续审记录

本轮继续执行 `AGENTS.md` 的范围：只精简系统支持，保留既有产品功能；原版缺陷只记录，不自行修复。比较基线仍为 `18049d5a81b294d3387b3af30c54558d04b8b5f5`。

## 本轮实际修改

| 文件 | 处理及原因 |
| --- | --- |
| `Application/Dopamine/Exploits/Titan/exploit/ipc_port.c` | `proc_find_by_name` 完整恢复 ZQBB 原函数。裁剪时曾固定为 `0x381`，后续 `cddd0168` 又改为完整 XNU 版本比较；二者都不等于 ZQBB 原来的主版本比较。当前仍删除非 iOS 16 的 IOMachPort 分支。 |
| `Application/Dopamine/Exploits/Titan/exploit/titan.h` | 恢复原 `XNU_MAJOR_GREATER_THAN` 宏；保留 A17 枚举删除。 |
| `BaseBin/libjailbreak/src/primitives_IOSurface.m` | 恢复 `IOSurface_kalloc_16up` 的原名和外部可见性，同时恢复其静态辅助函数原名。iOS 15 分配实现继续删除。`16up` 是原接口名称，不能仅凭名称判定它包含其他系统支持。 |
| `Application/Dopamine/Jailbreak/DOExploit.m` | 撤销裁剪附带的 `@"unknown"` 默认值，恢复原声明；A8/A17 分支继续删除。 |

上述修改没有增加算法、错误处理或原版问题修复。Titan 恢复后的版本选择是：XNU 主版本 8792 选 `0x381`，大于 8792 选 `0x579`。这只说明恢复的源码行为，不证明该偏移对每台设备都正确；若需要保留 `cddd0168` 的行为，须作为单独修复决定。

## 本轮逐组核对内容

| 范围 | 核对结论和边界 |
| --- | --- |
| ClearSword / DarkSword / kfd / Titan | 核对版本元数据、A18/A17/A8 分支和剩余内存访问路径；保留原 iOS 16 分支及既有 beta 例外。dmaFail、momentarius 的版本元数据保留在 iOS 16 范围内。没有借审计调整 exploit 算法。 |
| DarkSword 公共依赖 | 抽出的 `IOSurface_helpers.h` 保留原调用选择器 6/33/16、输入尺寸 `0x20`、输出缓冲 `0xF60`、surface ID 偏移 `0x18` 及原错误处理。它供 DarkSword 使用，不能随旧 kfd IOSurface 后端一起删除；许可证继续打包。 |
| 内核接口 / 偏移 / 地址转换 | 核对 `proc + sizeof(proc)`、proc_ro、ucred_rw、pmap sw_asid、非 SPTM 转换和物理读写。`physrw.c` 的公共地址换算已在上一轮恢复。保留原 kcall API 和调用能力查询；原 arm64 kcall 初始化本身在 iOS 16 提前返回，移除其旧实现不新增 iOS 16 能力。 |
| App 启动链 | 核对 `DOJailbreaker`、`DOEnvironmentManager`、`DORuntimeConfiguration`：保留 iOS 16 双入口限制、原启动方法、现有自定义挂载和低电量/耗电记录接线；删除 SPTM/TXM 和旧系统专用分支。现有产品方法返回值和操作状态处理保持。 |
| launchd / boomerang / jailbreakd | 核对移除 hookd、旧 spinlock RPC、旧系统路径后的调用链；保留普通 check-in/fork/trust 协议及原消息编号。继续采用 iOS 16 的 `/Developer` 和 `SIGCONT` 行为。 |
| dyld / systemhook / libroothider | 核对保留 iOS 16 的 mach_msg2、dyld 注入和路径处理；删除旧 spinlock 及高版本 hookd/TXM 分支。`lv_bypass.c` 删除的是原 `#if 0` TXM 块及其辅助函数，活动信任流程保持。上一轮恢复的公共环境变量设置继续保留。 |
| 系统服务 hook | 核对 crashreporter、cfprefsd、runningboardd 和 SpringBoard。保留 iOS 16 实现；SpringBoard 仍只在原 hook 基础上接入我们已有服务。 |
| XPF | 检查准备脚本的版本分支及原代码注释：删除的 fallback 对应 iOS 14/15/17/18/27 路径；保留 iOS 16 metric 和注册路径。脚本验证输入后才修改，拒绝覆盖未知更改；不能把脚本可复现等同于真实 kernelcache patchfinding 验证。 |
| 构建 / 包内容 | 核对 iOS 16 最低目标、六个 exploit framework、两种 dyldhook 架构、固定子模块和打包白名单。`iOS16-17` 仅是保留的文件名；当前只按 iOS 16 编译和选择。 |

`info.h` 移除非 iOS 16 字段后，当前源码中的消费者按同一头文件重新构建，序列化按字段名进行，保留协议编号不变。仍需用同一候选源码完整构建和更新；本轮不声称兼容任意旧二进制组件。

这些是差异范围的源码核对，**不是对 395 个变化路径逐一完成了所有语义、UI 和实机验证**。图标、玻璃主题、授权、低电量、耗电记录和挂载的既有实现没有在本轮重写。上一轮报告中的原版问题仍然仅记录。

## 验证与恢复

- 原版 Titan 函数逐字规范化比较通过；`titan.h` 除 A17 枚举外与原版一致；`DOExploit.m` 除 A8/A17 分支外与原版一致。
- 基线清单从 38 增至 42 个完整文件，另保留 App 方法和 SpringBoard 的原版片段检查。没有用历史提交整体覆盖工作树。
- 续审修改前副本、逐文件散列和测试日志：`.audit-artifacts/zqbb-continuation-20261126/`。
- 完整本地测试 `node --test tests/*.test.cjs`：203 项，188 通过、0 失败、15 跳过，约 12.5 秒。跳过项包括当前平台缺失的 Apple 原生/UI 环境及可选外部程序检查，不能作为已验证结果。
- 根仓库及 XPF `git diff --check` 通过。暂存区前后 SHA256 相同，既有暂存内容未改动。
- Windows 环境不能执行本候选的 Xcode 编译、TIPA 实包检查或设备测试。此前其他源码版本的成功构建不替代这些步骤。

当前只完成本轮源码整理和可运行的本地检查。没有提交、推送、触发云构建、发布或安装新包；整体验收仍需当前候选源码的原生构建及设备验证。
