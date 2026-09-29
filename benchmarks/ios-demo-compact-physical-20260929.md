# iPhone 17 Demo layout acceptance, 2026-09-29

Device: physical iPhone 17, UDID `00008150-001C18E426F8401C`. The signed Demo ran on the device. No simulator was used for this change.

- `DemoExamplesUITests/testHomeAndFeatureHaveNoSecondaryHeader`: passed. [Home screenshot](evidence/ios-demo-home-no-subheader-iphone17.png), [Math page screenshot](evidence/ios-demo-math-no-subheader-iphone17.png).
- The same UI test passed again after the inline-code background fix. [Updated iPhone screenshot](evidence/ios-demo-inline-code-centered-iphone17.png) shows `var x = 42;` centered vertically in its gray background on the Basic Text Formatting page. The earlier screenshot placed the fill above the code glyphs.
- `DemoAIChatUITests/testCompactDeepSeekChatOnPhysicalDevice`: passed. [DeepSeek chat screenshot](evidence/ios-demo-deepseek-chat-iphone17.png). The screenshot shows mock mode with no API Key injected into this app launch.
- `DemoAIChatUITests/testDeepSeekSettingsExposeRuntimeKeyAndBothModels`: passed on the physical device.
- `DemoAIChatUITests/testFlutterMockPromptStreamsWithThinkingPluginAndNewChatResets`: passed on the physical device after removing a transient status assertion. Thinking card, full mock response source, new chat and Help were checked. [Mock reply screenshot](evidence/ios-demo-deepseek-mock-reply-iphone17.png) records the bubble typography and spacing on the iPhone.
- Flutter fixture parity: all eight fixture groups matched Flutter main merge commit `0634734ccc6e2c63ab78904a68496f4b0a29f071`.
- The user-supplied DeepSeek Key was stored only in local macOS Keychain and injected into the signed Demo process on this iPhone. `DemoAIChatUITests/testPrelaunchedDeepSeekDevelopmentKeyOnPhysicalDevice` then passed: the navigation status was `deepseek-flash`, the actual in-app streaming response to `Reply with exactly OK.` completed with `OK`, and the response source contained no error. [Live reply screenshot](evidence/ios-demo-deepseek-live-iphone17.png). The first live run had exposed an SSE parser bug: `URLSession.AsyncBytes.lines` omitted blank event separators, causing an empty-response error. The client now feeds the SSE decoder raw bytes, retaining those separators. A separate direct API check also returned HTTP 200 and `OK`. No Key was written to this repository or screenshots.
- `QwenChatClientTests`: all five focused request/streaming tests passed on the physical iPhone after the SSE decoder change.

The iOS CI job compiles package tests and the Demo for generic iOS devices. Running UI tests remains part of local physical-device acceptance.
