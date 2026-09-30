Pod::Spec.new do |spec|
  spec.name = 'SmoothMarkdown'
  spec.version = '0.2.0'
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
  spec.source_files = 'Sources/SmoothMarkdown/**/*.swift'
  spec.frameworks = 'SwiftUI', 'UIKit', 'WebKit', 'CoreText', 'CoreGraphics'
  spec.static_framework = true
end
