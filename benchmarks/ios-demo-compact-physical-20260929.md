# iPhone 17 Demo layout acceptance, 2026-09-29

Device: physical iPhone 17, UDID `00008150-001C18E426F8401C`. The signed Demo ran on the device. No simulator was used for this change.

- `DemoExamplesUITests/testHomeAndFeatureHaveNoSecondaryHeader`: passed. [Home screenshot](evidence/ios-demo-home-no-subheader-iphone17.png), [Math page screenshot](evidence/ios-demo-math-no-subheader-iphone17.png).
- `DemoAIChatUITests/testCompactDeepSeekChatOnPhysicalDevice`: passed. [DeepSeek chat screenshot](evidence/ios-demo-deepseek-chat-iphone17.png). The screenshot shows mock mode with no API Key injected into this app launch.
- `DemoAIChatUITests/testDeepSeekSettingsExposeRuntimeKeyAndBothModels`: passed on the physical device.
- `DemoAIChatUITests/testFlutterMockPromptStreamsWithThinkingPluginAndNewChatResets`: passed on the physical device after removing a transient status assertion. Thinking card, full mock response source, new chat and Help were checked.
- Flutter fixture parity: all eight fixture groups matched Flutter commit `6a6b9a9d34c6cb8debede46cccb3bb608004f72f`.
- The user-supplied DeepSeek Key was checked through one direct `deepseek-flash` Chat Completions request: HTTP 200, response `OK`. It was never written to this repository. This direct API check does not assert that an in-app live request was tested on the device.

The iOS CI job compiles package tests and the Demo for generic iOS devices. Running UI tests remains part of local physical-device acceptance.
