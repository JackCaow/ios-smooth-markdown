use crate::ast::{Kind, Node};

pub fn escape(value: &str) -> String {
    let mut out = String::new();
    for c in value.chars() { match c { '&' => out.push_str("&amp;"), '<' => out.push_str("&lt;"),
        '>' => out.push_str("&gt;"), '"' => out.push_str("&quot;"), '\0' => out.push('\u{fffd}'), _ => out.push(c) } }
    out
}
fn destination(value: &str) -> String {
    let mut out = String::new();
    for byte in value.as_bytes() {
        if byte.is_ascii_alphanumeric() || b"-._~:/?#@!$&'()*+,;=%".contains(byte) { out.push(*byte as char); }
        else { out.push_str(&format!("%{byte:02X}")); }
    }
    escape(&out)
}
pub fn plain_text(node: &Node) -> String {
    if let Some(literal) = &node.literal { return literal.clone(); }
    match node.kind {
        Kind::Text | Kind::InlineCode => crate::inline::decode_text(&node.source),
        Kind::SoftBreak | Kind::HardBreak => "\n".into(),
        _ => node.children.iter().map(plain_text).collect(),
    }
}
pub fn render(node: &Node) -> String { render_inner(node, false) }
fn children(node: &Node) -> String { node.children.iter().map(render).collect() }
fn render_inner(node: &Node, tight: bool) -> String {
    let title = node.title.as_ref().map(|title| format!(" title=\"{}\"", escape(title))).unwrap_or_default();
    match node.kind {
        Kind::Document | Kind::TableRow | Kind::TableCell => children(node),
        Kind::Text => escape(&node.literal.clone().unwrap_or_else(|| crate::inline::decode_text(&node.source))),
        Kind::Paragraph => { let text = children(node); if tight { text } else { format!("<p>{text}</p>\n") } },
        Kind::Heading => format!("<h{}>{}</h{}>\n", node.level, children(node), node.level),
        Kind::FencedCode | Kind::IndentedCode => {
            let language = node.info.split_whitespace().next().unwrap_or("");
            let attr = if node.kind == Kind::FencedCode && !language.is_empty() { format!(" class=\"language-{}\"", escape(language)) } else { String::new() };
            format!("<pre><code{attr}>{}</code></pre>\n", escape(node.literal.as_deref().unwrap_or("")))
        },
        Kind::ThematicBreak => "<hr />\n".into(),
        Kind::Strong => format!("<strong>{}</strong>", children(node)),
        Kind::Emphasis => format!("<em>{}</em>", children(node)),
        Kind::Strikethrough => format!("<del>{}</del>", children(node)),
        Kind::InlineCode => format!("<code>{}</code>", escape(node.literal.as_deref().unwrap_or(&node.source))),
        Kind::SoftBreak => "\n".into(), Kind::HardBreak => "<br />\n".into(),
        Kind::InlineHtml => node.literal.clone().unwrap_or_else(|| node.source.clone()),
        Kind::HtmlBlock => { let text = node.literal.as_deref().unwrap_or(&node.source); format!("{text}{}", if text.ends_with('\n') { "" } else { "\n" }) },
        Kind::Link => format!("<a href=\"{}\"{title}>{}</a>", destination(&node.destination), children(node)),
        Kind::Image => format!("<img src=\"{}\" alt=\"{}\"{title} />", destination(&node.destination), escape(&plain_text(node))),
        Kind::ReferenceDefinition => String::new(),
        Kind::BlockQuote => format!("<blockquote>\n{}</blockquote>\n", children(node)),
        Kind::List => {
            let tag = if node.ordered { "ol" } else { "ul" };
            let start = match node.list_start { Some(start) if node.ordered && start != 1 => format!(" start=\"{start}\""), _ => String::new() };
            let body: String = node.children.iter().map(|n| render_inner(n, node.tight.unwrap_or(true))).collect();
            format!("<{tag}{start}>\n{body}</{tag}>\n")
        },
        Kind::ListItem => {
            if node.children.is_empty() { return "<li></li>\n".into(); }
            let checkbox = node.checked.map(|checked| format!("<input {}disabled=\"\" type=\"checkbox\"> ", if checked { "checked=\"\" " } else { "" })).unwrap_or_default();
            if !tight {
                let text = children(node);
                let body = if !checkbox.is_empty() && text.starts_with("<p>") { format!("<p>{checkbox}{}", &text[3..]) } else { format!("{checkbox}{text}") };
                return format!("<li>\n{body}</li>\n");
            }
            // Both public host AST facades are supported: Kotlin keeps paragraph
            // nodes in tight items; Swift's legacy AST can store inline children.
            let mut body = String::new();
            if node.children.first().is_some_and(|n| is_block(n) && n.kind != Kind::Paragraph) { body.push('\n'); }
            for (index, child) in node.children.iter().enumerate() {
                if index > 0 && is_block(child) && !body.ends_with('\n') { body.push('\n'); }
                body.push_str(&render_inner(child, child.kind == Kind::Paragraph));
            }
            if node.children.last().is_some_and(|n| is_block(n) && n.kind != Kind::Paragraph) && !body.ends_with('\n') { body.push('\n'); }
            format!("<li>{checkbox}{body}</li>\n")
        },
        Kind::Table => {
            let Some(header) = node.children.first() else { return String::new(); };
            let row = |row: &Node, header: bool| {
                let tag = if header { "th" } else { "td" };
                let cells: String = row.children.iter().enumerate().map(|(index, cell)| {
                    let alignment = node.alignments.get(index).and_then(|a| a.as_ref()).map(|a| format!(" align=\"{}\"", escape(a))).unwrap_or_default();
                    format!("<{tag}{alignment}>{}</{tag}>\n", children(cell))
                }).collect();
                format!("<tr>\n{cells}</tr>\n")
            };
            let body: String = node.children.iter().skip(1).map(|n| row(n, false)).collect();
            format!("<table>\n<thead>\n{}</thead>\n{}</table>\n", row(header, true), if body.is_empty() { body } else { format!("<tbody>\n{body}</tbody>\n") })
        },
        Kind::InlineMath | Kind::FootnoteReference | Kind::Raw => escape(&node.source),
        Kind::BlockMath | Kind::FootnoteDefinition => format!("<p>{}</p>\n", escape(node.source.trim_matches(['\r', '\n']))),
    }
}
fn is_block(node: &Node) -> bool { matches!(node.kind, Kind::Paragraph | Kind::Heading | Kind::FencedCode | Kind::IndentedCode | Kind::ThematicBreak | Kind::BlockQuote | Kind::List | Kind::HtmlBlock | Kind::Table | Kind::Raw) }

/// GFM tagfilter applies to raw HTML; generated tags never use these names.
pub fn render_gfm(node: &Node) -> String {
    let html = render(node);
    let blocked = ["title", "textarea", "style", "xmp", "iframe", "noembed", "noframes", "script", "plaintext"];
    let mut result = String::new();
    let mut cursor = 0;
    while let Some(relative) = html[cursor..].find('<') {
        let position = cursor + relative;
        result.push_str(&html[cursor..position]);
        let rest = html[position + 1..].strip_prefix('/').unwrap_or(&html[position + 1..]);
        let length = rest.bytes().take_while(u8::is_ascii_alphabetic).count();
        let forbidden = blocked.iter().any(|tag| rest[..length].eq_ignore_ascii_case(tag))
            && rest.as_bytes().get(length).is_some_and(|c| c.is_ascii_whitespace() || *c == b'>' || *c == b'/');
        result.push_str(if forbidden { "&lt;" } else { "<" });
        cursor = position + 1;
    }
    result.push_str(&html[cursor..]); result
}
