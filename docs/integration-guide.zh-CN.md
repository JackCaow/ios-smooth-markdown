# iOS Smooth Markdown 接入手册

适用于在自己的 iOS 应用中接入 Markdown 阅读、流式回复、编辑器和样式定制。UI 使用 SwiftUI；独立 Core 提供解析和 HTML 导出。

## 1 选择安装版本

发布版本：`0.4.0`。

| 接入目标 | 使用方式 |
| --- | --- |
| 稳定版本 | SwiftPM Exact Version `0.4.0`，或公共 CocoaPods `0.4.0` |
| 团队与 CI 固定依赖 | 提交 `Package.resolved` 或 `Podfile.lock` |

`0.4.0` 修复图表与周围文字重叠、图表边框裁切、连线及标签避让，新增基础 Git 图和思维导图。`MermaidKind` 新增枚举项，穷尽 switch 的接入方需要增加对应分支。它包含原有自有 Rust 解析、后台流式调度与非滚动阅读器完整高度修复，并新增可选高亮、上下标语法、小字样式和列表内折叠块。既有初始化接口保持原签名；未支持的 sequence 语句现在整图回退源码，不再静默丢弃。

项目地址：[ios-smooth-markdown](https://github.com/JackCaow/ios-smooth-markdown)。

## 2 安装已发布版本

要求 iOS 17+、Swift 5.9+。库没有外部 package 或第三方解析、图片、SVG、公式依赖；使用 Apple 系统框架，并随包提供自有 Rust 静态 XCFramework。应用开发者不需要安装 Rust 或 Cargo。

### Swift Package Manager

在 Xcode 选择 **File → Add Package Dependencies**：

1. 地址填 `https://github.com/JackCaow/ios-smooth-markdown`。
2. 需要确定版本时选择 Exact Version `0.4.0`。
3. 将 **SmoothMarkdown** product 加到应用 target。
4. 源码中 `import SmoothMarkdown`。

Swift package 的依赖声明：

```swift
.package(url: "https://github.com/JackCaow/ios-smooth-markdown", exact: "0.4.0")
```

应用 target 的 dependencies：

```swift
.product(name: "SmoothMarkdown", package: "ios-smooth-markdown")
```

### CocoaPods

在已有 Podfile 的应用 target 内添加：

```ruby
platform :ios, '17.0'

target 'YourApp' do
  pod 'SmoothMarkdown', '~> 0.4.0'
end
```

执行 `pod install --repo-update`，之后打开应用的 `.xcworkspace`。默认安装 UI 和它的 Core 依赖，模块名同样是 `SmoothMarkdown`。不要在同一应用 target 内同时安装 SwiftPM 和 CocoaPods 的这份库，以免重复链接。

本机发布验收时 CocoaPods CDN 返回 `403`，通过官方 Git Specs 源完成了安装与编译。遇到同类访问问题，可在 Podfile 顶部添加 `source 'https://github.com/CocoaPods/Specs.git'`；该源是 CocoaPods 官方公共索引，库依赖仍只写 Pod 名，不需要 `:git` 或 `:path`。

## 3 最小阅读页面

```swift
import SwiftUI
import SmoothMarkdown

struct MarkdownPage: View {
    let source: String

    var body: some View {
        SmoothMarkdownView(markdown: source, selectable: true)
    }
}
```

默认由 reader 自己纵向滚动。聊天气泡、List row 或外层 ScrollView 内设置 `scrollable: false`，让外层负责滚动。增强标题、引用和代码控制需显式设置 `useEnhancedComponents: true`。

需要集中管理行为与事件时使用分组 API：

```swift
import SwiftUI
import SmoothMarkdown

struct ChatMarkdown: View {
    let source: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        SmoothMarkdownView(
            markdown: source,
            renderOptions: MarkdownRenderOptions(
                useEnhancedComponents: true,
                scrollable: false
            ),
            selectionOptions: MarkdownSelectionOptions(mode: .document),
            events: MarkdownEvents(onLinkTap: { url in
                openURL(url)
            })
        )
    }
}
```

分组 API 的图片事件携带原始 source、alt 和 title。旧扁平 API 仍支持 `onLinkTap`（URL）、`onTapLink`（String）等入口；两种 link alias 同时提供时都会调用，业务通常只需选择一种。

## 4 统一样式和 Design Token

在业务主题层定义一份样式，传给 reader 和 stream：

```swift
import SwiftUI
import SmoothMarkdown

func appMarkdownStyle(dark: Bool) -> MarkdownStyleSheet {
    var style = MarkdownStyleSheet.github(dark: dark)
    style.blockSpacing = 12
    style.linkColor = .indigo
    style.designTokens.typography.paragraph = MarkdownFontToken(size: 16)
    style.designTokens.typography.paragraphLineHeight = 1.55
    style.designTokens.heading.accentColor = .indigo
    style.designTokens.details.cornerRadius = 12
    return style
}
```

调用时传 `styleSheet: appMarkdownStyle(dark: isDark)`。自定义字体用 `MarkdownFontToken(fontName:size:weight:monospaced:)` 提供明确字体指标，并在应用中注册字体文件。正文与六级标题通过 `designTokens.typography` 集中配置；显式指标用于普通 reader 和原生可选择文本的一致排版，并支持 Dynamic Type。

| 配置 | 控制范围 |
| --- | --- |
| `designTokens.document` | 文档语义颜色 |
| `designTokens.typography` | 正文、六级标题字体和行高比例 |
| `heading`、`quote`、`code`、`link` | 增强组件装饰和代码控件 |
| `details`、`keyboard`、`math` | 折叠区、键帽和公式 |
| `plugins`、`mermaid` | 内置插件面板和图表基础样式 |
| `MarkdownEditorTheme` | 编辑器工具栏、源码及编辑控件 |

显式 token 优先于旧样式字段；可选 token 设为 `nil` 恢复回退。旧 SwiftUI `Font` 不提供 UIKit 字体指标，需要两种渲染路径一致时采用 `MarkdownFontToken`。导航栏、输入框和自定义 builder UI 由宿主应用管理。完整字段和优先级见 [样式手册](styling.md)。

## 5 流式回复

```swift
import SwiftUI
import SmoothMarkdown

struct StreamingReply: View {
    let chunks: AsyncStream<String>
    let messageID: String
    let saveFinal: (String) -> Void

    var body: some View {
        StreamMarkdownView(
            chunks: chunks,
            streamID: messageID,
            throttleMillis: 50,
            onError: { error in
                print("流式错误：\(error)")
            },
            onComplete: saveFinal,
            scrollable: false
        )
    }
}
```

输入为 `AsyncSequence<String>` 的**新增片段**，例如 `"Hello "`、`"**world**"`，库累积完整 Markdown。不要把每次完整快照作为 chunk，否则会重复累积。`AsyncThrowingStream` 也可接入同一个泛型入口；正常结束调用完成回调，抛错走错误回调，取消不算成功完成。

在 ViewModel 中创建和持有稳定的 stream；不要在每次 `body` 求值时创建。切换或重试一条消息时更新 `streamID`，使用新的消息或尝试标识，立即重置旧内容。生命周期结束时，宿主也应停止其网络请求和生产任务；可将生产者清理接到 continuation 的 `onTermination`。

固定最新提交接入时，普通 Markdown 的原生解析和解码在后台串行队列处理，待处理的完整前缀会合并，最终前缀不会丢失。Markup 适配和发布留在 MainActor，`onComplete` 等待最终解析结果发布，完成后释放 worker 原生会话缓存。自定义插件、含美元符号的公式路径、脚注、HTML 和 details 使用兼容解析路径；不能假设所有内容都走后台增量路径。

聊天列表需要由业务持有完整消息源码、流式状态和消息 ID；完成后可使用静态 `SmoothMarkdownView` 渲染持久化内容。库负责渲染，不负责请求 AI 接口、存储会话或管理 API Key。

## 6 图片和中文标签

默认使用系统网络和图像 API，支持常见位图及受支持的 SVG。优先使用完整 HTTPS 图片地址。需要认证图片时配置当前账号的资源参数：

```swift
import SwiftUI
import SmoothMarkdown

struct AuthenticatedArticle: View {
    let source: String
    let imageToken: String

    private var chineseStrings: MarkdownStrings {
        var strings = MarkdownStrings()
        strings.copy = "复制"
        strings.copied = "已复制"
        return strings
    }

    var body: some View {
        SmoothMarkdownView(
            markdown: source,
            renderOptions: MarkdownRenderOptions(useEnhancedComponents: true),
            events: MarkdownEvents(onImageTap: { event in
                print("图片：\(event.source)，说明：\(event.alt ?? "")")
            }),
            resourceOptions: MarkdownResourceOptions(
                headers: ["Authorization": "Bearer \(imageToken)"]
            ),
            strings: chineseStrings
        )
    }
}
```

headers 会作用于该资源配置处理的图片请求，只给受信任内容使用账号凭据；需要按域名选取认证头时实现 `MarkdownResourceLoader`。loader 异步返回编码后的 `Data`，遵守取消。缓存策略为 `.default`、`.reload` 和 `.noStore`；自定义 loader 自己也应遵守缓存策略。

`MarkdownStrings` 只改变库的控件及无障碍标签，不翻译文章。可在父 View 使用 `.environment(\.markdownResources, resources)`、`.environment(\.markdownStrings, strings)`，单个 reader 的显式参数覆盖环境值。

## 7 插件和自定义渲染

保持 registry 实例稳定，只启用业务需要的扩展。在 MainActor 上创建、注册和修改 registry：

```swift
import SwiftUI
import SmoothMarkdown

@MainActor
func makeArticlePlugins() throws -> ParserPluginRegistry {
    let plugins = ParserPluginRegistry()
    try plugins.register(MentionPlugin())
    try plugins.register(MermaidPlugin())
    return plugins
}
```

由 ViewModel 持有返回的 registry，将其传给 `SmoothMarkdownView(markdown: source, plugins: plugins)`。注册失败是可抛出的错误，由业务处理；不要每次 `body` 求值都重新创建。

`ParserPluginRegistry` 扩展语法；`BuilderRegistry` 替换已解析节点的 UI。分组 API 使用 `MarkdownBuilders(nodes: …, code: …, image: …)` 传替换组件，代码和图片 builder 返回 `AnyView`。自定义视图可能打断完整文档的连续选择，需要自行提供语义文本或相应交互。Mermaid 支持已实现的语法子集，不等同于完整 Mermaid.js。

### 可选排版扩展

注册 `HighlightPlugin()`、`SuperscriptPlugin()`、`SubscriptPlugin()` 可识别 `==高亮==`、`x^2^`、`H~2~O`；这些插件不在默认 registry 中。数字下标仅支持单词内部形式，普通 GFM 删除线保持原义。使用样式表的 `highlightStyle`、`superscriptStyle`、`subscriptStyle` 定制。

`enableHTML: true` 时支持 `<small>` 与段落、列表内的完整 `<details>`。`smallStyle` 配置小字；默认取当前配置字体的 80%。动态内联折叠块使用 SwiftUI 展开状态，因此不支持跨其动态正文的连续原生选区。代码中的 HTML 和扩展标记保留字面显示。

完整语法边界见 [插件说明](inline-formatting-plugins.md) 与 [HTML 说明](html-readable-content.md)。

## 8 编辑器

```swift
import SwiftUI
import SmoothMarkdown

struct MarkdownComposer: View {
    @StateObject private var controller = MarkdownEditorController(text: "# 草稿")

    var body: some View {
        SmoothMarkdownEditor(controller: controller, onSave: { source in
            print("保存：\(source)")
        })
    }
}
```

controller 默认 Source 模式，也支持 Preview、Split 和 Formatted/Blocks。要默认使用 Blocks，可在业务创建 controller 时设置 `controller.mode = .formatted`。controller 应与文档生命周期一致；Markdown 源码作为持久化内容。

编辑控件使用独立 `MarkdownEditorTheme`，显式传入 `editorTheme:` 或在父 View 使用 `.markdownEditorTheme(...)`。文件选择、分享和业务保存由宿主处理。iOS 编辑器不是 macOS product 的可用编辑入口。

## 9 只接入解析 Core

SwiftPM 只选择 **SmoothMarkdownCore** product：

```swift
.product(name: "SmoothMarkdownCore", package: "ios-smooth-markdown")
```

```swift
import SmoothMarkdownCore

let parser = MarkdownCoreParser()
let ast = parser.parse("# Hello")
let html = parser.renderHTML("**Hello**")
```

Core 使用 Foundation 和随包提供的静态 Rust 解析器，无 SwiftUI、UIKit 依赖。SwiftPM 也支持 macOS 14+ 的 Apple Silicon 和 Intel。

CocoaPods 只安装 Core：

```ruby
pod 'SmoothMarkdown/Core', '~> 0.4.0'
```

CocoaPods Core 的模块名是 `SmoothMarkdown`，代码应 `import SmoothMarkdown`；它与 SwiftPM 的独立 Core 模块导入名不同。

## 10 历史固定源码提交示例

新接入使用第 2 节的 `0.4.0` Exact Version，并提交锁文件。以下完整 SHA 是历史后台优化版本，仅用于说明 revision 安装方法；它不包含后续排版与扩展语法修复。SwiftPM：

```swift
.package(
    url: "https://github.com/JackCaow/ios-smooth-markdown",
    revision: "043093bc1f38beac6832ec37b448f0f27eb3c7bf"
)
```

Xcode 图形界面可将 Dependency Rule 设为 Commit 并填入同一完整 SHA。仍选择 `SmoothMarkdown` product，已包含所需静态 XCFramework，无需编译 Rust。

CocoaPods：

```ruby
pod 'SmoothMarkdown', :git => 'https://github.com/JackCaow/ios-smooth-markdown.git', :commit => '043093bc1f38beac6832ec37b448f0f27eb3c7bf'
```

安装后提交应用的 `Package.resolved` 或 `Podfile.lock`，让团队和 CI 使用相同 revision。不要同时保留旧 tag 的重复依赖声明。固定实现提交是源码锁定方式；当前 SwiftPM 接入使用 `0.4.0` tag，后续升级继续按业务流程固定版本。

## 11 常见问题和验收

| 现象 | 检查与处理 |
| --- | --- |
| `No such module SmoothMarkdown` | 检查 product 是否加到应用 target；Pods 工程打开 `.xcworkspace` |
| `pod 'SmoothMarkdown'` 找不到 | 使用 `0.3.1` 并执行 `pod install --repo-update`；CDN 访问失败时按第 2 节切换官方 Git Specs 源 |
| 找不到后台增量功能 | 升级到 `0.3.1`；也可按第 10 节固定 revision 接入 |
| 字体或行距在选择模式下不同 | 用明确的 `MarkdownFontToken` 和行高 token，不只修改旧 SwiftUI Font |
| 图片不显示 | 检查完整 HTTPS 地址、认证头、响应格式、ATS 策略和资源错误视图 |
| 聊天气泡高度或滚动冲突 | 外层负责滚动时 `scrollable: false`，检查父布局宽高约束 |
| 流式文字重复或混入旧回复 | 输入新增片段；保持 stream 稳定，切换回复更新 `streamID` |
| 完成回调不执行 | 检查 continuation 是否正常 finish；抛错和取消不算成功完成 |
| 自定义 builder 后选择不连续 | 自定义视图可能需要独立语义和选择实现，见公开契约 |
| 图表或格式化编辑不支持某语法 | 查看 [实现范围](reference.md)，unsupported 情况按文档回退 |

接入后至少在业务页面确认：标题/正文/代码、表格和图片正常；浅深色及 Dynamic Type 正确；聊天气泡没有双重纵向滚动；链接、复制、选择符合业务行为；流式最终文本与持久化源码一致；取消或切换回复不复活旧内容；完成和错误事件由宿主处理。

## 12 后续参考

- [公开配置契约](public-library-contract.md)
- [Design Token 和样式](styling.md)
- [API 和实现范围](reference.md)
- [自定义节点渲染](custom-blocks.md)
- [后台流式验收](../benchmarks/stream-background-2026-10-01.md)
- [CocoaPods 发布验收](cocoapods-release-0.3.1.md)
- [已发布版本](https://github.com/JackCaow/ios-smooth-markdown/releases)
