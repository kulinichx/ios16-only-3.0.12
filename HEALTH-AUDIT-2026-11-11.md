# RC9 iOS 16 代码健康审计

日期：2026-11-11，America/Denver。

## 发现与结论

本轮记录 1 项 P1、8 项 P2。最需要先处理的是授权设备绑定和两个挂载副本删除问题。
当前版本编译与源码检查通过，但不宜据此称为“全面健康”，建议先修复这三项再扩大分发。

以下是源码路径确认的缺陷或风险，不是手机上已经复现的故障。
P1 表示应优先修复；P2 表示应安排修复，不代表每次正常使用都会触发。
这不是越狱利用链的完整安全认证，也不能保证不存在清单以外的问题。

### 1. [P1] 授权设备身份可由可迁移的本地状态决定

位置：[DOSupporterLicense.h:1457](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/DOSupporterLicense.h:1457>)；
[旧授权迁移:1479](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/DOSupporterLicense.h:1479>)；
[设备比较:1627](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/DOSupporterLicense.h:1627>)。

`DORHSupporterDeviceCode` 优先直接采用外部状态中的 `DeviceCode`，不与当前硬件核对。
没有该值时，迁移逻辑从旧签名授权中取出设备码，再用这个同一设备码验证该授权，随后将其认作本机身份。
签名仍然会检查，但它证明的是授权由签发者签署，不能证明接受迁移的就是原手机。

触发条件：另一台设备获得有效授权及可迁移状态，并能将其置入应用读取的状态存储。
后果：接收设备可以沿用原设备身份通过 RH1 验证，影响防止授权复制传播的目标。
这不是私钥泄露，也不等于仅复制 TIPA 就必然激活；正常已初始化界面直接粘贴异机授权仍可能被拒绝。
已有硬件身份和设备密钥诊断代码，但当前 RH1 验证路径没有强制它们参与绑定。

建议：将签名授权绑定到可独立核实的本机身份或不可迁移密钥证明；旧 RC9 授权需有可信迁移方案。
不能为修复此项而突然让所有现有授权失效。增加真实 Foundation/Security 层的异机状态迁移拒绝测试。

### 2. [P2] 新增挂载保存失败的回滚会删除原有副本

位置：[DOSettingsController.m:944](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/Settings/DOSettingsController.m:944>)；
[副本复用:74](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/BaseBin/jbctl/src/internal.m:74>)；
[副本删除:913](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/Jailbreak/DOEnvironmentManager.m:913>)。

新增时若 `/mnt` 下已有非空副本，底层会复用，不会新建。
但挂载成功、列表保存失败后，界面回滚会卸载并无条件删除副本，没有记录它是否由本次操作创建。

触发示例：用户先“仅从列表移除”，保留自己修改过的字体副本，再次新增同一路径，恰遇列表写入失败。
后果：原有自定义副本被删除；若该目录本来已挂载，还可能撤销原有挂载。
这里删除的是当前 JBROOT `/mnt` 下的用户副本，不是系统原字体目录。

建议：记录副本和挂载的操作前状态；失败只撤销本次新增的资源，绝不能以“回滚”为由删除复用数据。
增加“原有副本 + 保存失败”和“原已挂载 + 保存失败”的故障注入测试。

### 3. [P2] 固定 `_tmp` 暂存路径会与另一个合法挂载副本冲突

位置：[internal.m:82](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/BaseBin/jbctl/src/internal.m:82>)。

为路径 `/.../A` 创建副本时，暂存目录固定为 `/mnt/.../A_tmp`，且复制前会删除已存在的该目录。
如果用户也配置了真实存在的 `/.../A_tmp`，这个目录就是另一个挂载的正式副本，而非本次操作的垃圾。
此时新增 A 会删除 A_tmp 的用户数据，之后还会把该位置当暂存目录移动走。

建议：使用唯一暂存目录，放在与正式副本命名空间分离的位置，只清理本次创建的暂存数据。
测试相邻的 A/A_tmp 路径和上次中断的暂存残留，保证不删除其他挂载数据。

来源说明：`_tmp` 命名来自所对照的 ZQBB 实现；本次适配又加入了主动删除已有暂存路径的处理。
不能把当前整套风险或适配改动简单描述成 ZQBB 原码逐行照搬。

### 4. [P2] 壁纸/头像删旧文件早于权威主题镜像提交

位置：[DOCustomGlassMediaStore.h:229](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/DOCustomGlassMediaStore.h:229>)；
[ThemeSync 启动恢复:92](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/DOCustomGlassThemeSync.h:92>)；
[延迟镜像:137](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/DOCustomGlassThemeSync.h:137>)。

