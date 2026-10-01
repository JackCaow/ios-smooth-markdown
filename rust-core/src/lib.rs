pub mod ast;
pub mod inline;
pub mod block;
pub mod html;
pub mod ffi;

pub fn parse(source: &str, options: ast::Options) -> ast::Node {
    block::parse(source, options)
}
