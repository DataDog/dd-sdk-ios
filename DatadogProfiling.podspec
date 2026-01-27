Pod::Spec.new do |s|
  s.name         = "DatadogProfiling"
  s.version      = "3.5.1"
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
  
  s.private_header_files = ["DatadogProfiling/Mach/**/*.h"]

  s.preserve_paths = "DatadogProfiling/Mach/include/module.modulemap"

  s.dependency 'DatadogInternal', s.version.to_s

  # Configure C++ compilation
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'SWIFT_INCLUDE_PATHS' => '$(PODS_TARGET_SRCROOT)/DatadogProfiling/Mach'
  }

end
