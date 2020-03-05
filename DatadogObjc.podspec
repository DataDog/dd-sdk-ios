Pod::Spec.new do |spec|
  spec.name         = "DatadogObjc"
  spec.version      = "0.0.1"
  spec.summary      = "Logging and iOS app monitoring using Datadog."
  spec.description  = <<-DESC
  Logging and iOS app monitoring using Datadog in Objective-C.
                   DESC
  spec.homepage     = "https://www.datadoghq.com"
  spec.license            = { :type => "Apache" }
  spec.authors            = { "Maciek Grzybowski" => "maciek.grzybowski@datadoghq.com" }
  spec.social_media_url   = "https://twitter.com/datadoghq"
  spec.platform           = :ios, "12.0"
  spec.swift_version      = '5.1'
  spec.source = { :git => 'https://github.com/DataDog/dd-sdk-ios.git',
                  :tag => spec.version.to_s }
  spec.source_files       = "Sources/DatadogObjc/**/*.swift"
  spec.dependency 'Datadog'
end
