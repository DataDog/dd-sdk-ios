Pod::Spec.new do |s|
  s.name         = "DatadogSDK"
  s.module_name  = "Datadog"
  s.version      = "1.20.0"
  s.summary      = "Official Datadog Swift SDK for iOS."
  
  s.homepage     = "https://www.datadoghq.com"
  s.social_media_url   = "https://twitter.com/datadoghq"

  s.license            = { :type => "Apache", :file => 'LICENSE' }
  s.authors            = { 
    "Maciek Grzybowski" => "maciek.grzybowski@datadoghq.com",
    "Mert Buran" => "mert.buran@datadoghq.com",
    "Maxime Epain" => "maxime.epain@datadoghq.com"
  }

  s.swift_version      = '5.1'
  s.ios.deployment_target = '11.0'
  s.tvos.deployment_target = '11.0'

  s.source = { :git => "https://github.com/DataDog/dd-sdk-ios.git", :tag => s.version.to_s }
  
  s.source_files = ["Sources/Datadog/**/*.swift",
                    "Sources/_Datadog_Private/**/*.{h,m}",
                    "Datadog/TargetSupport/Datadog/Datadog.h"]
  s.public_header_files = ["Datadog/TargetSupport/Datadog/Datadog.h", 
                           "Sources/_Datadog_Private/include/*.h"]

  s.dependency 'DatadogInternal', s.version.to_s
  s.dependency 'DatadogTrace', s.version.to_s
  s.dependency 'DatadogRUM', s.version.to_s

end
