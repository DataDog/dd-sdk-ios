/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

/**
 - Parameters:
   - start: Hitch duration in ns from the start of the view
   - duration: Hitch duration in ns
 */
internal typealias Hitch = (start: Int64, duration: Int64)

/**
 - Parameters:
   - maxCollectedHitches: Max buffer size to collect view hitches
   - acceptableLatency: Lower threshold to start tracking view hitches
   - hangThreshold: Upper threshold to stop tracking view hitches
 */
internal typealias HitchesConfiguration = (maxCollectedHitches: Int, acceptableLatency: TimeInterval, hangThreshold: TimeInterval)

/**
 - Parameters:
   - hitches: Array of view hitches (slow frames)
   - hitchesDuration: Cumulative duration in seconds of the view hitches
 */
internal typealias HitchesDataModel = (hitches: [Hitch], startTimestamp: Double, hitchesDuration: Double)

internal struct HitchesTelemetryModel {
    /// Total amount of slow frames collected.
    let hitchesCount: Int
    /// Total slow frames that were outside of the min and max boundaries.
    let ignoredHitchesCount: Int
    /// Indicates that ProMotion was applied.
    let didApplyDynamicFraming: Bool
    /// Value indicating the extra duration used to calculate the slow frame rate.
    let ignoredDurationNs: Int64
}

internal protocol ViewHitchesModel {
    var config: HitchesConfiguration { get }
    var dataModel: HitchesDataModel { get }
    var telemetryModel: HitchesTelemetryModel { get }
}

/// Class that reads View Hitches or Slow frames.
internal final class ViewHitchesReader: ViewHitchesModel {
    internal enum Constants {
        static let frozenFrameThreshold: TimeInterval = 0.7 // seconds
        /// Taking into account each Hitch takes 64B in the payload, we can have 64KB max per view event
        static let maxCollectedHitches = 1_000
        /// Threshold of old hitches to remove. 10% of `maxCollectedHitches`
        static let maxHitchesThreshold = 100
        /// By default, a hitch is detected when a frame takes twice as long to render as the current refresh rate.
        static let hitchesMultiplier: Double = 2
        /// Tolerance to handle timestamp conversions. 1ms of tolerance.
        static let timestampTolerance = 0.001
    }

    /// Queue used to synchronize the access to hitch information.
    private let queue = DispatchQueue(
        label: "com.datadoghq.view-hitches-reader",
        qos: .utility
    )

    private var startTimestamp: Double = 0
    private var nextFrameTimestamp: Double?

    let config: HitchesConfiguration
    private var _isActive: Bool = false
    var isActive: Bool { queue.sync { self._isActive } }

    private var hitches: [Hitch] = []
    /// Amount of time when the frames are rendered too late.
    private var hitchesDuration: Double = 0.0
    var dataModel: HitchesDataModel { queue.sync { (hitches: self.hitches, startTimestamp: startTimestamp, hitchesDuration: self.hitchesDuration) } }

    private var removedHitchesCount = 0
    private var ignoredHitchesCount = 0
    private var startFrameRate: CFTimeInterval?
    private var didApplyDynamicFraming = false
    var telemetryModel: HitchesTelemetryModel {
        queue.sync {
            let ignoredDurationNs = hitchesDuration.toInt64Nanoseconds - hitches.reduce(into: 0) { $0 += $1.duration }

            return .init(
                hitchesCount: self.hitches.count + self.removedHitchesCount,
                ignoredHitchesCount: self.ignoredHitchesCount,
                didApplyDynamicFraming: self.didApplyDynamicFraming,
                ignoredDurationNs: ignoredDurationNs
            )
        }
    }

    init(hangThreshold: TimeInterval? = nil, acceptableLatency: TimeInterval = 0) {
        self.config = (
            maxCollectedHitches: Constants.maxCollectedHitches,
            acceptableLatency: acceptableLatency,
            hangThreshold: hangThreshold ?? Constants.frozenFrameThreshold
        )
    }
}

extension ViewHitchesReader: RenderLoopReader {
    func stop() { queue.async { self._isActive = false } }

    func didUpdateFrame(link: FrameInfoProvider) {
        queue.async {
            self._isActive = true
            // Baseline to capture View Hitches
            guard let nextFrameTimestamp = self.nextFrameTimestamp else {
                self.startTimestamp = link.currentFrameTimestamp
                self.nextFrameTimestamp = link.nextFrameTimestamp
                self.startFrameRate = link.nextFrameTimestamp - link.currentFrameTimestamp
                return
            }

            // Updated Frame rate since it can change due to ProMotion,
            // low power mode, set of preferredFramesPerSecond and whatnot
            // (60 FPS = 1/60 s)
            let idealFrameInterval = link.nextFrameTimestamp - link.currentFrameTimestamp
            if let startFrameRate = self.startFrameRate,
               abs(idealFrameInterval - startFrameRate) > Constants.timestampTolerance {
                self.didApplyDynamicFraming = true
            }

            let hitchFrameDuration = link.currentFrameTimestamp - nextFrameTimestamp
            // Every time the frame appear later than expected, the delay is collected
            // Except when the issue is tracked by App hangs
            if hitchFrameDuration < self.config.hangThreshold {
                self.hitchesDuration += max(0, hitchFrameDuration)
            }

            if (hitchFrameDuration + Constants.timestampTolerance) >= max(self.config.acceptableLatency, idealFrameInterval)
                && hitchFrameDuration < self.config.hangThreshold {
                // The buffer has reach the maximum of hitches. The oldest hitches should be removed.
                if self.hitches.count > Constants.maxCollectedHitches {
                    let arraySlice = self.hitches.dropFirst(Constants.maxHitchesThreshold)
                    self.hitches = Array(arraySlice)
                    self.removedHitchesCount += Constants.maxHitchesThreshold
                }

                let hitchStart = nextFrameTimestamp - self.startTimestamp
                self.hitches.append((hitchStart.toInt64Nanoseconds, hitchFrameDuration.toInt64Nanoseconds))
            } else if hitchFrameDuration > Constants.timestampTolerance {
                self.ignoredHitchesCount += 1
            }

            self.nextFrameTimestamp = link.nextFrameTimestamp
        }
    }
}
