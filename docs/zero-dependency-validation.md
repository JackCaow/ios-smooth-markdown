# 零运行时依赖验证

本页记录 2026-09-30 在 macOS / Xcode 26.0.1 / CocoaPods 1.16.2 上对联合工作树的实际验证。Swift Package 的 `dependencies` 为空；CocoaPods consumer 的 Podfile 只声明本地 `SmoothMarkdown`。

## 语义与包内测试

- Native AST 与正式 HTML 导出对照 CommonMark 0.31.2 官方 652 例和 GFM 扩展 24 例，完整 HTML 均通过。
- 联合版本的 Swift 包测试共 532 项，0 失败、1 项跳过（联合验收）。这些结果验证解析语义与包内行为。

## 独立 CocoaPods consumer

示例工程位于 `/tmp/smoothmarkdown-pod-consumer`。`PodConsumer/PodConsumerApp.swift` 仅导入 `SwiftUI` 和 `SmoothMarkdown`，并在同一 App 中实例化 `SmoothMarkdownView`、`StreamMarkdownView`、`SmoothMarkdownEditor`，注册一个接受 `Heading` 的自定义 `MarkdownWidgetBuilder`。Podfile 的唯一 pod 声明为：

```ruby
pod 'SmoothMarkdown', :path => '/Users/cver/workspace/ios-smooth-markdown-native-ast'
```

实际执行：

```sh
cd /tmp/smoothmarkdown-pod-consumer
xcodegen generate
pod install
xcodebuild -workspace SmoothMarkdownPodConsumer.xcworkspace \
  -scheme SmoothMarkdownPodConsumer -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/smoothmarkdown-pod-consumer-derived \
  CODE_SIGNING_ALLOWED=NO build
```

`pod install` 成功。`/tmp/smoothmarkdown-pod-consumer/Podfile.lock` 的 `PODS` 列表只有 `SmoothMarkdown (0.2.0)`，没有传递 pod。consumer 的 iOS Simulator Debug 构建输出 `** BUILD SUCCEEDED **`；日志在 `/tmp/smoothmarkdown-pod-consumer-build.log`，构建产物在 `/tmp/smoothmarkdown-pod-consumer-derived`。这验证了 reader、stream、editor 和公开 `Markup` builder 在真实 CocoaPods consumer 中可编译。

## Podspec lint

完整 lint 未使用 `--quick`、`--skip-tests` 或 `--skip-import-validation`。最终通过的命令：

```sh
cd /Users/cver/workspace/ios-smooth-markdown-native-ast
pod lib lint SmoothMarkdown.podspec --allow-warnings \
  --validation-dir=/tmp/smoothmarkdown-pod-lint-validation-2
```

结果为 `SmoothMarkdown passed validation.`，日志位于 `/tmp/smoothmarkdown-pod-lint-retry.log`。lint 期间有 `SVGWebKitView.swift` 未使用局部变量及 App Intents metadata 跳过的警告。

首次有效 lint 使用默认 validation 目录时，Xcode 在 DerivedData 的 `build.db` 报 `disk I/O error`，随后提示无法打开 `SmoothMarkdown_const_extract_protocols.json`，没有报告源码编译错误；日志为 `/tmp/smoothmarkdown-pod-lint.log`。当时数据卷仍有约 27 GiB 可用。改用上面的独立 validation 目录重跑后通过。CocoaPods 1.16.2 不接受 `pod lib lint --local`，因此复现命令不包含该参数。

## 模拟器 UI 复核

完整 Demo 截图套件 9 项通过，共导出 220 张 PNG，覆盖基础 Markdown、功能页、编辑器、主题、聊天、12 个会话详情、40 个 Mermaid 图及动态状态。截图与复核记录位于桌面 `ios-smooth-markdown-zero-dependency-review` 文件夹。

截图发现并修复了嵌套折叠块、无扩展名 SVG 识别与缩放、发出消息表格表头对比度；折叠块和表头均有定向通过截图。公式复核覆盖括号、负间距、暗色透明背景及 cases 花括号。

原始图片 fixture 中的 Flutter Logo 地址返回 404，另一处地址是预设失败样例。部分宽幅 Mermaid 图初始视窗显示不全，需双轴平移或缩放；这仍是现有布局限制。

验证使用模拟器；CocoaPods Trunk 尚未发布，需要完成账号验证。
