# 0.3.4 非滚动 reader 内在高度修复

0.3.3 将非滚动 reader 改为 eager `VStack`，修复首次挂载及复用布局时延后的 block 测量。最终消费端回归发现，该 stack 在有限高度提议下可以压缩正文：同一长列表在宽度 `300pt`、高度 `2000pt` 时测量为 `94.333pt`，在高度 `1pt` 时仅返回 `19.333pt`。旧 lazy 路径保留了完整内在高度。

本次只在非滚动 eager 分支添加 `.fixedSize(horizontal: false, vertical: true)`：横向仍接受宿主宽度以正确换行，纵向使用完整内在高度。滚动分支、公开 API、宿主缓存、parser 与 Rust 不变。

## 发布 gate

2026-10-02，候选消费端的原压缩尺寸断言和三个首次挂载及复用布局场景合计 4 项、0 失败；其余 19 项已在公开 0.3.3 上通过。最终公开版本消费端验收由发布负责人完成。

库内新增公开 reader 行为回归：分别以全新 `UIHostingController` 首次测量宽度 `300pt`、高度 `1pt` 与 `2000pt`，验证普通正文、`2.`、`14.`、`100.`、bullet 和 task 的完整高度相等，且内容确实换行。该项实际 iOS Simulator runtime 通过，公开 API baseline 及 UIKit build-for-testing 通过。

发布 PR 进入独立复审；0.3.4 尚未创建 tag 或发布 Trunk。

0.3.4 发布后使用 SwiftPM `from: "0.3.4"` 或 CocoaPods `pod 'SmoothMarkdown', '~> 0.3.4'`；公开 registry 安装验收在发布后完成。
