/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import TestUtilities

@testable import DatadogRUM

struct FrameInfoProviderMock: FrameInfoProvider {
    var maximumDeviceFramesPerSecond: Int
    var currentFrameTimestamp: CFTimeInterval
    var nextFrameTimestamp: CFTimeInterval

    init(
        maximumDeviceFramesPerSecond: Int = 60,
        currentFrameTimestamp: CFTimeInterval = 0,
        nextFrameTimestamp: CFTimeInterval = 0
    ) {
        self.maximumDeviceFramesPerSecond = maximumDeviceFramesPerSecond
        self.currentFrameTimestamp = currentFrameTimestamp
        self.nextFrameTimestamp = nextFrameTimestamp
    }

    func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) { }
    func invalidate() { }
}

final class ViewHitchesMock: ViewHitchesMetric {
    private(set) var isActive: Bool = false
    private(set) var hitchesDataModel: HitchesDataModel

    init(hitchesDataModel: HitchesDataModel = ([], 0.0)) {
        self.hitchesDataModel = hitchesDataModel
    }
}

extension ViewHitchesMock: RenderLoopReader {
    func stop() { isActive = false }

    func didUpdateFrame(link: FrameInfoProvider) { isActive = true }
}

extension ViewHitchesMock: AnyMockable, RandomMockable {
    static func mockAny() -> Self {
        ViewHitchesMock(hitchesDataModel: ([(1, 10), (20, 10)], 100.0)) as! Self
    }

    static func mockRandom() -> Self {
        ViewHitchesMock(hitchesDataModel: (Array(repeating: (.mockAny(), .mockAny()), count: .mockAny()), .mockAny())) as! Self
    }
}
