Pod::Spec.new do |s|
  s.name           = 'SuflerCore'
  s.version        = '1.0.0'
  s.summary        = 'Sufler native core: custom-content Picture in Picture + Apple Speech following'
  s.description    = 'Renders the teleprompter into CMSampleBuffers for a custom AVPictureInPictureController content source, and drives the cursor from SFSpeechRecognizer via a fuzzy sequence aligner.'
  s.author         = 'Sufler'
  s.homepage       = 'https://github.com/igorao79/sufler'
  s.platforms      = {
    :ios => '17.0'
  }
  s.source         = { git: 'https://github.com/igorao79/sufler.git' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.frameworks = 'AVFoundation', 'AVKit', 'Speech', 'CoreMedia', 'CoreVideo', 'CoreText', 'QuartzCore'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_VERSION' => '5.9'
  }

  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
end
