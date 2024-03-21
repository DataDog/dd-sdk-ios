Pod::Spec.new do |s|
  s.name         = "DatadogRUM"
  s.version      = "2.8.1"
  s.summary      = "Datadog Real User Monitoring Module."
  
  s.homepage     = "https://www.datadoghq.com"
  s.social_media_url   = "https://twitter.com/datadoghq"

  s.license            = { :type => "Apache", :file => 'LICENSE' }
  s.authors            = { 
    "Maciek Grzybowski" => "maciek.grzybowski@datadoghq.com",
    "Maxime Epain" => "maxime.epain@datadoghq.com",
    "Ganesh Jangir" => "ganesh.jangir@datadoghq.com",
    "Maciej Burda" => "maciej.burda@datadoghq.com"
  }

  s.swift_version = '5.7.1'
  s.ios.deployment_target = '11.0'
  s.tvos.deployment_target = '11.0'

  s.source = { :git => "https://github.com/DataDog/dd-sdk-ios.git", :tag => s.version.to_s }
  
  s.source_files = ["DatadogRUM/Sources/**/*.swift"]

  s.resource_bundle = {
    "DatadogRUM" => "DatadogRUM/Resources/PrivacyInfo.xcprivacy"
  }

  s.dependency 'DatadogInternal', s.version.to_s

end
