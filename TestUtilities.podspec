Pod::Spec.new do |s|
  s.name         = "TestUtilities"
  s.version      = "3.1.0"
  s.summary      = "Datadog Testing Utilities. This module is for internal testing and should not be published."

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
  s.ios.deployment_target = '12.0'
  s.tvos.deployment_target = '12.0'

  s.source = { :git => "https://github.com/DataDog/dd-sdk-ios.git", :tag => s.version.to_s }

  s.pod_target_xcconfig = {
    'ENABLE_TESTING_SEARCH_PATHS'=>'YES'
  }

  s.framework = 'XCTest'

  s.source_files = [
    "TestUtilities/Sources/**/*.swift"
  ]

  s.dependency 'DatadogCore'
  s.dependency 'DatadogInternal'
  s.dependency 'DatadogLogs'
  s.dependency 'DatadogRUM'
  s.dependency 'DatadogSessionReplay'
  s.dependency 'DatadogTrace'
  s.dependency 'DatadogCrashReporting'
  s.dependency 'DatadogWebViewTracking'

end