# 2026-11-04 代码健康审计

## 范围与结论

- 仓库：`G:\RootHide\ZQBB IOS16\Dopamine-roothide-ios16`。
- 分支：`ios16-roothide-3.0.12`。
- 已提交审计范围：`1754adf6..851480cc`，即今天的 5 次提交。
- 同时复查本轮新增的 About 玻璃改动；该改动不包括下面六项问题的修复。
- 未发现此范围修改 BaseBin、越狱执行引擎、bootstrap、签名、Jetsam
  算法、插件数据库或导入授权实现。`startJailbreak` 方法指纹保持一致。
- 发现 6 项 P2 待修问题。P2 表示应安排修复，不等同于已在手机上复现。
  本次没有确认的 P0/P1 问题，也不能据此保证不存在其他问题。

这是代码路径审查与逻辑模型验证，不是 iOS 动态安全审计。
不应因 UI 审计而移除越狱、删除 bootstrap 或清理用户插件。

## 1. [P2] 媒体删旧文件早于权威主题镜像提交

位置：
[媒体提交与删除](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-ios16/Application/Dopamine/UI/DOCustomGlassMediaStore.h:228>)；
[镜像延迟写入](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-ios16/Application/Dopamine/UI/DOCustomGlassThemeSync.h:128>)；
[启动时镜像覆盖本地值](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-ios16/Application/Dopamine/UI/DOCustomGlassThemeSync.h:92>)。

保存新图片后，MediaStore 更新 NSUserDefaults，确认进程内能读到新文件名，
随即删除旧文件。但是启动时真正优先采用的外部主题 plist，要等通知后的
0.3 秒定时回调才写入；文件写入失败也只记日志。

若在这个窗口被杀进程，或外部镜像写入失败，下一次启动会把旧文件名重新
覆盖回本地，而旧文件已经删除。表现可能是壁纸/头像消失，新文件成为孤儿。
这不是“先写新图、后删旧图”本身能解决的问题。

验证：按实际调用顺序建立的中断模型得到
`local = old.jpg`，但磁盘只剩 `new.jpg`。这是逻辑模型，不是实机杀进程测试。

建议：将媒体文件名与权威镜像作为同一次受控提交；镜像成功前保留旧媒体。
统一串行协调状态读写，并为进入后台/重启等边界增加可靠的持久化处理。
不要仅在另一个源文件中直接复制 static header 状态来调用 Flush。

## 2. [P2] 异步导入没有“最后一次选择优先”的保护

位置：
[壁纸导入回调](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-ios16/Application/Dopamine/UI/DOCustomGlassView.m:1008>)；
[头像导入回调](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-ios16/Application/Dopamine/UI/DOMainViewController.m:126>)；
[视频及海报分步提交](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-ios16/Application/Dopamine/UI/DOCustomGlassMediaStore.h:306>)。

相册选择器在导入完成前就关闭，页面仍允许再次选择；各完成回调直接保存，
没有请求代数、串行提交或失效检查。先选择的慢 Live Photo/视频可以晚于
后选择的照片完成，进而覆盖用户更新的选择。

页面已经返回时，weakSelf 只会阻止部分界面刷新，不会阻止之前的回调继续
写入媒体和偏好。并发的静态图/视频导入还可能交错海报与视频键的提交。

建议：为头像/壁纸分别管理导入代数；只允许当前请求进入串行提交阶段。
视频与海报作为一组提交，过期回调只清理自己的暂存资源。
通过慢资源 A、快资源 B 的逆序完成，以及导入中返回页面进行实机验证。

## 3. [P2] 所有外观滑块都反复触发整图模糊

位置：
[滑块统一处理](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-ios16/Application/Dopamine/UI/DOCustomGlassView.m:1522>)；
[无条件提交壁纸模糊](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-ios16/Application/Dopamine/UI/DOCustomGlassView.m:1533>)；
[全局队列上的 Core Image 工作](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-ios16/Application/Dopamine/UI/DONavigationController.m:512>)。

即使只调整 Glass 透明度、高光或自身模糊，代码仍无条件提交同一个壁纸、
同一个强度的整图模糊任务。快速连续滑动会产生大量过期工作。

generation 检查位于图像渲染之后，只阻止旧结果显示，不能取消已经安排的
计算。它也没有合并等待中的请求。2048 像素边长限制降低单次成本，但不限制
任务数量。实际卡顿、内存峰值和能耗尚未测量，不能声称已经发生 Jetsam。

建议：只在壁纸源或壁纸模糊值变化时提交，缓存最后应用的参数；使用有界、
可合并的串行工作队列，并在昂贵计算前检查请求是否过期。
用 Instruments 对快速拖动分别测量 CPU、内存与主线程帧耗时。

## 4. [P2] 头像停靠缩小仍会牵动面板布局

位置：
[停靠时修改头像高度](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-ios16/Application/Dopamine/UI/DOMainViewController.m:476>)；
[资料块依赖头像底边](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-ios16/Application/Dopamine/UI/DOMainViewController.m:899>)；
[整体栈垂直居中](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-ios16/Application/Dopamine/UI/DOMainViewController.m:705>)。

虽然隐藏资料文字使用 alpha、不移除 arrangedSubview，但用户名顶部直接锚定
头像底边。头像从普通尺寸变为停靠尺寸，会缩短资料块，进而改变 mainStack
的自然高度。在居中约束成立、文本高度不变时，后续面板仍会上移。

按现有约束的逻辑模型：

