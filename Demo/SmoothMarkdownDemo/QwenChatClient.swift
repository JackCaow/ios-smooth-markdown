import Foundation

/// The request used by Flutter's AI Chat example. The key is supplied at runtime.
struct QwenChatRequest {
    static let endpoint = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
    static let systemPrompt = """
    你是一个 AI 助手。在回答时，请适当使用以下格式：

    1. 使用 <artifact identifier="id" type="code" language="lang" title="title">...</artifact> 包裹代码制品
    2. 使用标准 Markdown 格式

    请确保回答内容丰富、格式清晰。
    """

    let apiKey: String
    let model: String
    let enableThinking: Bool

    func urlRequest(prompt: String) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw QwenChatError.missingKey }
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": prompt],
            ],
            "stream": true,
        ]
        if enableThinking && model.hasPrefix("qwen3") {
            body["enable_thinking"] = true
            body["thinking_budget"] = 10_000
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

/// DeepSeek's OpenAI-compatible chat endpoint. The key is never persisted by the Demo.
struct DeepSeekChatRequest {
    static let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!

    let apiKey: String
    let model: String

    func urlRequest(prompt: String) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw QwenChatError.missingKey }
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [
                ["role": "system", "content": QwenChatRequest.systemPrompt],
                ["role": "user", "content": prompt],
            ],
            "stream": true,
        ] as [String: Any])
        return request
    }
}

enum QwenChatError: LocalizedError {
    case missingKey
    case unexpectedResponse
    case httpStatus(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingKey: "API Key 为空"
        case .unexpectedResponse: "API 返回了无效的 HTTP 响应"
        case let .httpStatus(code): "API Error: \(code)"
        case .emptyResponse: "API 未返回可显示的内容"
        }
    }
}

/// Incremental SSE decoder: URLSession can split a JSON event at any byte boundary.
struct QwenSSEDecoder {
    private var pendingLine = Data()
    private var eventData: [String] = []
    private(set) var isDone = false
    private(set) var hasText = false
    private var isThinking = false

    mutating func consume(_ bytes: Data) -> [String] {
        var output: [String] = []
        for byte in bytes {
            if byte == 0x0A {
                processLine(&output)
            } else {
                pendingLine.append(byte)
            }
        }
        return output
    }

    mutating func finish() -> [String] {
        var output: [String] = []
        if !pendingLine.isEmpty { processLine(&output) }
        dispatchEvent(&output)
        if isThinking { output.append("\n</thinking>\n\n"); isThinking = false }
        return output
    }

    private mutating func processLine(_ output: inout [String]) {
        if pendingLine.last == 0x0D { pendingLine.removeLast() }
        let line = String(decoding: pendingLine, as: UTF8.self)
        pendingLine.removeAll(keepingCapacity: true)
        if line.isEmpty { dispatchEvent(&output); return }
        guard line.hasPrefix("data:") else { return }
        var payload = String(line.dropFirst(5))
        if payload.hasPrefix(" ") { payload.removeFirst() }
        eventData.append(payload)
    }

    private mutating func dispatchEvent(_ output: inout [String]) {
        guard !eventData.isEmpty else { return }
        let payload = eventData.joined(separator: "\n")
        eventData.removeAll(keepingCapacity: true)
        if payload == "[DONE]" { isDone = true; return }
        guard !isDone,
              let data = payload.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any] else { return }
        if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
            hasText = true
            if !isThinking { output.append("<thinking>\n"); isThinking = true }
            output.append(reasoning)
        }
        if let content = delta["content"] as? String, !content.isEmpty {
            hasText = true
            if isThinking { output.append("\n</thinking>\n\n"); isThinking = false }
            output.append(content)
        }
    }
}

struct QwenChatClient {
    func stream(prompt: String, configuration: QwenChatRequest,
                onDelta: @MainActor (String) -> Void) async throws {
        try await stream(request: configuration.urlRequest(prompt: prompt), onDelta: onDelta)
    }

    func stream(request: URLRequest, onDelta: @MainActor (String) -> Void) async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw QwenChatError.unexpectedResponse }
        guard http.statusCode == 200 else { throw QwenChatError.httpStatus(http.statusCode) }
        var decoder = QwenSSEDecoder()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            for fragment in decoder.consume(Data((line + "\n").utf8)) {
                await onDelta(fragment)
            }
            if decoder.isDone { break }
        }
        try Task.checkCancellation()
        for fragment in decoder.finish() { await onDelta(fragment) }
        guard decoder.hasText else { throw QwenChatError.emptyResponse }
    }
}

struct DeepSeekChatClient {
    func stream(prompt: String, configuration: DeepSeekChatRequest,
                onDelta: @MainActor (String) -> Void) async throws {
        try await QwenChatClient().stream(request: configuration.urlRequest(prompt: prompt), onDelta: onDelta)
    }
}
