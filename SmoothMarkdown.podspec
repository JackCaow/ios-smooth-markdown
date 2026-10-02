Pod::Spec.new do |spec|
  spec.name = 'SmoothMarkdown'
  spec.version = '0.4.0'
  spec.summary = 'Native SwiftUI Markdown reader, streaming reader, and editor.'
  spec.description = <<-DESC
    A native iOS Markdown library with source-preserving CommonMark and GFM
    parsing, streaming updates, selectable rich text, custom renderers,
    math and SVG rendering, and a Markdown editor.
  DESC
  spec.homepage = 'https://github.com/JackCaow/ios-smooth-markdown'
  spec.license = { :type => 'MIT', :file => 'LICENSE' }
  spec.author = 'JackCaow'
  spec.source = { :git => 'https://github.com/JackCaow/ios-smooth-markdown.git', :tag => spec.version.to_s }
  spec.ios.deployment_target = '17.0'
  spec.swift_version = '5.9'
  spec.module_name = 'SmoothMarkdown'
  spec.default_subspec = 'UI'
  spec.subspec 'Core' do |core|
    core.source_files = 'Sources/SmoothMarkdownCore/**/*.swift'
    core.vendored_frameworks = 'Artifacts/CSmoothMarkdownRust.xcframework'
    core.frameworks = 'Foundation'
  end
  spec.subspec 'UI' do |ui|
    ui.dependency 'SmoothMarkdown/Core'
    ui.source_files = 'Sources/SmoothMarkdown/**/*.swift'
    ui.frameworks = 'SwiftUI', 'UIKit', 'WebKit', 'CoreText', 'CoreGraphics'
  end
  spec.static_framework = true
  spec.preserve_paths = 'rust-core/**/*', 'tools/build-rust-parser.py'
end
