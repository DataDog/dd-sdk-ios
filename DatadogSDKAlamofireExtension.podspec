Pod::Spec.new do |s|
  s.name         = "DatadogSDKAlamofireExtension"
  s.module_name  = "DatadogAlamofireExtension"
  s.version      = "2.5.0"
  s.summary      = "An Official Extensions of Datadog Swift SDK for Alamofire."
  
  s.homepage     = "https://www.datadoghq.com"
  s.social_media_url   = "https://twitter.com/datadoghq"

  s.license            = { :type => "Apache", :file => 'LICENSE' }
  s.authors            = { 
    "Maciek Grzybowski" => "maciek.grzybowski@datadoghq.com",
    "Maxime Epain" => "maxime.epain@datadoghq.com",
    "Ganesh Jangir" => "ganesh.jangir@datadoghq.com",
    "Maciej Burda" => "maciej.burda@datadoghq.com"
  }

  s.deprecated_in_favor_of = "DatadogAlamofireExtension"

  s.swift_version = '5.7.1'
  s.ios.deployment_target = '11.0'
  s.tvos.deployment_target = '11.0'

  s.source = { :git => "https://github.com/DataDog/dd-sdk-ios.git", :tag => s.version.to_s }

  s.source_files = ["DatadogExtensions/Alamofire/**/*.swift"]
  s.dependency 'DatadogInternal', s.version.to_s
  s.dependency 'Alamofire', '~> 5.0'
end
