# 注销后进入桌面触发看门狗：源码对比

检查日期：2026-11-25（Asia/Shanghai）。

## 判断

补充收到 launchd 详细报告后，已定位另一条明确的崩溃路径：
`posix_spawn → fix__iosConnect → ElleKit MSFindSymbol → findPrivateSymbol → sharedCachePath`
随后经过 Objective-C runtime，在 libsystem_platform 中触发 `EXC_BREAKPOINT`。
它与下述 SpringBoard 超时需分别解释。当前没有发现这条调用链缺失了
iOS 16 必需文件；设备实际加载的多个二进制 UUID 与本地留存构建也不一致，
不能直接认定用户正在运行当前源码对应的运行时。具体比对见本节后续补充。

新收到的 `userspace-panic-1795533643.705187-1.ips` 已确认一次
SpringBoard 连续 180 秒未成功 check-in 的看门狗事件。当前优先排查的源码差异
仍是我们新增的 SpringBoard 低电量调度及耗电记录启动路径。
它们在每次 SpringBoard 重启时进入主队列，首次获取根目录可能同步等待
launchd，之后还在同一线程读写状态、注册持久计时器，并在需要追赶计划时调用
系统电量模式接口。此路径与“注销后刚回桌面”吻合。

这是已确认的代码差异和阻塞风险，尚不是已复现的超时根因。
现在已能确认这次超时对象是 SpringBoard；短日志没有线程栈，无法确认具体阻塞调用。
初次审查只生成记录；后续用户授权的预防性修复见文末。没有关闭功能或发布安装包。

## 收到日志后的复核

两份用户提供的日志均标识设备为 `iPhone14,8`、iOS 16.0.2（20A380）。

### SpringBoard 看门狗事件

`userspace-panic-1795533643.705187-1.ips` 的正文为：

```text
no successful checkins from SpringBoard in 180 seconds
service: SpringBoard, total successful checkins in 270 seconds: 8, last successful checkin: 180 seconds ago
This panic was prevented by Dopamine and a userspace reboot was done instead.
```

同一记录中 backboardd、logd、thermalmonitord、runningboardd、wifid、configd
的最后成功 check-in 均为 0 秒前；mediaserverd 为 50 秒前。
因此这份记录明确报告 SpringBoard 的 check-in 超时，没有报告所有服务同时失联。
累计成功次数为 8，也不能描述为 SpringBoard 从未成功启动或从未报到。

该文件只有设备信息、check-in 汇总和拦截说明，没有 SpringBoard 线程栈、
插件清单或用户安装包版本。不能从 180 秒这一个数字反推出具体阻塞函数，
也不能证明一定是低电量计划、耗电记录或第三方插件导致。

源码对应 `BaseBin/launchdhook/src/jbserver/jbdomain_watchdog.c` 的
`watchdog_intercept_userspace_panic`：保存该说明并设置安全模式标记；
`BaseBin/watchdoghook/src/main.m` 在拦截成功后调用 `reboot3(RB2_USERREBOOT)`。
日志与这条拦截路径一致，说明这次看门狗事件走到了 Dopamine 的恢复处理，
不能据此认定是看门狗 hook 自身失效。拦截器也不会消除 SpringBoard 超时的原因。

### 另一份 panic-full 是 launchd Mach 异常

`panic-full-2026-11-25-051205.0002.ips` 的报告时间为
2026-11-25 05:12:05（+0800），panic 原因为：

```text
userspace panic: Mach exception occured on thread 2774. A detailed report has been written to the file launchd-1795554698.975139-1.ips.
```

该措辞对应 `BaseBin/libroothider/src/crashreporter.m` 的
`crashreporter_catch_mach`，在生成详细报告后通过 `ABORT` 调用
`reboot_np(RB_PANIC | RB_QUICK, message)`。这份 panic-full 的直接触发原因
是 launchd 中捕获到 Mach 异常，不能将其描述为 SpringBoard 180 秒超时报告。

