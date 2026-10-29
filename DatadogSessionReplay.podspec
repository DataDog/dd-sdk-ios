Pod::Spec.new do |s|
  s.name         = "DatadogSessionReplay"
  s.version      = "3.21.0"
  s.summary      = "Official Datadog Session Replay SDK for iOS."

  s.homepage     = "https://www.datadoghq.com"
  s.social_media_url   = "https://twitter.com/datadoghq"

  s.license            = { :type => "Apache", :file => 'LICENSE' }
  s.authors            = {
    "Maciek Grzybowski" => "maciek.grzybowski@datadoghq.com",
    "Maciej Burda" => "maciej.burda@datadoghq.com",
    "Maxime Epain" => "maxime.epain@datadoghq.com",
    "Ganesh Jangir" => "ganesh.jangir@datadoghq.com"
  }

  s.swift_version = '5.9'
  s.ios.deployment_target = '15.0'
  s.tvos.deployment_target = '15.0'

  s.source = { :git => "https://github.com/DataDog/dd-sdk-ios.git", :tag => s.version.to_s }

  s.source_files = ["DatadogSessionReplay/Sources/**/*.swift"]
  s.ios.source_files = ["DatadogSessionReplay/WebP/**/*.{c,h}"]
  s.ios.private_header_files = ["DatadogSessionReplay/WebP/**/*.h"]
  s.preserve_paths = ["DatadogSessionReplay/WebP/include/module.modulemap",
                      "DatadogSessionReplay/WebP/{COPYING,PATENTS,AUTHORS}"]
  s.ios.pod_target_xcconfig = {
    'SWIFT_INCLUDE_PATHS' => '$(PODS_TARGET_SRCROOT)/DatadogSessionReplay/WebP/include',
    'HEADER_SEARCH_PATHS' => '$(PODS_TARGET_SRCROOT)/DatadogSessionReplay/WebP'
  }
  s.dependency 'DatadogInternal', s.version.to_s
end
