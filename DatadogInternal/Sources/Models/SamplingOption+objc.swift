/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

@objc(DDSamplingOption)
@objcMembers
@_spi(objc)
public final class objc_SamplingOption: NSObject {
    public let swiftType: SamplingOption

    private init(_ swiftType: SamplingOption) {
        self.swiftType = swiftType
    }

    public init(sampleRate: Float) {
        swiftType = .enabled(sampleRate: sampleRate)
    }

    public static let disabled = objc_SamplingOption(.disabled)
    public static let enabled = objc_SamplingOption(.enabled(sampleRate: 100))

    public static func enabled(sampleRate: Float) -> objc_SamplingOption {
        objc_SamplingOption(.enabled(sampleRate: sampleRate))
    }
}