异常线程为 2774，队列名 `com.apple.xpc.launchd.spawn`；发出内核 panic 的
线程为 5339，两者不同。线程 2774 的用户栈包含未符号化的镜像偏移；
初次没有匹配 UUID 的符号文件，无法仅由这些偏移命名故障函数；
随后补充的详细报告已提供下节所列的调用链。
同一快照中 SpringBoard 主线程 1517 位于 `mach_msg receive on port set`
等待；这是另一时刻的快照，不能拿它作为上一次超时现场的主线程阻塞栈。

按文件名中的 Unix 时间换算，userspace-panic 对应
2026-11-24 23:20:43.705（+0800），launchd 详细报告名对应
2026-11-25 05:11:38.975（+0800）。这些是依文件名推算的时间，
不是已核实的连续事件链。相隔数小时，不能声称看门狗重启立即引发了该次 launchd 异常。

初次复核时该目录没有详细报告；随后用户补充提供了准确命名的
`launchd-1795554698.975139-1.ips`，分析见下一节。
SpringBoard 的 180 秒超时仍缺少同一时刻的线程栈；
2026-11-24 23:20 左右的卡顿采样或 watchdog 详细诊断可用于独立定位。

### launchd 详细报告与实际加载版本

新报告与 panic-full 的线程 2774、报告文件名及设备信息吻合，
确认它是前一份 panic-full 指向的详细报告。异常类型是 `EXC_BREAKPOINT`，
去除 PAC 后 PC 为 `0x1F2216110`，对应 libsystem_platform 偏移 `0x6110`。
关键调用链由底向上为：

```text
roothide_launchd___posix_spawn_prehook
  dispatch_once
    fix__iosConnect + 0x38
      ElleKit MSFindSymbol
        findPrivateSymbol
          sharedCachePath
            libobjc.A.dylib / 未关联地址
              libsystem_platform.dylib + 0x8A8 / + 0x6110
```

可以确认是在第一次匹配可移除应用路径时查询 IOSurface 私有变量的过程中崩溃，
而不是已走到 `IOServiceOpen` / `IOServiceClose` 的错误检查。
没有足够符号把顶部 `<redacted>` 命名为某个特定锁函数；
也不能只见 `EXC_BREAKPOINT` 就认定误删了 iOS 15 spinlock 补丁。
报告中没有低电量调度或耗电记录调用。

截至本轮修改前，官方 RootHide 提交 `18049d5a`、审查分支 `3ac500e9`
和当前分支中 `fix__iosConnect` 的查询/重连逻辑一致；
`7d6a3874` 的裁剪没有改动此函数的执行逻辑。
官方 RootHide 与当前 HEAD 的内置备用 ElleKit Git blob 同为
`9996519e41c7e6ab9a6ca0939e6a4d5c81a92e0f`。
这只是仓库内容对比，不能代替用户设备上的二进制身份核实。

进一步从本地留存的 2026-11-24 构建包
`TIPA/2026-11-24-头像显示-c57e4182/Application/Dopamine-rh-rc9-c57e418.tipa`
直接解读其内嵌 basebin 的 arm64e Mach-O `LC_UUID`，与 panic-full 中按
详细报告镜像加载地址对应的 UUID 比较：

| 组件 | 设备 panic-full UUID | 留存 c57e418 包 UUID |
| --- | --- | --- |
| launchdhook | `666da958-85fd-3b77-897d-bb0ce5afa388` | `d1f2ae02-5cad-37fb-9986-cc706aeedd7e` |
| libjailbreak | `b05c13a9-45cd-3233-8f39-a560fad4d338` | `a3507fb2-d6c4-3cbb-bffb-042e6dcfc0a9` |
| fallback ElleKit | `ad0ac18b-369e-30c2-acc9-0136cba9aa78` | `7a1d699d-bdaf-302d-92db-9806410b3614` |

