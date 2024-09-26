Pod::Spec.new do |s|
  s.name         = "DatadogObjc"
  s.version      = "2.18.0"
  s.summary      = "Official Datadog Objective-C SDK for iOS."

  s.homepage     = "https://www.datadoghq.com"
  s.social_media_url   = "https://twitter.com/datadoghq"

  s.license            = { :type => "Apache", :file => 'LICENSE' }
  s.authors            = {
    "Maciek Grzybowski" => "maciek.grzybowski@datadoghq.com",
    "Maxime Epain" => "maxime.epain@datadoghq.com",
    "Ganesh Jangir" => "ganesh.jangir@datadoghq.com",
    "Maciej Burda" => "maciej.burda@datadoghq.com"
  }

  s.swift_version = '5.9'
  s.ios.deployment_target = '12.0'
  s.tvos.deployment_target = '12.0'

  s.source = { :git => 'https://github.com/DataDog/dd-sdk-ios.git', :tag => s.version.to_s }

  s.source_files = "DatadogObjc/Sources/**/*.swift"
  s.dependency 'DatadogCore', s.version.to_s
  s.dependency 'DatadogRUM', s.version.to_s
  s.dependency 'DatadogLogs', s.version.to_s
  s.dependency 'DatadogTrace', s.version.to_s
  s.dependency 'DatadogSessionReplay', s.version.to_s
end
