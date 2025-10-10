Pod::Spec.new do |s|
  s.name         = "DatadogCore"
  s.version      = "2.30.2"
  s.summary      = "Official Datadog Swift SDK for iOS."
  
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
  s.watchos.deployment_target = '7.0'

  s.source = { :git => "https://github.com/DataDog/dd-sdk-ios.git", :tag => s.version.to_s }
  
  s.source_files = ["DatadogCore/Sources/**/*.swift",
                    "DatadogCore/Private/**/*.{h,m}"]

  s.resource_bundle = {
    "DatadogCore" => "DatadogCore/Resources/PrivacyInfo.xcprivacy"
  }

  s.dependency 'DatadogInternal', s.version.to_s

end
