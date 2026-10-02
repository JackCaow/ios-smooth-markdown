# 0.3.5 排版与可选语法修复

## 变更

- 新增 opt-in `HighlightPlugin`、`SuperscriptPlugin`、`SubscriptPlugin`；默认 Core/GFM 与 built-in registry 不变。
- 同一公开样式表控制高亮、上下标和新增 `smallStyle`；显式自定义插件 builder 保持优先，包括相邻 keycap 与选择投影。
- 启用 HTML 时支持完整的同一行、段落和列表内折叠块，并按宿主宽度换行；HTML code 恢复保留原始 source/range，保护代码内的字面标签与反引号。
- 动态内联折叠块使用 SwiftUI 展开状态，不提供跨其动态正文的连续原生选区。内部整体 atom Copy 保留其源码；原独立折叠块保持展开感知的原生选择。

Rust、静态 XCFramework 与外部依赖列表均未变。公开符号仅新增三个插件和 `smallStyle`；既有符号与声明保持不变。

## 验收记录

候选版本的独立插件源码 review 未发现阻断。2026-10-02，UIKit 最终 11 项全部通过：冻结生产源码的同批测试中插件 6 项、HTML 4 项通过；剩余 1 项纠正测试对普通 Copy fallback 与段首空格的期待后单独运行通过。该重跑没有修改生产源码。最终证据为 10+1，未宣称一次批次全绿。

生产源码摘要 SHA256：`30b90b32301e58f0163a44b8b537768c971a957c7ebf1b83a5e73b5da7c4c343`。公开 API 仅增加 28 个符号，无既有符号删除或声明变化。

消费端聊天列表截图验收在独立候选 checkout 上运行，记录 original SHA、dirty diff/source hash 与新增文件 manifest，并在测试后还原。发布前还需完成消费端 gate 与公共 CI。

安装方式为 SwiftPM Exact Version `0.3.5` 或 `pod 'SmoothMarkdown', '~> 0.3.5'`。发布完成记录及公共依赖的消费端验收另行补充。
