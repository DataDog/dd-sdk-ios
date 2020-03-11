Pod::Spec.new do |s|
  s.name         = "Datadog"
  s.version      = "1.0.0-beta1"
  s.summary      = "Datadog Swift SDK for iOS and macOS."
  
  s.homepage     = "https://www.datadoghq.com"
  s.social_media_url   = "https://twitter.com/datadoghq"

  s.license            = { :type => "Apache" }
  s.authors            = { "Maciek Grzybowski" => "maciek.grzybowski@datadoghq.com" }

  s.swift_version      = '5.1'
  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '10.14'

  s.source = { :git => 'https://github.com/DataDog/dd-sdk-ios.git', :tag => s.version.to_s }
  
  s.source_files = "Sources/Datadog/**/*.swift"
end
