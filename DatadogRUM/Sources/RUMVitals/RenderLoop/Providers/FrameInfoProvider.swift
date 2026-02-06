/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
#if !os(watchOS)
import UIKit
#endif

/// Facade for `CADisplayLink` to provide frame timestamps & device information
/// It decouple FPS calculation from `CADisplayLink` implementation.
/// - Note: It allows to mock `CADisplayLink` in tests
internal protocol FrameInfoProvider {
    /// Timestamp of the current frame in seconds
    var currentFrameTimestamp: CFTimeInterval { get }

    /// Expected timestamp of the next frame in seconds
    var nextFrameTimestamp: CFTimeInterval { get }

    /// Maximum number of frames per second supported by the device
    var maximumDeviceFramesPerSecond: Int { get }

    /// Initializer of the frame info provider. It has the same signature as the `CADisplayLink` init.
    init(target: Any, selector: Selector)

    /// Adds the receiver to the given run-loop and mode. Unless paused, it will fire every vsync until removed.
    func add(to runloop: RunLoop, forMode mode: RunLoop.Mode)

    /// Removes the object from all runloop modes and releases the 'target' object.
    func invalidate()
}

extension FrameInfoProvider {
    /// Frame rate reference to assess frame rate variations
    var adaptiveFrameRateThreshold: Int { 60 }

    /// `true` if the device supports adaptive frame rate
    var adaptiveFrameRateSupported: Bool {
        maximumDeviceFramesPerSecond > adaptiveFrameRateThreshold
    }
}

#if !os(watchOS)
extension CADisplayLink: FrameInfoProvider {
    var maximumDeviceFramesPerSecond: Int {
        #if swift(>=5.9) && os(visionOS)
        // Hardcoded as for now there's no good way of extracting maximum FPS on VisionOS
        // https://developer.apple.com/documentation/visionos/analyzing-the-performance-of-your-visionos-app#Inspect-frame-rendering-performance
        90
        #else
        UIScreen.main.maximumFramesPerSecond
        #endif
    }

    var currentFrameTimestamp: CFTimeInterval { timestamp }

    var nextFrameTimestamp: CFTimeInterval { targetTimestamp }
}
#else

/// No-op implementation of FrameInfoProvider
internal final class NOPFrameInfoProvider: FrameInfoProvider {
    var currentFrameTimestamp: CFTimeInterval { 0 }
    var nextFrameTimestamp: CFTimeInterval { 0 }
    var maximumDeviceFramesPerSecond: Int { 60 }

    required init(target: Any, selector: Selector) {
        // no-op
    }

    func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) {
        // no-op
    }

    func invalidate() {
        // no-op
    }
}
#endif
