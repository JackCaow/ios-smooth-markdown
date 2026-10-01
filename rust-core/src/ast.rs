use std::collections::HashMap;

/// Stable wire IDs; append values rather than reordering them.
#[repr(u16)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Document = 0,
    Paragraph = 1,
    Heading = 2,
    FencedCode = 3,
    IndentedCode = 4,
    Table = 5,
    TableRow = 6,
    TableCell = 7,
    List = 8,
    ListItem = 9,
    BlockQuote = 10,
    ThematicBreak = 11,
    Text = 12,
    Strong = 13,
    Emphasis = 14,
    Strikethrough = 15,
    InlineCode = 16,
    InlineMath = 17,
    SoftBreak = 18,
    HardBreak = 19,
    InlineHtml = 20,
    BlockMath = 21,
    FootnoteReference = 22,
    FootnoteDefinition = 23,
    ReferenceDefinition = 24,
    Link = 25,
    Image = 26,
    HtmlBlock = 27,
    Raw = 28,
    Custom = 29,
    TableHead = 30,
    TableBody = 31,
    TaskMarker = 32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Span {
    pub start: u32,
    pub len: u32,
}
impl Span {
    pub fn end(self) -> u32 {
        self.start + self.len
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Node {
    pub kind: Kind,
    pub span: Span,
    pub source: String,
    pub children: Vec<Node>,
    pub level: u32,
    pub info: String,
    pub destination: String,
    pub title: Option<String>,
    pub ordered: bool,
    pub checked: Option<bool>,
    pub tight: Option<bool>,
    pub list_start: Option<u32>,
    pub literal: Option<String>,
    pub alignments: Vec<Option<String>>,
    pub label: String,
    pub html_header: bool,
    pub html_number: Option<i64>,
}
impl Node {
    pub fn new(kind: Kind, source: impl Into<String>, start: u32, len: u32) -> Self {
        Self {
            kind,
            span: Span { start, len },
            source: source.into(),
            children: Vec::new(),
            level: 0,
            info: String::new(),
            destination: String::new(),
            title: None,
            ordered: false,
            checked: None,
            tight: None,
            list_start: None,
            literal: None,
            alignments: Vec::new(),
            label: String::new(),
            html_header: false,
            html_number: None,
        }
    }
}
#[derive(Debug, Clone, Copy)]
pub struct Options {
    pub gfm: bool,
    pub extensions: bool,
}
impl Default for Options {
    fn default() -> Self {
        Self {
            gfm: true,
            extensions: true,
        }
    }
}
#[derive(Debug, Clone)]
pub struct Reference {
    pub destination: String,
    pub title: Option<String>,
}
pub type References = HashMap<String, Reference>;
pub fn utf16_len(s: &str) -> u32 {
    s.encode_utf16().count() as u32
}