三者均不相同。详细报告还将 `fix__iosConnect` 归入 launchdhook，
而 c57e418 包中该函数定义在 libroothider，launchdhook 对它是未定义引用。
这些是版本/布局不一致的证据，不能直接归因为某一个源码回归提交。
可能是设备仍运行其他构建的 basebin，也可能用户实际安装的包就与留存包不同；
仅凭 UUID 不匹配不能断言发生了新旧组件混装。
提取证据保存于 `.audit-artifacts/launchd-package-uuid-20261125.json`。

`DOEnvironmentManager.updateEnvironment` 将 App 内的 basebin.tar 暂存更新，
成功后调用用户空间重启；普通注销只重启 SpringBoard，不能证明 launchd 的
常驻库已替换。下一轮实机复测需记录实际安装包及运行时版本，确认更新路径成功。

### iOS 16 裁剪与新增功能的专项复核

本轮按 `18049d5a → HEAD` 及裁剪提交 `7d6a3874` 核对：

- 看门狗源文件与官方 RootHide 一致，Makefile 仍构建 watchdoghook，
  c57e418 的内嵌 basebin 也确实包含该库。本次 userspace-panic 还记录了成功拦截。
- IOSurface 私有变量重连函数、调用它的 spawn `dispatch_once`、备用 ElleKit、
  libjailbreak、libroothider、roothidehooks 与 iOS 16 的 arm64/arm64e dyldhook
  均保留；留存包中所列的这些运行时文件存在。没有“源码在但打包漏了这些库”的证据。
- 删除的 spinlock 修复入口原本受 `arm64e && iOS < 16` 限制；
  hookd 初始化原本受 `iOS >= 19` 的检查限制；stock_fixes 中
  mach_ports_lookup 重实现用于 iOS 18+。它们不是该设备 iOS 16.0.2 原本执行的分支。
  移除它们不能直接解释这次发生在已加载 ElleKit 内的符号查询崩溃。
- 删除的 `gAPIs` 分支在对应上游代码注明 iOS 18.4+；iOS 16 的 `gDyld`
  查询路径保留。iOS 16 的 Mach 消息生成代码和保留端点编号也有源码检查覆盖。
- cfprefsd 保留原 iOS 16 使用的 legacy ABI；runningboardd 保留原
  iOS 16 `_allowedLockedFilePaths` hook。没有把它们改接到 iOS 17 的函数签名。
- 新增低电量/耗电记录确实进入 SpringBoard 每次重启流程，原有同步根目录查询
  和主线程写盘属于真实的新增阻塞风险；已做预防性修改，但短日志不能证明责任。
- 自定义挂载恢复入口属于 App 越狱启动流程；普通注销不会直接重跑该方法。
  已存在的挂载和第三方插件仍可能影响系统，不能用入口位置排除它们。

以上是对本次日志相关路径的核对，并非已经在实机证明所有裁剪变化都无回归。
目前不应为这次故障盲目恢复 iOS 15/18/26 的整套实现，也不应把所有责任
归于新增功能。先确认实际运行组件，再分别验证已定位的 launchd 路径和
仍缺栈的 SpringBoard 超时。

### 根据详细栈实施的局部修改

`BaseBin/libroothider/src/launchd.m` 的 `fix__iosConnect` 改用
项目已有的 `litehook_find_dsc_symbol` 查询 `__iosService`、`__iosConnect`，
替代此处 `MSGetImageByName` / `MSFindSymbol`，避开本次报告中的
ElleKit `sharedCachePath` / Swift / Objective-C 查询路径。
litehook 的该读取器也已被 systemhook 使用，libjailbreak 构建会编译并导出它。
libroothider Makefile 增加对应头文件搜索路径，没有升级或整体替换 ElleKit。

重连时机、先打开新连接再关闭旧连接的顺序，以及符号缺失/IOKit 错误的原有
assert 检查均保留。因此它是替换已观察到的查询崩溃路径，不是在错误时
直接跳过 IOSurface 修复；也不意味着 PID 1 以后任何错误都不会再触发 panic。
真实设备 `.symbols` 文件兼容性、实际查得变量地址及恢复效果仍待构建/实机验证。