| 布局 | 头像高度减少 | 后续面板预计位移 |
| --- | ---: | ---: |
| 紧凑 iPhone | 26 pt | -13 pt |
| 普通 iPhone | 34 pt | -17 pt |
| iPad | 46 pt | -23 pt |

这是约束推导值，不是截图测量。空间受限时具体结果取决于 Auto Layout
压缩优先级，但“仅改 alpha”不能证明面板位置保持不变。

建议：保留固定的原始头像占位高度，让根视图中的头像独立缩放和停靠。
增加实际布局前后 frame 对比。现有源码测试名称已收窄，不再声称证明面板不动。

## 5. [P2] 更新入口的预留空间没有计入负向按钮偏移

位置：
[更新占位高度](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-ios16/Application/Dopamine/UI/DOMainViewController.m:1024>)；
[越狱按钮负向偏移](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-ios16/Application/Dopamine/UI/DOMainViewController.m:1120>)；
[更新按钮位置](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-ios16/Application/Dopamine/UI/DOMainViewController.m:1359>)。

更新按钮高 30 pt，底部位于越狱按钮顶部上方 12 pt。越狱按钮本身又有
-24/-30 pt 的视觉偏移，原来的 updateReserve 没有完整抵消它。

当前约束下，更新按钮顶部相对面板底部的距离为：
`2 * mainSpacing + updateReserveHeight + jailbreakVerticalOffset - 12 - 30`。

逻辑模型结果：紧凑 Home 键 iPhone 为 -14 pt，普通 Face ID iPhone 为
-4 pt，即更新按钮会侵入面板区域；iPad 为 +8 pt。

远程版本检查当前关闭，但 environmentUpdateAvailable 仍可触发入口，
所以不能把这一问题当成不可达代码。

建议：由真实更新按钮高度、间隔及越狱按钮偏移共同推导占位高度；在没有
更新、有环境更新两种状态分别检查首尾边界和点击区域。

## 6. [P2] 其他越狱环境被当作本 RootHide 的重启可用状态

位置：
[首页按钮可用状态](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-ios16/Application/Dopamine/UI/DOMainViewController.m:996>)；
[本环境的 jbctl 路径及权限要求](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-ios16/Application/Dopamine/Jailbreak/DOEnvironmentManager.m:335>)；
[原有菜单状态判断](<G:/RootHide/ZQBB IOS16/Dopamine-roothide-ios16/Application/Dopamine/UI/DOMainViewController.m:1442>)。

新首页为 respring/userspace reboot 使用
`isJailbroken || isJailbrokenWithOtherJailbreak`，旧菜单只允许 `isJailbroken`。
但执行方法仍调用本 RootHide 路径下的 jbctl，并没有增加对其他越狱的支持。

只激活其他越狱时，这两个按钮仍可点；界面先执行 fadeToBlack，而后执行
可能失败，且没有恢复界面的失败路径。这会暴露不适用的操作并可能停留在黑屏。
这不表示检测到了插件损坏，也不表示会删除其他越狱。

建议：区分“禁止重复越狱”的 any-jailbreak 状态与“允许本环境维护”的
RootHide 状态，恢复这两个维护按钮的原有状态边界。

## 本轮 About 玻璃改动

已按用户后续要求补齐：

- About 与 Settings 共用现有壁纸和玻璃材质；仅两页进入全屏玻璃布局。
- 返回键和左缘返回保留；为滚动列表保留安全区和顶部空间。
- 同时覆盖零普通行、但含致谢名单分组标题的区段。
- 不改 Credits.plist、名单链接、collection delegate、原业务方法和许可证返回。
- 处理复用、主题通知、过期材质清理及观察者释放。
- 未借这次样式改动重写上面六项逻辑，也未移植授权。

许可证页面本身仍是原生样式，本轮没有要求将它也改成玻璃。

## 验证与限制

- 改动前：45 项源码测试通过；About 玻璃改动后：48 项通过。
- `git diff --check` 通过；原越狱执行、Settings 业务方法与 Credits 业务方法
  的现有指纹检查通过。
- GitHub 完整构建 #22（`41697683880`，源 `851480cc`）成功，
  包检查及 IPA/TIPA 上传成功；build job 实际耗时 5 分 30 秒。
- #22 不包含本轮 About 玻璃改动。新改动需独立原生编译及手机验证。
- 布局数值与中断保存场景在 Node 逻辑模型中核对，不应称为 UIKit 实测。
- 本机 Windows 无 Xcode/UIKit，未执行 Instruments、Main Thread Checker、
  Thread Sanitizer 或真机内存/相册权限测试。未下载或解包新的安装包。

源码测试主要检查特征、顺序和方法指纹，不是动态 UI/并发测试。
不能用 48 项绿灯证明头像不位移、导入没有竞争或媒体提交抗中断。

另有需实测的非本轮阻断项：主页按钮中的强 self 捕获在旧基线已存在，
不能冒充今天新增问题；大尺寸照片的解码峰值、私有 Core Animation 接口的
设备回退、中文输入法与组合字符长度上限也需要单独验证。

## 建议修复顺序

1. 媒体与镜像的一致性、导入代数与串行提交。
2. 壁纸模糊请求合并和参数去重。
3. 固定头像占位、更新入口空间、维护按钮状态边界。
4. 再执行真机导航、长时间后台/前台、大图及慢 Live Photo 回归。

本报告仅保存审计结果；不要将待修条目误认为已修复或已实机验证。
