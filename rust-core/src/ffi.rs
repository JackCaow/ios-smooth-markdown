use crate::ast::{utf16_len, Node, Options};
use std::ffi::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};

const MAX_UNITS: usize = 8 * 1024 * 1024;
const MAX_NODES: usize = 1_000_000;
const MAX_WIRE_BYTES: usize = 64 * 1024 * 1024;
#[repr(C)]
pub struct SmrBuffer {
    pub data: *const u8,
    pub len: usize,
    pub owner: *mut c_void,
}
impl Default for SmrBuffer {
    fn default() -> Self {
        Self {
            data: std::ptr::null(),
            len: 0,
            owner: std::ptr::null_mut(),
        }
    }
}
#[no_mangle]
pub extern "C" fn smr_abi_version() -> u32 {
    1
}

#[no_mangle]
pub extern "C" fn smr_stream_new(options: u32) -> *mut c_void {
    if options & !3 != 0 { return std::ptr::null_mut(); }
    catch_unwind(|| Box::into_raw(Box::new(crate::stream::Session::new(Options {
        gfm: options & 1 != 0, extensions: options & 2 != 0,
    }))).cast()).unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn smr_stream_free(session: *mut c_void) {
    if !session.is_null() { drop(Box::from_raw(session.cast::<crate::stream::Session>())); }
}

#[no_mangle]
pub unsafe extern "C" fn smr_stream_update_utf16(
    session: *mut c_void, source: *const u16, length: usize,
    result: *mut SmrBuffer, retained_blocks: *mut u32,
) -> i32 {
    if !result.is_null() { *result = SmrBuffer::default(); }
    if !retained_blocks.is_null() { *retained_blocks = 0; }
    if session.is_null() { return 1; }
    let session = &mut *session.cast::<crate::stream::Session>();
    if result.is_null() || retained_blocks.is_null() || (length != 0 && source.is_null()) {
        session.reset(); return 1;
    }
    if length > MAX_UNITS { session.reset(); return 2; }
    let attempt = catch_unwind(AssertUnwindSafe(|| {
        let units = if length == 0 { &[][..] } else { std::slice::from_raw_parts(source, length) };
        let delta = session.update(units);
        if delta.total_nodes > MAX_NODES || delta.total_wire_bytes > MAX_WIRE_BYTES { return Err(2); }
        let retained = delta.retained_blocks as u32;
        let bytes = encode(&delta.into_wire_root(), units)?;
        let owner = Box::new(bytes);
        Ok::<_, i32>((SmrBuffer {
            data: owner.as_ptr(), len: owner.len(), owner: Box::into_raw(owner).cast(),
        }, retained))
    }));
    match attempt {
        Ok(Ok((buffer, retained))) => { *result = buffer; *retained_blocks = retained; 0 }
        Ok(Err(status)) => { session.reset(); status }
        Err(_) => { session.reset(); 3 }
    }
}

/// Caller supplies a readable UTF-16 allocation and a writable, empty result.
/// Input is copied before parsing. Original UTF-16 is retained for source strings,
/// including temporary isolated surrogates from an editor/streaming prefix.
#[no_mangle]
pub unsafe extern "C" fn smr_parse_utf16(
    source: *const u16,
    length: usize,
    options: u32,
    result: *mut SmrBuffer,
) -> i32 {
    if result.is_null() {
        return 1;
    }
    *result = SmrBuffer::default();
    if length > MAX_UNITS {
        return 2;
    }
    if (length != 0 && source.is_null()) || options & !3 != 0 {
        return 1;
    }
    let attempt = catch_unwind(AssertUnwindSafe(|| {
        let units = if length == 0 {
            Vec::new()
        } else {
            std::slice::from_raw_parts(source, length).to_vec()
        };
        let text = String::from_utf16_lossy(&units);
        // Lossy decoding preserves UTF-16 length: each unpaired surrogate becomes
        // one replacement character; valid surrogate pairs remain two units.
        debug_assert_eq!(utf16_len(&text) as usize, units.len());
        let tree = crate::parse(
            &text,
            Options {
                gfm: options & 1 != 0,
                extensions: options & 2 != 0,
            },
        );
        let bytes = encode(&tree, &units)?;
        let owner = Box::new(bytes);
        let output = SmrBuffer {
            data: owner.as_ptr(),
            len: owner.len(),
            owner: Box::into_raw(owner).cast(),
        };
        Ok::<_, i32>(output)
    }));
    match attempt {
        Ok(Ok(buffer)) => {
            *result = buffer;
            0
        }
        Ok(Err(status)) => status,
        Err(_) => 3,
    }
}

#[no_mangle]
pub unsafe extern "C" fn smr_buffer_free(buffer: *mut SmrBuffer) {
    if buffer.is_null() {
        return;
    }
    if !(*buffer).owner.is_null() {
        drop(Box::from_raw((*buffer).owner.cast::<Vec<u8>>()));
    }
    *buffer = SmrBuffer::default();
}
fn word(out: &mut Vec<u8>, n: u32) {
    out.extend_from_slice(&n.to_le_bytes());
}
fn string(out: &mut Vec<u8>, value: Option<&str>) {
    if let Some(value) = value {
        word(out, value.encode_utf16().count() as u32);
        for unit in value.encode_utf16() { out.extend_from_slice(&unit.to_le_bytes()); }
    } else {
        word(out, u32::MAX);
    }
}
pub(crate) fn encoded_node_size(node: &Node) -> usize {
    let values = [Some(node.info.as_str()), Some(node.destination.as_str()),
                  node.title.as_deref(), node.literal.as_deref(), Some(node.label.as_str())];
    56 + values.into_iter().flatten().map(|v| v.encode_utf16().count() * 2).sum::<usize>()
        + node.alignments.iter().map(|v| 4 + v.as_ref().map_or(0, |v| v.encode_utf16().count() * 2)).sum::<usize>()
}
fn encode(root: &Node, original: &[u16]) -> Result<Vec<u8>, i32> {
    let mut count = 0usize;
    let mut wire_bytes = 8usize;
    let mut stack = vec![(root, 0usize)];
    while let Some((node, depth)) = stack.pop() {
        count += 1;
        let end = node.span.start as usize + node.span.len as usize;
        if end > original.len() {
            return Err(3);
        }
        // Every parser node uses the original source span. Literal/semantic text
        // is encoded separately; never duplicate the source across the boundary.
        wire_bytes += encoded_node_size(node);
        if wire_bytes > MAX_WIRE_BYTES {
            return Err(2);
        }
        if count > MAX_NODES || depth > 256 {
            return Err(2);
        }
        stack.extend(node.children.iter().rev().map(|child| (child, depth + 1)));
    }
    let mut out = Vec::with_capacity(wire_bytes);
    out.extend_from_slice(b"SMR1");
    word(&mut out, count as u32);
    let mut stack = vec![root];
    while let Some(node) = stack.pop() {
        word(&mut out, node.kind as u32);
        word(&mut out, node.span.start);
        word(&mut out, node.span.len);
        word(&mut out, node.level);
        let flags = u32::from(node.ordered)
            | (u32::from(node.checked == Some(true)) << 1)
            | (u32::from(node.checked.is_some()) << 2)
            | (u32::from(node.tight == Some(true)) << 3)
            | (u32::from(node.tight.is_some()) << 4)
            | (u32::from(node.list_start.is_some()) << 5);
        word(&mut out, flags);
        word(&mut out, node.list_start.unwrap_or(0));
        word(&mut out, node.children.len() as u32);
        word(&mut out, 0xfffffffe);
        string(&mut out, Some(&node.info));
        string(&mut out, Some(&node.destination));
        string(&mut out, node.title.as_deref());
        string(&mut out, node.literal.as_deref());
        string(&mut out, Some(&node.label));
        word(&mut out, node.alignments.len() as u32);
        for alignment in &node.alignments {
            string(&mut out, alignment.as_deref());
        }
        stack.extend(node.children.iter().rev());
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn cumulative_stream_wire_budget_matches_full_encoding() {
        let source = "# Heading🙂\n\nText **bold** [link](https://example.test).\n\n| a | b |\n| :- | -: |\n| x | y |\n\n```rust\nlet x = 1;\n```\n\n".repeat(8);
        let units: Vec<_> = source.encode_utf16().collect();
        let mut session = crate::stream::Session::new(Options::default());
        for end in (31..units.len()).step_by(31).chain(std::iter::once(units.len())) {
            let delta = session.update(&units[..end]);
            let full = crate::parse(&String::from_utf16_lossy(&units[..end]), Options::default());
            assert_eq!(delta.total_wire_bytes, encode(&full, &units[..end]).unwrap().len());
            let mut nodes = 0; let mut stack = vec![&full];
            while let Some(n) = stack.pop() { nodes += 1; stack.extend(&n.children); }
            assert_eq!(delta.total_nodes, nodes);
        }
    }
    #[test]
    fn stream_delta_retention_failure_reset_and_isolated_surrogates() {
        let handle = smr_stream_new(3);
        assert!(!handle.is_null());
        assert!(smr_stream_new(8).is_null());
        let initial: Vec<u16> = "one\n\ntwo\n\nthree\n\nfour\n".encode_utf16().collect();
        let mut result = SmrBuffer::default(); let mut retained = 99;
        unsafe {
            assert_eq!(smr_stream_update_utf16(handle, initial.as_ptr(), initial.len(), &mut result, &mut retained), 0);
            assert_eq!(retained, 0); smr_buffer_free(&mut result);
            let mut next = initial.clone(); next.extend("\nfive".encode_utf16());
            assert_eq!(smr_stream_update_utf16(handle, next.as_ptr(), next.len(), &mut result, &mut retained), 0);
            assert_eq!(retained, 2); smr_buffer_free(&mut result);
            assert_eq!(smr_stream_update_utf16(handle, next.as_ptr(), next.len(), &mut result, &mut retained), 0);
            assert_eq!(retained, 5); smr_buffer_free(&mut result);
            assert_eq!(smr_stream_update_utf16(handle, std::ptr::null(), 1, &mut result, &mut retained), 1);
            assert_eq!(retained, 0); assert!(result.owner.is_null());
            assert_eq!(smr_stream_update_utf16(handle, next.as_ptr(), next.len(), &mut result, &mut retained), 0);
            assert_eq!(retained, 0); smr_buffer_free(&mut result);
            let prefix = [0x61u16, 0xd83d];
            assert_eq!(smr_stream_update_utf16(handle, prefix.as_ptr(), 2, &mut result, &mut retained), 0);
            smr_buffer_free(&mut result);
            let completed = [0x61u16, 0xd83d, 0xde42];
            assert_eq!(smr_stream_update_utf16(handle, completed.as_ptr(), 3, &mut result, &mut retained), 0);
            let incremental = std::slice::from_raw_parts(result.data, result.len).to_vec();
            smr_buffer_free(&mut result);
            assert_eq!(smr_parse_utf16(completed.as_ptr(), 3, 3, &mut result), 0);
            assert_eq!(incremental, std::slice::from_raw_parts(result.data, result.len));
            smr_buffer_free(&mut result); smr_stream_free(handle); smr_stream_free(std::ptr::null_mut());
        }
    }
    #[test]
    fn invalid_inputs_do_not_allocate() {
        let mut result = SmrBuffer::default();
        assert_eq!(
            unsafe { smr_parse_utf16(std::ptr::null(), 1, 0, &mut result) },
            1
        );
        assert_eq!(
            unsafe { smr_parse_utf16(std::ptr::null(), MAX_UNITS + 1, 0, &mut result) },
            2
        );
        assert_eq!(
            unsafe { smr_parse_utf16(std::ptr::null(), 0, 8, &mut result) },
            1
        );
        assert!(result.owner.is_null());
    }
    #[test]
    fn empty_document_owns_and_releases_result() {
        let mut result = SmrBuffer::default();
        assert_eq!(
            unsafe { smr_parse_utf16(std::ptr::null(), 0, 0, &mut result) },
            0
        );
        assert_eq!(
            unsafe { std::slice::from_raw_parts(result.data, 4) },
            b"SMR1"
        );
        unsafe {
            smr_buffer_free(&mut result);
            smr_buffer_free(&mut result);
        }
        assert!(result.owner.is_null());
    }
    #[test]
    fn wire_preserves_temporary_isolated_surrogate() {
        let source = [b'a' as u16, 0xd83d];
        let mut result = SmrBuffer::default();
        assert_eq!(
            unsafe { smr_parse_utf16(source.as_ptr(), source.len(), 0, &mut result) },
            0
        );
        let bytes = unsafe { std::slice::from_raw_parts(result.data, result.len) };
        // Source is retrieved from the caller's original units, including the unpaired surrogate.
        assert_eq!(&bytes[36..40], &0xfffffffeu32.to_le_bytes());
        unsafe {
            smr_buffer_free(&mut result);
        }
    }
}

#[repr(C)]
#[derive(Default)]
pub struct SmrMatch {
    pub consumed: u32,
    pub id: u32,
}
pub type InlineCallback =
    unsafe extern "C" fn(*mut c_void, *const u16, usize, u32, u32, *mut SmrMatch) -> i32;
pub type BlockCallback = unsafe extern "C" fn(
    *mut c_void,
    *const *const u16,
    *const usize,
    usize,
    u32,
    u32,
    *mut SmrMatch,
) -> i32;
pub type InlineContextCallback = unsafe extern "C" fn(*mut c_void, *const u16, usize, i32) -> i32;
pub type BlockContextCallback =
    unsafe extern "C" fn(*mut c_void, *const *const u16, *const usize, usize, i32) -> i32;
#[repr(C)]
pub struct SmrHooks {
    pub context: *mut c_void,
    pub inline_callback: Option<InlineCallback>,
    pub block_callback: Option<BlockCallback>,
    pub inline_context: Option<InlineContextCallback>,
    pub block_context: Option<BlockContextCallback>,
}
struct Callbacks<'a> {
    hooks: &'a SmrHooks,
    error: std::cell::Cell<bool>,
    block_contexts: std::cell::RefCell<Vec<(Vec<*const u16>, Vec<usize>)>>,
}
impl crate::hooks::Hooks for Callbacks<'_> {
    fn begin_inline(&self, u: &[u16]) {
        if let Some(cb) = self.hooks.inline_context {
            if unsafe { cb(self.hooks.context, u.as_ptr(), u.len(), 1) } < 0 {
                self.error.set(true)
            }
        }
    }
    fn end_inline(&self) {
        if let Some(cb) = self.hooks.inline_context {
            unsafe {
                cb(self.hooks.context, std::ptr::null(), 0, 0);
            }
        }
    }
    fn begin_block(&self, u: &[Vec<u16>]) {
        self.block_contexts.borrow_mut().push((
            u.iter().map(|s| s.as_ptr()).collect(),
            u.iter().map(|s| s.len()).collect(),
        ));
        if let Some(cb) = self.hooks.block_context {
            let contexts = self.block_contexts.borrow();
            let (ptrs, lens) = contexts.last().unwrap();
            if unsafe { cb(self.hooks.context, ptrs.as_ptr(), lens.as_ptr(), u.len(), 1) } < 0 {
                self.error.set(true)
            }
        }
    }
    fn end_block(&self) {
        if let Some(cb) = self.hooks.block_context {
            unsafe {
                cb(self.hooks.context, std::ptr::null(), std::ptr::null(), 0, 0);
            }
        }
        self.block_contexts.borrow_mut().pop();
    }
    fn inline(
        &self,
        _s: &str,
        units: &[u16],
        index: u32,
        absolute: u32,
    ) -> Option<crate::hooks::Match> {
        if self.error.get() {
            return None;
        }
        let cb = self.hooks.inline_callback?;
        let mut found = SmrMatch::default();
        let status = unsafe {
            cb(
                self.hooks.context,
                units.as_ptr(),
                units.len(),
                index,
                absolute,
                &mut found,
            )
        };
        if status < 0 {
            self.error.set(true)
        }
        (status == 1).then_some(crate::hooks::Match {
            consumed: found.consumed,
            id: found.id,
        })
    }
    fn block(
        &self,
        units: &[Vec<u16>],
        index: usize,
        absolute: u32,
    ) -> Option<crate::hooks::Match> {
        if self.error.get() {
            return None;
        }
        let cb = self.hooks.block_callback?;
        let contexts = self.block_contexts.borrow();
        let (ptrs, lens) = contexts.last()?;
        let mut found = SmrMatch::default();
        let status = unsafe {
            cb(
                self.hooks.context,
                ptrs.as_ptr(),
                lens.as_ptr(),
                units.len(),
                index as u32,
                absolute,
                &mut found,
            )
        };
        if status < 0 {
            self.error.set(true)
        }
        (status == 1).then_some(crate::hooks::Match {
            consumed: found.consumed,
            id: found.id,
        })
    }
}
unsafe fn input<'a, T>(p: *const T, len: usize) -> Result<&'a [T], i32> {
    if len != 0 && p.is_null() {
        Err(1)
    } else if len == 0 {
        Ok(&[])
    } else {
        Ok(std::slice::from_raw_parts(p, len))
    }
}
unsafe fn output(result: *mut SmrBuffer, body: impl FnOnce() -> Result<Vec<u8>, i32>) -> i32 {
    if result.is_null() {
        return 1;
    }
    *result = SmrBuffer::default();
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(Ok(bytes)) => {
            if bytes.len() > MAX_WIRE_BYTES {
                return 2;
            }
            let owner = Box::new(bytes);
            *result = SmrBuffer {
                data: owner.as_ptr(),
                len: owner.len(),
                owner: Box::into_raw(owner).cast(),
            };
            0
        }
        Ok(Err(e)) => e,
        Err(_) => 3,
    }
}
fn html_bytes(text: String) -> Vec<u8> {
    text.encode_utf16().flat_map(u16::to_le_bytes).collect()
}
#[no_mangle]
pub unsafe extern "C" fn smr_parse_with_hooks_utf16(
    source: *const u16,
    length: usize,
    options: u32,
    hooks: *const SmrHooks,
    result: *mut SmrBuffer,
) -> i32 {
    output(result, || {
        if length > MAX_UNITS {
            return Err(2);
        }
        if options & !19 != 0 {
            return Err(1);
        }
        let units = input(source, length)?;
        let text = String::from_utf16_lossy(units);
        let callbacks = hooks.as_ref().map(|hooks| Callbacks {
            hooks,
            error: std::cell::Cell::new(false),
            block_contexts: std::cell::RefCell::new(Vec::new()),
        });
        let ast = crate::block::parse_with_hook_policy(
            &text,
            Options {
                gfm: options & 1 != 0,
                extensions: options & 2 != 0,
            },
            callbacks.as_ref().map(|c| c as &dyn crate::hooks::Hooks),
            options & 16 != 0,
        );
        if callbacks.as_ref().is_some_and(|c| c.error.get()) {
            return Err(4);
        }
        encode(&ast, units)
    })
}
#[no_mangle]
pub unsafe extern "C" fn smr_parse_inline_utf16(
    source: *const u16,
    length: usize,
    options: u32,
    refs: *const u8,
    refs_len: usize,
    hooks: *const SmrHooks,
    result: *mut SmrBuffer,
) -> i32 {
    output(result, || {
        if length > MAX_UNITS || refs_len > MAX_WIRE_BYTES {
            return Err(2);
        }
        if options & !3 != 0 {
            return Err(1);
        }
        let units = input(source, length)?;
        let text = String::from_utf16_lossy(units);
        let refs = crate::wire::references(input(refs, refs_len)?)?;
        let callbacks = hooks.as_ref().map(|hooks| Callbacks {
            hooks,
            error: std::cell::Cell::new(false),
            block_contexts: std::cell::RefCell::new(Vec::new()),
        });
        let mut ast = Node::new(crate::ast::Kind::Document, &text, 0, utf16_len(&text));
        ast.children = crate::inline::parse_with_hooks(
            &text,
            0,
            &refs,
            Options {
                gfm: options & 1 != 0,
                extensions: options & 2 != 0,
            },
            callbacks.as_ref().map(|c| c as &dyn crate::hooks::Hooks),
        );
        if callbacks.as_ref().is_some_and(|c| c.error.get()) {
            return Err(4);
        }
        encode(&ast, units)
    })
}
#[no_mangle]
pub unsafe extern "C" fn smr_render_ast_utf16(
    bytes: *const u8,
    length: usize,
    options: u32,
    result: *mut SmrBuffer,
) -> i32 {
    output(result, || {
        if length > MAX_WIRE_BYTES {
            return Err(2);
        }
        if options & !12 != 0 {
            return Err(1);
        }
        let ast = crate::wire::decode(input(bytes, length)?)?;
        Ok(html_bytes(crate::html::render_bounded(
            &ast,
            options,
            MAX_WIRE_BYTES / 2,
        )?))
    })
}
#[no_mangle]
pub unsafe extern "C" fn smr_export_html_utf16(
    source: *const u16,
    length: usize,
    options: u32,
    result: *mut SmrBuffer,
) -> i32 {
    output(result, || {
        if length > MAX_UNITS {
            return Err(2);
        }
        if options & !15 != 0 {
            return Err(1);
        }
        let text = String::from_utf16_lossy(input(source, length)?);
        let ast = crate::parse(
            &text,
            Options {
                gfm: options & 1 != 0,
                extensions: options & 2 != 0,
            },
        );
        let html = crate::html::render_bounded(&ast, options, MAX_WIRE_BYTES / 2)?;
        Ok(html_bytes(if options & 1 != 0 {
            crate::html::filter_gfm(&html)
        } else {
            html
        }))
    })
}