新增 macOS C 夹具从生产源码提取该函数，模拟 IOSurface 句柄并验证未初始化
连接不重开、已有连接先开后关、符号缺失和打开失败仍按原有检查停止。
Windows 不能运行此夹具。打包流程新增 arm64/arm64e libjailbreak 的
`_litehook_find_dsc_symbol` 导出检查，尚未执行云端构建。

本轮九个测试文件共 208 项，190 通过、0 失败、18 平台跳过。
日志：`.audit-artifacts/launchd-iosurface-tests-20261125.log`。
这不包含 iOS 动态库编译、真实共享缓存解析或设备注销测试。

### 对现有修复的影响

新证据支持继续保留已完成的 SpringBoard 启动预防性修复：消除首次根目录
同步 IPC、延后新增服务初始化、合并首次刷新、异步发布状态。
这些改动针对已确认存在的阻塞风险，方向合理；日志没有证明原始故障栈经过这些调用，
所以仍需 macOS 构建和更新 basebin 后的实机注销验证。
初次只据两份缺少详细栈的记录时没有修改 launchd；补充收到详细报告后，
才按上一节替换了已观察到的符号查询路径。没有关闭看门狗或调整超时时间。

## 对比身份

通过 `git -c http.sslBackend=openssl ls-remote origin ...` 查询公开远端，结果为：

| 对象 | 提交 |
| --- | --- |
| ZQBB `3.x_modify_` / `3.0.13` 标签 | `6522285754fd9c4574e9afc352dc31fe548567fc` |
| ZQBB `3.x_roothide` | `18049d5a81b294d3387b3af30c54558d04b8b5f5` |
| ZQBB `3.x_roothide_AI_review_fix` | `3ac500e9d95553c2ffd651894315d79b31ee8aed` |
| 当前分支 `codex/power-schedule-controls` | `eaffc3d0` |

本地已保存这些提交的源码。当前 HEAD 与 `3.x_roothide` 的共同祖先就是
`18049d5a`，因此以该分支检查 RootHide 运行时差异，同时参考发布标签及审查分支。
不能把 `3.x_modify_` 的 rootless 实现直接当成 RootHide 实现整体替换。
没有取得用户安装包的身份，也没有比对官方发布 IPA 的二进制；公开源码分支与
发布附件之间的对应关系不能仅由附件名称证明。

## 首要风险：新增任务进入 SpringBoard 启动主队列

证据位置：

- `BaseBin/roothidehooks/src/springboard.x:131`：`sbInit` 初始化原有 hook 后，
  无条件调用 `rcLowPowerScheduleStart` 和 `rcBatteryRecordStart`。
- `BaseBin/roothidehooks/src/lowpowerschedule.m:408`：注册主队列通知，
  并立即向主队列提交第一次 `refresh`。没有等待桌面启动完成的生命周期门槛。
- `BaseBin/roothidehooks/src/batteryrecord.m:294`：同样注册通知、提交启动刷新。
- `BaseBin/roothidehooks/src/lowpowerschedule.m:89` 和
  `BaseBin/roothidehooks/src/batteryrecord.m:54`：通过
  `jbclient_get_jbroot()` 获取根目录。
- `BaseBin/libjailbreak/src/jbclient_xpc.c:91`：该函数首次调用在 `dispatch_once`
  内同步请求 launchd；`:64` 使用 `xpc_pipe_routine_with_flags(..., 0)`。
  调用链没有我们设置的超时或异步完成机制。已预热缓存时不会重复发送该请求，
  不能声称每次刷新都进行一次 IPC。

风险在于：如果该首次请求发生在 SpringBoard 主线程且服务端响应迟缓，
主线程会等待它；`dispatch_async` 到主队列并不会把实际工作移到后台。
现有 `@try/@catch` 只能处理异常，不能打断没有返回的同步调用。

ZQBB 对比的 RootHide `sbInit` 仅初始化原有 hook，没有这两个新增服务。
低电量调度启动入口在 `9eb5c99b`（2026-11-08）加入，耗电记录启动入口在
`5bcb7d12`（2026-11-20）加入。未知用户安装包版本，不能直接把后者定为责任提交。