MediaStore 保存新文件、更新进程内 defaults 后即删除旧文件。
外部 `glass-theme.plist` 则经通知后延迟 0.3 秒写入；写失败只记日志。
下次启动优先采用该外部镜像。中断或镜像写失败时，旧文件名可能被恢复，但旧文件已删除。
后果是壁纸或头像消失，新文件可能成为未引用文件。这项 11 月 4 日已记录的问题仍然存在。

建议：媒体引用和权威镜像按同一次受控提交处理；权威提交成功之前保留旧文件。
通过提交故障注入验证，不应只检查“defaults 写入在删除之前”的源码顺序。

### 5. [P2] 异步媒体导入缺少“最后一次选择优先”的提交保护

位置：[壁纸导入:1049](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/DOCustomGlassView.m:1049>)；
[头像导入:193](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/DOMainViewController.m:193>)；
[视频保存:317](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/DOCustomGlassMediaStore.h:317>)。

选择器立即关闭，提供者异步完成后直接保存，没有导入请求代数或串行事务提交。
先选择的慢资源 A 可以晚于后选择的快资源 B 完成，并覆盖 B；视频、海报引用也可能交错更新。
weakSelf 限制部分界面刷新，但不阻止过期回调写入文件和偏好。授权复核并不能解决请求顺序。
这项 11 月 4 日问题仍然存在。

建议：头像和壁纸分别管理请求代数，只有当前请求可以提交；视频与海报作为一组原子发布。
过期导入仅清理自己的暂存资源。增加 A/B 逆序完成和页面退出中的导入测试。

### 6. [P2] 挂载复制与等待子进程发生在主线程

位置：[按钮回调:937](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/Settings/DOSettingsController.m:937>)；
[同步命令:887](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/Jailbreak/DOEnvironmentManager.m:887>)；
[等待退出:682](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/BaseBin/libjailbreak/src/util.c:682>)。

UIAlertAction 处理器直接调用 mount，内部同步 exec 并 waitpid；首次复制目录在 jbctl 中完成。
大目录、慢存储或子进程迟迟不退出时，UI 在此期间无法响应。
这确认了阻塞路径，不代表已经测得 watchdog 终止或具体卡顿秒数。

建议：经单一受控任务队列执行并显示忙碌状态、防止重入；界面更新回主线程。
提权上下文的切换必须一起审查，不能简单把现有提权代码随意并发执行。

### 7. [P2] 材质刷新反复执行授权校验及持久化写入

位置：[DOCustomGlassView.m:219](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/DOCustomGlassView.m:219>)；
[授权自愈:1686](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/DOSupporterLicense.h:1686>)；
[状态写入:1382](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/DOSupporterLicense.h:1382>)。

每个玻璃表面的 reloadMaterial 都调用授权验证；验证成功又无条件重写外部状态并 synchronize defaults。
连续调节参数会刷新多个表面，重复执行签名校验、plist 读写和同步调用。
确认存在冗余工作，但本轮未用 Instruments 测量耗电、CPU、闪存写入或掉帧。

建议：只有内容改变时才自愈写入；为渲染提供只读授权快照，在授权变化时失效。
越狱执行入口仍需可靠复核，不要为了优化重新引入“撤销授权后仍可越狱”。

### 8. [P2] 静态壁纸模糊任务没有合并，过期判断晚于昂贵计算

位置：[滑块处理:1590](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/DOCustomGlassView.m:1590>)；
[无条件提交:1623](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/DOCustomGlassView.m:1623>)；
[后台图像处理:552](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/DONavigationController.m:552>)。

即使只改玻璃透明度或高光，也提交同一静态壁纸和强度的整图模糊。
generation 检查在 Core Image 计算后，只能丢弃过期结果，不能避免过期计算或合并待处理请求。
快速滑动可积累冗余后台工作。视频已有提前返回，不属于此项；没有声称已发生内存终止。

建议：仅在壁纸或壁纸模糊强度改变时计算，缓存参数，采用可合并的有界工作队列。
这是此前审计遗留问题，不应误写成这次移植已经完成的优化。

### 9. [P2] 其他越狱状态下启用本环境专用维护按钮，失败后不能恢复界面

位置：[DOMainViewController.m:1089](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/DOMainViewController.m:1089>)；
[本环境命令:350](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/Jailbreak/DOEnvironmentManager.m:350>)；
[黑屏动画:1521](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-rc9-ios16-next/Application/Dopamine/UI/DOMainViewController.m:1521>)。

重启桌面/用户空间按钮以“本环境或其他越狱”作为启用条件，但实际操作仍依赖本环境的 jbctl 和提权通道。
只有其他越狱时，不能保证命令被执行；UI 先变为透明黑屏，void 包装又丢弃失败状态，未恢复 alpha 或 didFade。
此时可能没有重启却留下黑屏界面。这不是断言 RC9 自身正常越狱后的重启已经失效。

