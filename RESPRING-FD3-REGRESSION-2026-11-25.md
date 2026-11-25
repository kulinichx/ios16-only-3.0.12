# RC9 注销错误 256 的 fd 3 回归（2026-11-25）

## 当前反馈与版本

用户报告 e781116 候选点击注销显示系统操作失败 256，之后观察到设备重启；安装插件后注销仍等待较久，有时注销两次才进入桌面。没有本次完整 ips，尚不能确认重启类型或 SpringBoard 阻塞位置。e781116 不得再描述为实机可用版本。

RC9 主树和隔离构建均为 basebin `.version=3.0.12`、`.version-roothide=30`，即 3.0.12.30。对照 Theme-v3 精确源码 e36e0cc 的两个值是 3.0.13 / 31。此前将对照目录版本套入当前包的表述有误。

`cmd_wait_for_exit` 返回 waitpid 原始状态；正常退出代码 1 对应 256。它不能单独区分 jbctl 握手失败、sbreload 退出 1 或 fallback 的退出 1。维护弹窗的代码没有触发 reboot 的分支。

## 可验证的缺陷与修复

e781116 的 App 管道两端都标记 FD_CLOEXEC，然后通过 adddup2 将读端映射到 3。若读端本来就是 3，iOS 16 的同号 dup2 不清除该标志，exec 时 fd 3 被关闭，jbctl 读取失败并退出 1。

依据 Apple XNU 标签 xnu-8792.41.9 的三个实际实现（iOS 16 系列源码，非设备 20A380 二进制反汇编）：

- `libsyscall/wrappers/spawn/posix_spawn.c`：adddup2 直接记录 PSFA_DUP2，无同号特殊处理。
- `bsd/kern/kern_exec.c`：PSFA_DUP2 调用内核 dup2；PSFA_INHERIT 则显式清除 FP_CLOEXEC。
- `bsd/kern/kern_descrip.c`：dup2 的 old == new 分支直接返回，不改 FP_CLOEXEC。

修复在 dup2 后追加 `posix_spawn_file_actions_addinherit_np(&act, 3)` 并检查其返回值，保留父端 CLOEXEC 和原清理逻辑。该 API 在 Apple 对应源码已有实现。

另外 `cmd_wait_for_exit` 现在在 EINTR 后继续等待实际退出；保持原始状态 ABI。原测试替身错误地返回 WEXITSTATUS，现改为提取真实生产等待函数。

## 回归测试

macOS 原生夹具仍实际 spawn 自己。主动控制管道读端=3、写端=3、两端都不是 3；模拟 XNU 8792 同号 dup2 不改变标志的行为，避免 runner 新系统语义掩盖旧系统缺陷。覆盖 3.0.12、3.0.13、旧版 3.0.4、继承动作失败、权限未获得、spawn 失败、读写及 waitpid EINTR、EOF、错误字节、exit(1)=256 和信号退出。

测试额外移除生产继承动作并重新编译，要求真实子进程用例断言失败，以证明测试能抓到此次回归。Windows 平台会跳过原生夹具；云端执行结果另记。

## 适用范围

这处修复有明确源码证据，能解释一条 App 错误 256 路径。尚未证明用户设备当次管道就是 fd 3，也未证明随后重启由此引发。插件管理器直接执行 sbreload 不经过此 App 握手，因此不能将安装插件后等待较久、二次注销或 watchdog 一并宣称已解决。

暂不改变子进程 persona / 凭据策略；临时 root 与父进程恢复的潜在竞态仍是待证假设。没有恢复旧 strcmp 比较、吞掉非零退出状态或修改 watchdog 阈值。