## 放大因素

1. **关闭功能仍有启动工作。** 低电量配置缺失时，`refresh` 仍先获取根目录，
   检查配置并写入 disabled 状态。耗电记录同样会读取历史、配置和命令，
   最终发布 idle 状态。因此在界面关闭计划，不能完全排除这条启动路径。
2. **低电量调度重复启动刷新。** 低电量服务已提交自己的初次刷新；耗电记录的
   初次刷新又先调用 `rcLowPowerScheduleRefresh()`。启用计划时可能重复撤销和
   注册计时器、读写状态。这是额外工作，本身不足以证明会超过看门狗时限。
3. **电量接口仍在主线程调用。** `requestPowerMode:` 经 `NSInvocation`
   同步调用 `_PMLowPowerMode`。源码能够证明调用线程，不能证明该系统私有
   方法内部必然阻塞。启动追赶未处理的计划事件时会经过这条路径。

## 已核实的其他差异

- `watchdoghook/src/main.m` 和 `launchdhook/src/jbserver/jbdomain_watchdog.c`
  与 ZQBB `3.x_roothide` 完全一致（`git diff --quiet` 返回 0）。
  没有证据说明我们改坏了看门狗拦截器。
- 官方 `473d52e4` 的 `logd_helper` 插件加载排除已由 `cc81d3d8` 回移，
  当前 `systemhook/src/main.c` 包含该项。不能用“漏合这个死锁修复”解释现象。
- 新快照保存 hook 的主要做法也存在于 ZQBB `3.0.13` 的
  `BaseBin/rootlesshooks/SpringBoard.x`。我们的 RootHide 版本增加了路径范围检查，
  并保留 Apple 内部越狱应用的原有例外，不能单凭改动量认定是新死锁。
- `restoreCustomMounts` 的新增调用位于 App 越狱启动流程。
  普通 SpringBoard 注销重启不直接重新执行该方法；应区分注销与用户空间重启。
  已存在的挂载仍可能影响系统，不能据此排除用户挂载配置的影响。
- 审查分支含配置缓存和进程监听修复，而当前分支未全部采用。
  这些不是已证明的发布包差异，不能将未合并审查分支等同于本次回归根因。

## 修复与验证顺序

1. 首先消除新增服务首次查根目录对 launchd 的同步依赖，使用注入阶段已经取得的
   本地根目录，并核实动态库符号解析与原有 `JBROOT_PATH` 的一致性。
2. 将两个新增服务的激活移到明确的 SpringBoard 启动完成阶段，合并初次调度刷新。
   生命周期调整只能减少启动竞争，不能代替消除同步阻塞。
3. 将配置解析、历史读写等文件工作移离主线程；保留串行状态管理。
   系统私有电量 API、UIKit 电量采样、持久计时器的线程要求需分别确认，
   不能简单把所有调用搬到全局并发队列，也不能新增主线程同步等待后台的环路。
4. 制作保持其他运行时一致、仅隔离两个新增启动入口的对照构建，验证是否消除
   注销后的现象，再逐一恢复以区分调度与记录。此构建属于诊断用途，
   不能把功能被停用的结果当成保留功能后的正式修复。
5. 对照时必须核实设备实际使用的 `/basebin/roothidehooks.dylib` 已更新。
   仅换 App 安装包或只注销不能证明新的 basebin 已加载。项目的
   `DOEnvironmentManager.updateEnvironment` 通过暂存更新后用户空间重启应用运行时更新。

实机矩阵至少覆盖：两个计划从未开启、均已关闭但有历史、仅低电量计划、
仅耗电记录、计划执行期间注销、锁屏状态注销后恢复。
如仍触发，日志中应保留超时服务名、check-in 描述和阻塞线程栈，继续定位系统服务链路。

## 验证边界

本次进行了公开远端提交身份核实、Git 源码差异和实际控制流检查。
未运行 iOS 实机、未复现注销、未生成安装包；不作故障已根治的声明。
既有 Foundation 测试使用模拟时钟、电量及计时器，即使通过也不能证明
SpringBoard 与 launchd 在真实注销期间不存在服务等待或看门狗超时。

