# 0.3.3 非滚动 reader 首帧布局修复

本版本修复 `SmoothMarkdownView(scrollable: false)` 的首次挂载高度。此前该路径无条件使用 `LazyVStack`，宿主首次布局会以尚未完成测量的 block 高度放置后续内容。现在非滚动 reader 使用 `VStack`；滚动 reader 继续使用 `LazyVStack`。公开 API、parser、缓存和宿主刷新时序不变。

## 验证

2026-10-02，DimRemote 真实 timeline 的 `testMarkdownFirstPresentationKeepsFollowingChipsOutsideText` 对照结果：

- 公开 0.3.2：首次 mounted cell 高度 `2166pt`，完整测量 `2220pt`，少 `54pt`；下一帧才恢复。
- 仅将库布局改为 eager：首次 mounted cell 与完整测量均为 `2220pt`，连续 30 帧一致，测试通过。
- 对照没有修改宿主缓存或刷新延迟。正式修复仅对 `scrollable: false` 启用 eager 布局。

库的 iOS Simulator generic build（arm64 / x86_64）及公开 Swift API baseline 校验通过。使用上述真实宿主几何测试作为此布局修复的回归证据；此次没有 parser 或 Rust 变更。

## 发布状态

0.3.3 正在进行独立复审，尚未 merge、创建 tag 或发布公共包。发布后安装入口为：

```swift
.package(url: "https://github.com/JackCaow/ios-smooth-markdown", from: "0.3.3")
```

```ruby
pod 'SmoothMarkdown', '~> 0.3.3'
```

公共 Specs 安装及独立 consumer 编译应在发布后另行验收。
