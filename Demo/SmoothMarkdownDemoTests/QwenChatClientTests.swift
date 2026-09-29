import Foundation
@testable import SmoothMarkdownDemo
import XCTest

final class QwenChatClientTests: XCTestCase {
    func testDeepSeekRequestUsesSelectedModelAndRuntimeKey() throws {
        let configuration = DeepSeekChatRequest(apiKey: "  sk-runtime  ", model: "deepseek-flash")
        let request = try configuration.urlRequest(prompt: "你好")
        XCTAssertEqual(request.url, DeepSeekChatRequest.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-runtime")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "deepseek-flash")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertNil(body["enable_thinking"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
        XCTAssertEqual(messages[1]["content"], "你好")

        let pro = try DeepSeekChatRequest(apiKey: "key", model: "deepseek-v4-pro")
            .urlRequest(prompt: "Hi")
        let proBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(pro.httpBody)) as? [String: Any])
        XCTAssertEqual(proBody["model"] as? String, "deepseek-v4-pro")
        XCTAssertThrowsError(try DeepSeekChatRequest(apiKey: "  ", model: "deepseek-flash")
            .urlRequest(prompt: "Hi"))
    }

    func testFlutterRequestBodyAndThinkingGate() throws {
        let configuration = QwenChatRequest(apiKey: "  sk-runtime  ", model: "qwen3-235b-a22b",
                                            enableThinking: true)
        let request = try configuration.urlRequest(prompt: "演示 thinking block")
        XCTAssertEqual(request.url, QwenChatRequest.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-runtime")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "qwen3-235b-a22b")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["enable_thinking"] as? Bool, true)
        XCTAssertEqual(body["thinking_budget"] as? Int, 10_000)
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
        XCTAssertEqual(messages[0]["content"], QwenChatRequest.systemPrompt)
        XCTAssertEqual(messages[1]["content"], "演示 thinking block")

        let oldModel = try QwenChatRequest(apiKey: "secret", model: "qwen-plus", enableThinking: true)
            .urlRequest(prompt: "Hi")
        let oldBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(oldModel.httpBody)) as? [String: Any])
        XCTAssertNil(oldBody["enable_thinking"])
        XCTAssertNil(oldBody["thinking_budget"])
        XCTAssertThrowsError(try QwenChatRequest(apiKey: "  ", model: "qwen-plus", enableThinking: false)
            .urlRequest(prompt: "Hi"))
    }

    func testSSEReassemblesSplitUTF8AndWrapsReasoning() {
        let source = """
        data: {"choices":[{"delta":{"reasoning_content":"分析"}}]}

        data: {"choices":[{"delta":{"content":"答案"}}]}

        data: [DONE]

        """
        var decoder = QwenSSEDecoder()
        var output: [String] = []
        // One byte at a time includes splits inside both JSON syntax and Han characters.
        for byte in source.utf8 { output += decoder.consume(byte) }
        output += decoder.finish()
        XCTAssertEqual(output.joined(), "<thinking>\n分析\n</thinking>\n\n答案")
        XCTAssertTrue(decoder.isDone)
        XCTAssertTrue(decoder.hasText)
    }

    func testSSEIgnoresMalformedEventsAndClosesUnfinishedThinking() {
        var decoder = QwenSSEDecoder()
        var output = decoder.consume(Data("event: ping\r\ndata: not-json\r\n\r\n".utf8))
        XCTAssertTrue(output.isEmpty)
        output += decoder.consume(Data("data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"why\"}}]}\n\n".utf8))
        output += decoder.finish()
        XCTAssertEqual(output.joined(), "<thinking>\nwhy\n</thinking>\n\n")
        XCTAssertTrue(decoder.hasText)
    }

    func testSSEReportsNoDisplayableContent() {
        var decoder = QwenSSEDecoder()
        XCTAssertTrue(decoder.consume(Data("data: {\"choices\":[]}\n\ndata: [DONE]\n\n".utf8)).isEmpty)
        XCTAssertTrue(decoder.finish().isEmpty)
        XCTAssertTrue(decoder.isDone)
        XCTAssertFalse(decoder.hasText)
    }
}