## 用户授权后的预防性修复

保留低电量调度、耗电记录、定时唤醒、模式变更后的延迟确认，以及采样前后的
电量模式顺序。没有修改看门狗拦截器，也没有用延长看门狗时间掩盖问题。

- 新增 `springboardservices.m`：构造阶段只订阅
  `UIApplicationDidFinishLaunchingNotification`。收到通知后再异步进入主队列，
  初始化两个服务并执行一次有序恢复；移除了两个服务各自的即时启动刷新。
- 新增 `scheduleruntime.m`：通过 `dlsym(RTLD_DEFAULT, "JB_RootPath")` 读取
  systemhook 注入时已保存的根目录；缺失时返回 nil，不退回同步 launchd 查询。
  没有直接调用 `get_jbroot()`，因为该名字在 systemhook 与 libjailbreak 中均有实现，
  二级命名空间链接可能绑定到尚未初始化根目录的 libjailbreak 实现。
- 两个服务的状态/历史发布改由共享串行 I/O 队列执行。提交前深拷贝嵌套可变记录，
  继续采用原来的临时文件、权限及原子替换逻辑，只在落盘成功后发送通知。
- 耗电记录写入失败后仍会停止当前计时器；使用发布代次检查，防止旧写入的失败
  回调误停后来开始的新记录。失败回调回到主线程处理计时器，不跨线程修改记录状态。
- 构建验证增加打包后的 arm64/arm64e systemhook 根目录符号导出检查，
  防止日后链接/裁剪改变使无 IPC 的根目录读取悄悄失效。

这次没有把整个状态机搬到后台线程。配置读取仍在主线程，以保留现有的变更检查
及采样顺序；系统私有模式接口、UIKit 采样和持久计时器也仍在主线程。
因此这次消除了新增根目录 IPC 与同步状态写盘，并降低了启动阶段竞争，
没有证明所有可能的主线程等待已消失。后续日志若指向剩余读取或私有 API，
应再针对实际栈实现异步读取/版本失效机制或隔离系统调用。

新增 macOS Foundation 原生夹具覆盖：启动通知前不恢复计划、通知返回后只初始化
一次、阻塞 I/O 队列时主 run loop 仍响应、嵌套快照不受后续修改影响、顺序提交、
写入失败回调，以及旧失败不取消新记录。既有模式确认及耗电状态机夹具也已适配
异步落盘。当前 Windows 环境无法执行这些 Foundation 夹具或编译 iOS 动态库，
需要 macOS 构建及实机注销测试后才能确认发行包效果。

本地验证结果：按 `.github/workflows/build.yml` 的九个测试文件执行，
共 206 项，189 通过、0 失败、17 跳过（包含仅 macOS/iOS 可执行的检查）。
`git diff --check` 通过。日志：`.audit-artifacts/watchdog-preventive-tests-20261125.log`。
首次运行曾因沙箱用户与 XPF 仓库所有者不同触发 Git 所有权检查；
复核时只给测试进程增加该 XPF Git 目录的 `safe.directory` 例外，
没有修改全局 Git 配置。相关三文件复核为 69 项、63 通过、0 失败、6 平台跳过。

本地未提交/推送这些修改，未触发云端构建。新增的原生夹具及打包后符号检查
会在后续 macOS 构建中运行；它们目前只是待执行的验证，不能计入本地通过项。

## 2026-11-25 测试构建准备

测试分支以已成功构建的 `4efcdddc9771e120c59004121e52529549657178` 为基础，
保留此前头像、授权备份及设备型号修复，仅叠加本报告所述看门狗相关补丁。
独立检出目录复核九个测试文件：207 项，189 通过、0 失败、18 平台跳过；
`git diff --check` 通过。原生夹具及实际 iOS 编译由本次 macOS 云端任务执行。
此前本地验证数字对应当时工作区，以上数字对应这次实际提交的源码快照。