建议：只在本环境能力可用时启用；维护操作返回明确状态，失败恢复视图并报错。

## 审计基线与验证

- 本地目录：`G:\RootHide\ZQBB IOS16\Dopamine-roothide-rc9-ios16-next`。
- 分支：`rc9-ios16-next`；HEAD：`918c32adb2f99662a54a0e39b1e1f17dceade6b4`。
- 既有工作区状态：`BaseBin/XPF` 已修改，`TIPA/` 未跟踪；均未撤销或提交。
- 本轮未修改运行源码、测试脚本、授权状态、手机文件，也未执行挂载、签发授权或触发构建。
- 挂载来源固定对照：ZQBB `3.x_modify_` / `3.0.13`，提交 `6522285754fd9c4574e9afc352dc31fe548567fc`。
  该功能适配到了 RootHide，并非把 rootless 引擎整体合并；不能称作当前 RootHide 上游原样自带菜单。

本地复跑命令：

```powershell
node --test tests/ios16-contracts.test.cjs tests/glass-ui-contracts.test.cjs tests/supporter-license-contracts.test.cjs tests/lowpower-schedule-contracts.test.cjs
```

最终结果：103 项，100 通过、0 失败、3 跳过。跳过的是需要 Linux/macOS C 编译环境的抽取 C 测试。
重跑初期曾被 Windows 沙箱/宿主不同账号触发 XPF Git 所有权检查；只在测试进程中加入两个具体目录的
safe.directory 设置后全部可运行项通过，没有修改全局 Git 配置，也没有关闭所有仓库的所有权检查。

GitHub CLI 只读核实了运行 `42468237626`：HEAD 与上述提交一致，2026-11-08 UTC 原生构建成功，
build job 耗时 6 分 24 秒；日志显示测试 103 通过、0 失败、0 跳过。原生 Build、Verify TIPA、上传均成功。
这是已有构建的核验，不是 11 月 11 日重新进行的原生构建。

本地 TIPA：`TIPA/build-918c32a/Application/Dopamine-rh-rc9-918c32a.tipa`。
本轮 SHA256 复核一致：

```text
a66352102e41c4e1459f1480f60d92dd674ed3795564ae2e83225b0e87a207a6
```

`git diff --check` 通过。大部分现有测试是源码契约、指纹和逻辑模型，另有少量抽取 C 测试；
它们不能替代真实 Foundation/UIKit、安全存储、目录挂载、异常写入及生命周期测试。
例如“错误设备授权被拒绝”的源码契约不能证明上面的迁移设备身份路径安全。

## 其他核对与边界

- 越狱按钮有授权启用条件，startJailbreak 也有授权复核，不是单纯只将按钮变灰；问题在身份信任链。
- “安装白名单管理器”专用按钮及跳转方法已移除，现有用户的管理器和配置没有因该改动被卸载。
- 首页模式依据注入配置文件是否存在判断，与当前运行时代码约定一致；未找到新的确定误判。
  这不是管理器安装检测，也不能证明一个损坏配置可正常工作。
- 视频壁纸已有不做全屏模糊、非活动前台暂停、旧窗口退出播放的代码与契约测试。
  不能因此声称所有玻璃性能优化已经完整移植。
- 低电量调度及 iOS 16 精简契约通过；本轮没有确认新的确定功能缺陷。
  实际休眠唤醒、跨午夜/DST、SpringBoard 重启及各机型私有 API 行为仍属于真机验证边界。
- Jetsam 的 MB 路径相关源码/抽取 C 检查通过；不代表所有机型的额度效果已动态验证。
- 挂载启动恢复的阶段顺序尚无充分证据认定有错，本轮没有把它列为确认缺陷。
- 11 月 4 日旧报告还有布局项；本轮没有完整重测所有屏幕、字体尺寸和更新入口布局，不能把旧清单视作全部关闭。

## 建议处理顺序

1. 先修两个挂载数据删除问题，补保存失败和路径冲突测试，避免真实用户副本受损。
2. 单独设计并修复授权绑定，明确旧 RC9 授权兼容/迁移规则，禁止无条件采纳迁入设备身份。
3. 完成媒体事务提交及导入顺序保护，使用故障注入覆盖中断情况。
4. 处理主线程挂载、授权重复写入、静态图重复模糊和维护按钮失败恢复。
5. 原生构建后定向回归，再决定扩大测试范围；不因本报告要求用户清空越狱或删除插件。

本轮仅新增此报告，未提交、未 push。报告中的建议均未标记为已经修复。
