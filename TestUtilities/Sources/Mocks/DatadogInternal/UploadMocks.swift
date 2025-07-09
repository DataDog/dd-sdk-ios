/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

public struct UploadPerformanceMock: UploadPerformancePreset {
    public var initialUploadDelay: TimeInterval
    public var minUploadDelay: TimeInterval
    public var maxUploadDelay: TimeInterval
    public var uploadDelayChangeRate: Double
    public var maxBatchesPerUpload: Int
    public var maxUploadJitter: TimeInterval

    public init(
        initialUploadDelay: TimeInterval,
        minUploadDelay: TimeInterval,
        maxUploadDelay: TimeInterval,
        uploadDelayChangeRate: Double,
        maxBatchesPerUpload: Int = 1,
        maxUploadJitter: TimeInterval = 0.0
    ) {
        self.initialUploadDelay = initialUploadDelay
        self.minUploadDelay = minUploadDelay
        self.maxUploadDelay = maxUploadDelay
        self.uploadDelayChangeRate = uploadDelayChangeRate
        self.maxBatchesPerUpload = maxBatchesPerUpload
        self.maxUploadJitter = maxUploadJitter
    }

    public static let noOp = UploadPerformanceMock(
        initialUploadDelay: .distantFuture,
        minUploadDelay: .distantFuture,
        maxUploadDelay: .distantFuture,
        uploadDelayChangeRate: 0,
        maxBatchesPerUpload: 0
    )

    /// Optimized for performing very fast uploads in unit tests.
    public static let veryQuick = UploadPerformanceMock(
        initialUploadDelay: 0.05,
        minUploadDelay: 0.05,
        maxUploadDelay: 0.05,
        uploadDelayChangeRate: 0,
        maxBatchesPerUpload: 10
    )

    /// Optimized for performing very fast first upload and then changing to unrealistically long intervals.
    public static let veryQuickInitialUpload = UploadPerformanceMock(
        initialUploadDelay: 0.05,
        minUploadDelay: 60,
        maxUploadDelay: 60,
        uploadDelayChangeRate: 60 / 0.05,
        maxBatchesPerUpload: 10
    )
}

extension UploadPerformanceMock {
    public init(other: UploadPerformancePreset) {
        initialUploadDelay = other.initialUploadDelay
        minUploadDelay = other.minUploadDelay
        maxUploadDelay = other.maxUploadDelay
        uploadDelayChangeRate = other.uploadDelayChangeRate
        maxBatchesPerUpload = other.maxBatchesPerUpload
        maxUploadJitter = other.maxUploadJitter
    }
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
