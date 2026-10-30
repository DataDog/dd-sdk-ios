# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2026-Present Datadog, Inc.

# Local benchmark integration only. Do not publish this pod.
Pod::Spec.new do |s|
  s.name = 'RulesEvaluationPrototype'
  s.version = '0.0.1'
  s.summary = 'Isolated rules evaluation benchmark prototype'
  s.homepage = 'https://github.com/DataDog/dd-sdk-ios'
  s.license = { :type => 'Apache-2.0' }
  s.author = 'Datadog'
  s.source = { :git => 'https://github.com/DataDog/dd-sdk-ios.git' }
  s.ios.deployment_target = '15.0'
  s.swift_version = '5.9'
  s.source_files = 'Sources/RulesEvaluationPrototype/**/*.swift'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.user_target_xcconfig = { 'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) DD_FLAGS_PROTOTYPE_ENABLED=1' }
  s.dependency 'SwiftProtobuf', '= 1.38.1'
end
