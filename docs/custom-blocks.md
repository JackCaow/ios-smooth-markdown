# Custom Blocks in Blocks mode

`SmoothMarkdownEditor` can delegate a top-level block to a host view and editor. The host must explicitly recognize it with `customBlockMatcher`; an absent matcher leaves every row on the built-in path. This is intended for raw blocks such as app-specific HTML directives. The matcher also receives other semantic block kinds when an app deliberately wants to override one.

```swift
SmoothMarkdownEditor(
    controller: controller,
    customBlockMatcher: { block in
        if case .raw = block.kind { return block.source.hasPrefix("<callout>") }
        return false
    },
    customBlockBuilder: { context in
        AnyView(Button(context.plainText) { context.edit() })
    },
    customBlockEditorBuilder: { context in
        AnyView(VStack {
            Button("Replace") {
                _ = context.replaceMarkdown("<callout>Updated</callout>\n")
            }
            Button("Done") { context.finishEditing() }
            Button("Delete", role: .destructive) { _ = context.delete() }
        })
    }
)
```

`replaceMarkdown` and `delete` return `false` if the document changed since the context was built. Replacement accepts exactly one top-level block and refuses an edit that would merge or split adjacent blocks. Both operations enter the controller's normal Undo history and preserve untouched neighboring source. `finishEditing` only closes the host editor.

This API delegates **Blocks mode** rows. Source, preview, and split render through their existing paths. The native codec currently treats many custom directives as `.raw`; it does not expose Flutter's full parser-plugin block tree or stable IDs across reparsing.
