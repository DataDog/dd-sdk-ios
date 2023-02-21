#!/usr/bin/env ruby

# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.

require 'cocoapods'

version = ARGV[0]
if !version
    raise "Usage: podspec_bump_version.rb <version number>"
end

podspecs = Dir.glob('*.podspec')

for podspec in podspecs do
    spec = Pod::Specification.from_file(podspec)
    text = File.read(podspec)
    text.gsub!(/(s.version( )*= ")#{spec.version}(")/, "\\1#{version}\\3")
    File.open(podspec, "w") { |file| file.puts text }
end