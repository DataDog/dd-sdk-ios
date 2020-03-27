Pod::Spec.new do |s|
  s.name         = "Datadog"
  s.version      = "1.0.0-beta3"
  s.summary      = "Datadog Swift SDK for iOS."
  
  s.homepage     = "https://www.datadoghq.com"
  s.social_media_url   = "https://twitter.com/datadoghq"

  s.license            = { :type => "Apache" }
  s.authors            = { "Maciek Grzybowski" => "maciek.grzybowski@datadoghq.com" }

  s.swift_version      = '5.1'
  s.ios.deployment_target = '11.0'

  s.source = { :git => 'https://github.com/DataDog/dd-sdk-ios.git', :tag => s.version.to_s }
  
  s.source_files = "Sources/Datadog/**/*.swift"
  s.dependency 'OpenTracingSwift'
end
