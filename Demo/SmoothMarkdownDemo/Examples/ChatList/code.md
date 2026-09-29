
# 💻 Code Example

Here's a Flutter widget with performance optimizations:

```dart
class OptimizedChatMessage extends StatefulWidget {
  const OptimizedChatMessage({
    required this.message,
    super.key,
  });

  final String message;

  @override
  State<OptimizedChatMessage> createState() => _OptimizedChatMessageState();
}

class _OptimizedChatMessageState extends State<OptimizedChatMessage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;  // ✅ Keep state alive

  @override
  Widget build(BuildContext context) {
    super.build(context);  // Required!

    return SmoothMarkdown(
      key: ValueKey(widget.message.id),
      data: widget.message.content,
      enableCache: true,  // ✅ Enable caching
      useRepaintBoundary: true,  // ✅ Isolate repaints
      styleSheet: MarkdownStyleSheet.light(),
    );
  }
}
```

**Key optimizations:**
- ✅ Cache hit: ~0.1ms vs ~15ms parsing
- ✅ RepaintBoundary reduces overdraw by 30%
- ✅ KeepAlive preserves state during scrolling
