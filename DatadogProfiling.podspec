Pod::Spec.new do |s|
  s.name         = "DatadogProfiling"
  s.version      = "2.30.0"
  s.summary      = "Official Datadog Profiling module of the Swift SDK."
  
  s.homepage     = "https://www.datadoghq.com"
  s.social_media_url   = "https://twitter.com/datadoghq"

  s.license            = { :type => "Apache", :file => 'LICENSE' }
  s.authors            = "Datadog, Inc."

  s.swift_version = '5.9'
  s.ios.deployment_target = '12.0'
  s.tvos.deployment_target = '12.0'

  s.source = { :git => "https://github.com/DataDog/dd-sdk-ios.git", :tag => s.version.to_s }
  
  s.source_files = ["DatadogProfiling/Sources/**/*.swift",
                    "DatadogProfiling/Mach/**/*.{h,c,cpp}"]

  s.dependency 'DatadogInternal', s.version.to_s

end
