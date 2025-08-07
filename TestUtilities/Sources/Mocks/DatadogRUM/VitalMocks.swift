/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

@testable import DatadogRUM

public struct FrameInfoProviderMock: FrameInfoProvider {
    public var maximumDeviceFramesPerSecond: Int
    public var currentFrameTimestamp: CFTimeInterval
    public var nextFrameTimestamp: CFTimeInterval

    public init(
        maximumDeviceFramesPerSecond: Int = 60,
        currentFrameTimestamp: CFTimeInterval = 0,
        nextFrameTimestamp: CFTimeInterval = 0
    ) {
        self.maximumDeviceFramesPerSecond = maximumDeviceFramesPerSecond
        self.currentFrameTimestamp = currentFrameTimestamp
        self.nextFrameTimestamp = nextFrameTimestamp
    }

    public func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) { }
    public func invalidate() { }
}

public final class ViewHitchesMock: ViewHitchesModel {
    public private(set) var isActive: Bool = false
    public private(set) var config: HitchesConfiguration = (100, 0, 1)
    public private(set) var dataModel: HitchesDataModel = ([], 0.0)
    public private(set) var telemetryModel: HitchesTelemetryModel = .init(
        hitchesCount: 0,
        ignoredHitchesCount: 0,
        didApplyDynamicFraming: false,
        ignoredDurationNs: 0
    )

    public init(hitchesDataModel: HitchesDataModel = ([], 0.0)) {
        self.dataModel = hitchesDataModel
    }
}

extension ViewHitchesMock: RenderLoopReader {
    public func stop() { isActive = false }

    public func didUpdateFrame(link: FrameInfoProvider) { isActive = true }
}

extension ViewHitchesMock: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        ViewHitchesMock(hitchesDataModel: ([(1, 10), (20, 10)], 100.0)) as! Self
    }

    public static func mockRandom() -> Self {
        ViewHitchesMock(hitchesDataModel: (Array(repeating: (.mockAny(), .mockAny()), count: .mockAny()), .mockAny())) as! Self
    }
}

extension RUMFeatureOperationFailureReason: AnyMockable, RandomMockable {
    private static var allCases: [RUMFeatureOperationFailureReason]
        = [.error, .abandoned, .other]

    public static func mockAny() -> Self {
        return .error
    }

    public static func mockRandom() -> Self {
        return RUMFeatureOperationFailureReason.allCases.randomElement()!
    }
}
