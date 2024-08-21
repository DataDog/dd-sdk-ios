/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

public struct UploadPerformanceMock: UploadPerformancePreset {
    public let initialUploadDelay: TimeInterval
    public let minUploadDelay: TimeInterval
    public let maxUploadDelay: TimeInterval
    public let uploadDelayChangeRate: Double

    public init(initialUploadDelay: TimeInterval, minUploadDelay: TimeInterval, maxUploadDelay: TimeInterval, uploadDelayChangeRate: Double) {
        self.initialUploadDelay = initialUploadDelay
        self.minUploadDelay = minUploadDelay
        self.maxUploadDelay = maxUploadDelay
        self.uploadDelayChangeRate = uploadDelayChangeRate
    }

    public static let noOp = UploadPerformanceMock(
        initialUploadDelay: .distantFuture,
        minUploadDelay: .distantFuture,
        maxUploadDelay: .distantFuture,
        uploadDelayChangeRate: 0
    )

    /// Optimized for performing very fast uploads in unit tests.
    public static let veryQuick = UploadPerformanceMock(
        initialUploadDelay: 0.05,
        minUploadDelay: 0.05,
        maxUploadDelay: 0.05,
        uploadDelayChangeRate: 0
    )

    /// Optimized for performing very fast first upload and then changing to unrealistically long intervals.
    public static let veryQuickInitialUpload = UploadPerformanceMock(
        initialUploadDelay: 0.05,
        minUploadDelay: 60,
        maxUploadDelay: 60,
        uploadDelayChangeRate: 60 / 0.05
    )
}

extension ExecutionContext: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        return .init(previousResponseCode: .mockAny(), attempt: .mockAny())
    }

    public static func mockRandom() -> Self {
        return .init(previousResponseCode: .mockRandom(), attempt: .mockRandom())
    }
    
    public static func mockWith(previousResponseCode: Int?, attempt: UInt) -> Self {
        return .init(previousResponseCode: previousResponseCode, attempt: attempt)
    }
}
