Pod::Spec.new do |s|
  s.name         = "DatadogSDKAlamofireExtension"
  s.module_name  = "DatadogAlamofireExtension"
  s.version      = "1.0.0"
  s.summary      = "An Official Extensions of Datadog Swift SDK for Alamofire."
  
  s.homepage     = "https://www.datadoghq.com"
  s.social_media_url   = "https://twitter.com/datadoghq"

  s.license            = { :type => "Apache", :file => 'LICENSE' }
  s.authors            = { 
    "Maciek Grzybowski" => "maciek.grzybowski@datadoghq.com",
    "Mert Buran" => "mert.buran@datadoghq.com",
    "Alexandre Costanza" => "alexandre.costanza@datadoghq.com"
  }

  s.swift_version      = '5.1'
  s.ios.deployment_target = '11.0'

  # :tag must follow DatadogSDK version below
  s.source = { :git => "https://github.com/DataDog/dd-sdk-ios.git", :tag => '1.5.0-beta1' }

  s.source_files = ["Sources/DatadogExtensions/Alamofire/**/*.swift"]
  s.dependency 'DatadogSDK', '~> 1.5.0-beta1'
  s.dependency 'Alamofire', '~> 5.0'
end
