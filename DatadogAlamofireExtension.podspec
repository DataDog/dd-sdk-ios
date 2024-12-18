Pod::Spec.new do |s|
  s.name         = "DatadogAlamofireExtension"
  s.version      = "2.22.0"
  s.summary      = "An Official Extensions of Datadog Swift SDK for Alamofire."
  s.description  = <<-DESC
                   The DatadogAlamofireExtension pod is deprecated and will no longer be maintained.
                   Please refer to the following documentation on how to instrument Alamofire with the Datadog iOS SDK:
                   https://docs.datadoghq.com/real_user_monitoring/mobile_and_tv_monitoring/integrated_libraries/ios
                   DESC

  s.homepage     = "https://www.datadoghq.com"
  s.social_media_url   = "https://twitter.com/datadoghq"

  s.license            = { :type => "Apache", :file => 'LICENSE' }
  s.authors            = {
    "Maciek Grzybowski" => "maciek.grzybowski@datadoghq.com",
    "Maxime Epain" => "maxime.epain@datadoghq.com",
    "Ganesh Jangir" => "ganesh.jangir@datadoghq.com",
    "Maciej Burda" => "maciej.burda@datadoghq.com"
  }

  s.deprecated = true

  s.swift_version = '5.9'
  s.ios.deployment_target = '12.0'
  s.tvos.deployment_target = '12.0'

  s.source = { :git => "https://github.com/DataDog/dd-sdk-ios.git", :tag => s.version.to_s }

  s.source_files = ["DatadogExtensions/Alamofire/**/*.swift"]
  s.dependency 'DatadogInternal', s.version.to_s
  s.dependency 'Alamofire', '~> 5.0'
end
