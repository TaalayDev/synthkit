#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint synthkit.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'synthkit'
  s.version          = '0.0.1'
  s.summary          = 'Cross-platform Flutter synth plugin for note playback and scheduling.'
  s.description      = <<-DESC
Cross-platform Flutter synth plugin for note playback, envelopes, filters, and beat scheduling.
                       DESC
  s.homepage         = 'https://github.com/example/synthkit'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Codex' => 'noreply@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.static_framework = true

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'synthkit_privacy' => ['Resources/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'
  s.dependency 'AudioKit', '~> 5.1'

  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
