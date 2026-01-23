Pod::Spec.new do |s|
  s.name         = "DatadogFlags"
  s.version      = "3.5.1"
  s.summary      = "Official Datadog Feature Flags module of the Swift SDK."

  s.homepage     = "https://www.datadoghq.com"
  s.social_media_url   = "https://twitter.com/datadoghq"

  s.license            = { :type => "Apache", :file => 'LICENSE' }
  s.authors            = "Datadog, Inc."

  s.swift_version = '5.9'
  s.ios.deployment_target = '12.0'
  s.tvos.deployment_target = '12.0'

  s.source = { :git => "https://github.com/DataDog/dd-sdk-ios.git", :tag => s.version.to_s }

  s.source_files = "DatadogFlags/Sources/**/*.swift"

  s.dependency 'DatadogInternal', s.version.to_s

end
