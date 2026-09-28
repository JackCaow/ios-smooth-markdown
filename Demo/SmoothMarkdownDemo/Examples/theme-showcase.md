
# 主题展示

点击右上角的 **调色板图标** 🎨 来切换不同的主题！

## 可用主题

### 默认主题
- **默认亮色** - 简洁清爽的亮色主题
- **默认暗色** - 护眼舒适的暗色主题

### GitHub 风格
- **GitHub** - 经典的 GitHub 亮色主题
- **GitHub Dark** - GitHub 暗色主题

### VS Code 风格
- **VS Code** - VS Code 编辑器亮色主题
- **VS Code Dark** - VS Code 编辑器暗色主题

## 主题特性

每个主题都精心设计了以下元素：

1. **文本样式** - 优雅的字体和间距
2. **代码高亮** - 专业的代码块样式
3. **链接颜色** - [点击链接](https://flutter.dev) 查看效果
4. **引用样式** - 查看下方示例

> 这是一个引用块
> 不同主题下颜色和样式会有所不同

## 代码示例

```dart
// 不同主题下的代码块效果
void main() {
  final message = 'Hello, Flutter!';
  print(message);
}
```

## 自定义主题

你也可以创建自己的主题：

```dart
final customTheme = MarkdownStyleSheet(
  h1Style: TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: Colors.purple,
  ),
  codeBlockDecoration: BoxDecoration(
    color: Colors.grey[100],
    borderRadius: BorderRadius.circular(8),
  ),
);
```

**试试切换主题，感受不同的视觉体验吧！** ✨
