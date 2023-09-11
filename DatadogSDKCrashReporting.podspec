Pod::Spec.new do |s|
  s.name         = "DatadogSDKCrashReporting"
  s.module_name  = "DatadogCrashReporting"
  s.version      = "2.1.3"
  s.summary      = "Official Datadog Crash Reporting SDK for iOS."
  
  s.homepage     = "https://www.datadoghq.com"
  s.social_media_url   = "https://twitter.com/datadoghq"

  s.license            = { :type => "Apache", :file => 'LICENSE' }
  s.authors            = { 
    "Maciek Grzybowski" => "maciek.grzybowski@datadoghq.com",
    "Maxime Epain" => "maxime.epain@datadoghq.com",
    "Ganesh Jangir" => "ganesh.jangir@datadoghq.com",
    "Maciej Burda" => "maciej.burda@datadoghq.com"
  }

  s.swift_version = '5.8.0'
  s.ios.deployment_target = '11.0'
  s.tvos.deployment_target = '11.0'

  s.deprecated_in_favor_of = 'DatadogCrashReporting'

  s.source = { :git => 'https://github.com/DataDog/dd-sdk-ios.git', :tag => s.version.to_s }
  s.static_framework = true

  s.source_files = "DatadogCrashReporting/Sources/**/*.swift"
  s.dependency 'DatadogInternal', s.version.to_s
  s.dependency 'PLCrashReporter', '~> 1.11.1'
end
