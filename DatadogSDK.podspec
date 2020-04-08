Pod::Spec.new do |s|
  s.name         = "DatadogSDK"
  s.module_name  = "Datadog"
  s.version      = "1.0.1"
  s.summary      = "Official Datadog Swift SDK for iOS."
  
  s.homepage     = "https://www.datadoghq.com"
  s.social_media_url   = "https://twitter.com/datadoghq"

  s.license            = { :type => "Apache", :file => 'LICENSE' }
  s.authors            = { 
    "Maciek Grzybowski" => "maciek.grzybowski@datadoghq.com",
    "Mert Buran" => "mert.buran@datadoghq.com"
  }

  s.swift_version      = '5.1'
  s.ios.deployment_target = '11.0'

  s.source = { :git => "https://github.com/DataDog/dd-sdk-ios.git", :tag => s.version.to_s }
  
  s.source_files = "Sources/Datadog/**/*.swift", "Datadog/DatadogPrivate/*.m"
  s.preserve_paths = "Datadog/DatadogPrivate/*.h", "Datadog/DatadogPrivate/include/*.modulemap"
  s.pod_target_xcconfig = { 
    "SWIFT_INCLUDE_PATHS" => "$(PODS_ROOT)/DatadogSDK/Datadog/DatadogPrivate/** $(PODS_TARGET_SRCROOT)/DatadogSDK/Datadog/DatadogPrivate/**"
  }
end
