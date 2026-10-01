# CocoaPods 0.3.1 发布验收

2026-10-01，`SmoothMarkdown 0.3.1` 已进入 CocoaPods 官方公共 Specs 仓库。SwiftPM 同时可使用 GitHub `0.3.1` tag；发布源码提交为 `8f046cf0014341678a87304070c4c2017614c88a`。

## 安装

```ruby
platform :ios, '17.0'
target 'YourApp' do
  pod 'SmoothMarkdown', '~> 0.3.1'
end
```

执行 `pod install --repo-update` 并打开生成的 `.xcworkspace`。只需解析时使用 `pod 'SmoothMarkdown/Core', '~> 0.3.1'`，两者的导入模块名均为 `SmoothMarkdown`。

## 公开发布记录

- [GitHub 0.3.1 release](https://github.com/JackCaow/ios-smooth-markdown/releases/tag/0.3.1)
- [官方公共 podspec](https://github.com/CocoaPods/Specs/blob/master/Specs/b/a/a/SmoothMarkdown/0.3.1/SmoothMarkdown.podspec.json)
- [Trunk 最新 spec 查询](https://trunk.cocoapods.org/api/v1/pods/SmoothMarkdown/specs/latest)

`pod trunk push` 完成 Core/UI 构建验证后，客户端收到 GitHub commit API 超时。随后查询 Trunk 和官方 Specs，确认该版本的公共 spec 已提交；因此通过公开状态核对了结果，未重复覆盖版本。

## 独立消费者验证

使用只声明 `pod 'SmoothMarkdown', '0.3.1'` 的新工程，依赖从官方 Specs 解析，未使用库的 `:git`、`:path` 或本地 podspec。

- `pod install` 成功，锁定 0.3.1。
- Podfile.lock 仅包含 SmoothMarkdown 和它自己的 Core/UI subspec，没有第三方 Pod。
- iOS Simulator 构建成功，覆盖 reader、stream、editor、Design Token 和 Core HTML 导出公开接口。
- 本次为安装和编译验证；不追加真机性能或界面验收结论。

## CDN 访问边界

本机访问默认 `cdn.cocoapods.org` 返回 HTTP 403（错误码 1010），因此本次独立消费者使用官方 Git Specs 源：

```ruby
source 'https://github.com/CocoaPods/Specs.git'
```

这是 CocoaPods 官方公共索引的另一种传输方式。遇到相同网络问题时将该行放在 Podfile 顶部，再执行 `pod install`。发布成功不代表所有网络环境中的 CDN 访问同时可用。
