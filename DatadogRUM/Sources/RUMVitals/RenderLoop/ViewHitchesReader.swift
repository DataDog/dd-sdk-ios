/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

/**
 - parameters:
   - start: Hitch duration in ns from the start of the view
   - duration: Hitch duration in ns
 */
internal typealias Hitch = (start: Int64, duration: Int64)
/**
 - parameters:
   - hitches: Array of view hitches (slow frames)
   - hitchesDuration: Cumulative duration in ms of the view hitches
 */
internal typealias HitchesDataModel = (hitches: [Hitch], hitchesDuration: Double)

internal protocol ViewHitchesMetric {
    var hitchesDataModel: HitchesDataModel { get }
}

/// Class that reads View Hitches or Slow frames.
internal final class ViewHitchesReader: ViewHitchesMetric {
    internal enum Constants {
        static let frozenFrameThreshold: TimeInterval = 0.7 // seconds
        /// Taking into account each Hitch takes 64B in the payload, we can have 64KB max per view event
        static let maxCollectedHitches = 1_000
        /// Threshold of old hitches to remove. 10% of `maxCollectedHitches`
        static let maxHitchesThreshold = 100
    }

    /// Queue used to synchronize the access to hitch information.
    private let queue = DispatchQueue(
        label: "com.datadoghq.view-hitches-reader",
        qos: .utility
    )

    private var startTimestamp: Double = 0
    private var nextFrameTimestamp: Double?

    private var hangThreshold: TimeInterval
    private var acceptableLatency: TimeInterval

    /// Amount of time when the frames are rendered too late.
    private var _hitchesDuration: Double = 0.0
    private var _hitches: [Hitch] = []
    var hitchesDataModel: HitchesDataModel { queue.sync { (hitches: self._hitches, hitchesDuration: self._hitchesDuration) } }

    init(hangThreshold: TimeInterval? = nil, acceptableLatency: TimeInterval = 0) {
        self.hangThreshold = hangThreshold ?? Constants.frozenFrameThreshold
        self.acceptableLatency = acceptableLatency
    }
}

extension ViewHitchesReader: RenderLoopReader {
    var isActive: Bool { queue.sync { self.nextFrameTimestamp != nil } }

    func stop() {
        queue.async {
            self.startTimestamp = 0
            self.nextFrameTimestamp = nil

            self._hitchesDuration = 0
            self._hitches.removeAll()
        }
    }

    func didUpdateFrame(link: FrameInfoProvider) {
        queue.async {
            // Baseline to capture View Hitches
            guard let nextFrameTimestamp = self.nextFrameTimestamp else {
                self.startTimestamp = link.currentFrameTimestamp
                self.nextFrameTimestamp = link.nextFrameTimestamp
                return
            }

            // Updated Frame rate since it can change due to ProMotion,
            // low power mode, set of preferredFramesPerSecond and whatnot
            // (60 FPS = 1/60 s)
            let idealFrameInterval = link.nextFrameTimestamp - link.currentFrameTimestamp

            let hitchFrameDuration = link.currentFrameTimestamp - nextFrameTimestamp
            // Every time the frame appear later than expected, the delay is collected
            self._hitchesDuration += max(0, hitchFrameDuration)

            if hitchFrameDuration >= max(self.acceptableLatency, idealFrameInterval)
                && hitchFrameDuration < self.hangThreshold {
                // The buffer has reach the maximum of hitches. The oldest hitches should be removed.
                if self._hitches.count > Constants.maxCollectedHitches {
                    let arraySlice = self._hitches.dropFirst(Constants.maxHitchesThreshold)
                    self._hitches = Array(arraySlice)
                }

                let hitchStart = nextFrameTimestamp - self.startTimestamp
                self._hitches.append((hitchStart.toInt64Nanoseconds, hitchFrameDuration.toInt64Nanoseconds))
            }

            self.nextFrameTimestamp = link.nextFrameTimestamp
        }
    }
}
