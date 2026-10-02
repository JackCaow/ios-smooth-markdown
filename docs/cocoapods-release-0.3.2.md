# CocoaPods 0.3.2 发布验收

2026-10-02，SmoothMarkdown 0.3.2 已进入 Trunk 和官方公共 Specs。SwiftPM 使用同名 GitHub tag，发布 revision 为 `fe59bdaad995fcf47f3b188ec259a68d8c8a9c3f`。

```ruby
pod 'SmoothMarkdown', '~> 0.3.2'
```

仅需要解析层时使用 `pod 'SmoothMarkdown/Core', '~> 0.3.2'`。两个 subspec 都导入 `SmoothMarkdown`；UI 只依赖库自身的 Core，没有外部 Pod。

## 公开证据

- [GitHub release](https://github.com/JackCaow/ios-smooth-markdown/releases/tag/0.3.2)
- [官方公共 podspec](https://github.com/CocoaPods/Specs/blob/master/Specs/b/a/a/SmoothMarkdown/0.3.2/SmoothMarkdown.podspec.json)
- [Trunk 版本记录](https://trunk.cocoapods.org/api/v1/pods/SmoothMarkdown)
- [发布前完整 CI](https://github.com/JackCaow/ios-smooth-markdown/actions/runs/36951063302)：包含官方 CommonMark 语法、公开使用者、CocoaPods Core/UI 构建及真实界面测试。

`pod trunk push` 校验完成后报告 GitHub commit API 超时；随后读取 Trunk 版本记录和官方公共 podspec，确认该版本已实际发布，未重复推送。

## CDN 访问

若默认 CocoaPods CDN 在你的网络中不可访问，可以使用官方 Git Specs 传输，在 Podfile 顶部添加：

```ruby
source 'https://github.com/CocoaPods/Specs.git'
```

随后执行 `pod install --repo-update`。库源码不需要 `:git`、`:path` 或本地 podspec。

## 独立使用者

新工程只声明 `pod 'SmoothMarkdown', '0.3.2'`，从上述官方 Git Specs 安装成功。锁文件仅包含库自身 Core/UI 0.3.2，没有 `EXTERNAL SOURCES`、`CHECKOUT OPTIONS` 或第三方 Pod。公开 reader、stream、editor 接口的 iOS Simulator 构建通过；这是安装与编译验收，不额外宣称真机性能结果。
