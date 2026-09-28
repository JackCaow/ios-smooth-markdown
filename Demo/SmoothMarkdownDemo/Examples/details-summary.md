
# Details & Summary 折叠块

Details 元素提供了可折叠的内容区域，非常适合隐藏详细信息或额外内容。

## 基础示例

<details>
<summary>点击展开/折叠</summary>
这是隐藏的内容，只有当用户点击摘要时才会显示。
</details>

## 默认展开

使用 `open` 属性可以让折叠块默认展开：

<details open>
<summary>默认展开的内容</summary>
这个折叠块默认是展开状态。
</details>

## 包含列表

<details>
<summary>查看功能列表</summary>

支持的功能：
- 折叠/展开动画
- 自定义样式
- 嵌套内容支持
- 响应式布局
</details>

## 包含代码块

<details>
<summary>查看代码示例</summary>

```dart
void main() {
  print('Details 块中的代码');
  final list = [1, 2, 3, 4, 5];
  print(list);
}
```
</details>

## 嵌套折叠块

<details>
<summary>外层折叠块</summary>

这是外层内容。

<details>
<summary>内层折叠块</summary>
这是内层嵌套的内容。
</details>

外层内容的其他部分。
</details>

## FAQ 示例

<details>
<summary>Q: 如何使用 Flutter Smooth Markdown？</summary>

A: 只需在你的 Flutter 项目中添加依赖，然后使用 `SmoothMarkdown` widget：

```dart
SmoothMarkdown(
  data: '# Hello World',
)
```
</details>

<details>
<summary>Q: 支持哪些 Markdown 语法？</summary>

A: 支持 CommonMark 标准语法，以及 GFM 扩展（表格、任务列表等）。
</details>

<details>
<summary>Q: 可以自定义主题吗？</summary>

A: 当然！使用 `MarkdownStyleSheet` 可以完全自定义所有元素的样式。
</details>

## 包含表格

<details>
<summary>查看数据表格</summary>

| 特性 | 支持 | 说明 |
|------|------|------|
| 折叠 | ✅ | 点击展开/收起 |
| 嵌套 | ✅ | 支持多层嵌套 |
| 样式 | ✅ | 可自定义 |
| 动画 | ✅ | 平滑过渡 |
</details>

## 包含引用

<details>
<summary>查看引用内容</summary>

> Details 和 Summary 元素是 HTML5 的原生元素，
> 提供了一种语义化的方式来创建可折叠的内容区域。
>
> 在 Markdown 中使用它们可以让文档更加清晰易读。
</details>

---

**提示**: Details 块非常适合用于：
- FAQ 页面
- 文档中的可选详细信息
- 长列表或大量内容的折叠
- 教程中的提示和解答
