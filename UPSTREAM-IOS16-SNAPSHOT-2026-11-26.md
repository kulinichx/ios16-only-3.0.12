# iOS 16 官方快照补丁：第二批

用户要求第一批构建成功后先不下载，继续完成剩余工作。本批继续评估建议中的快照适配，不扩展到 killall 或其他审查分支补丁。

## 第一批已完成

- 两个提交：`6f31c65`（logd_helper 精确避让）、`05ed78f5d26b6335c0c5e34da07f4257155ffe01`（spawn 内存参数恢复）。
- GitHub Actions：`45760311979`，完整构建、原生测试、TIPA 校验和上传成功。
- 构建地址：https://github.com/kulinichx/ios16-only-3.0.12/actions/runs/45760311979。
- 按用户要求没有下载该构建安装包。

## 本批范围

唯一生产文件：`BaseBin/roothidehooks/src/springboard.x`。

- 来源是官方 `26d95449d25d176a31ae7bc475fd85ee3403498c` 的快照保存思路，恢复本项目 `be6cb36a` 已有的 RootHide 适配。
- 由宽泛的 fcntl hook 切换到 `XBApplicationSnapshotManifestImpl` 的 `_imageAccessQueue_saveData:forSnapshot:`。
- 使用实际加载的 roothidehooks，保留随机 jbroot 快照目录、Apple-internal 标识例外及目标路径范围判断。
- 原应用隐藏、打开请求 hook 和低电量/耗电记录服务启动接线保持原样。
- 版本仍为 3.0.12 / RootHide 30。第一批两项补丁继续保留。

## 验证和边界

- 42 文件基线保留原摘要，第三项已批准例外单独记录新摘要和上游来源。
- 存储原快照前缀，用其与当前未变的后半部分拼回原版进行摘要验证，继续保护应用 hook；同时对完整新文件做已批准摘要检查。
- 新增 macOS Foundation 夹具，执行真实生产快照方法；私有对象由替身提供，但文件写入发生在临时目录。覆盖普通越狱应用、Apple 系统应用、Apple-internal 例外、空输入、外部目录、相似目录名、路径回退、缺失目标和写入失败。
- Windows 全量测试：209 项，191 通过，0 失败，18 跳过。其中快照原生夹具在 Windows 跳过，等待本候选 macOS 执行。
- `git diff --check` 通过。快照生产实现（去掉既有服务接线并规范化换行后）与 `be6cb36a` 相同，没有新增快照算法或额外修复。

Foundation 测试不能证明 iOS 16 的系统私有方法在每个版本上存在、必然调用，或实际应用切换器表现正确。仍需 iOS 16 实机检查快照生成与更新、锁屏解锁、注销、普通系统应用，以及后台低电量/耗电记录。

本节记录提交前状态。后续原生构建及交付结果另行追加，安装包仍按用户要求不下载。
