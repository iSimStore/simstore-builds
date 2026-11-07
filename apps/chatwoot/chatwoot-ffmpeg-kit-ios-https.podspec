# Based on chatwoot/ffmpeg at 3bbdfe9eb257c2181307f38afd17087227df55b2.
Pod::Spec.new do |s|
  s.name             = 'chatwoot-ffmpeg-kit-ios-https'
  s.version          = '6.0.2'
  s.summary          = 'FFmpeg iOS Binaries'
  s.homepage         = 'https://github.com/chatwoot/ffmpeg'
  s.license          = { :type => 'LGPL-3.0' }
  s.authors          = { 'chatwoot' => 'https://github.com/chatwoot' }
  s.platform         = :ios, '12.1'
  s.static_framework = true
  s.requires_arc     = true
  s.source = {
    :http => 'https://github.com/chatwoot/ffmpeg/releases/download/6.0.2/ffmpegkit-ios.xcframework.zip',
    :type => 'zip',
    :sha256 => 'b5dfd4ac585a7ae8efecf959d555515bc324de52b7114d112164f841bbf5eee1'
  }
  s.vendored_frameworks = [
    'ffmpegkit.xcframework',
    'libavcodec.xcframework',
    'libavdevice.xcframework',
    'libavfilter.xcframework',
    'libavformat.xcframework',
    'libavutil.xcframework',
    'libswresample.xcframework',
    'libswscale.xcframework'
  ]
  s.libraries = ['z', 'bz2', 'c++', 'iconv']
  s.frameworks = ['AudioToolbox', 'AVFoundation', 'CoreMedia', 'VideoToolbox']
end
