/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit

/// A class reading the refresh rate (frames per second) of the main screen
internal class VitalRefreshRateReader: ContinuousVitalReader {
    private static var backendSupportedFrameRate = 60.0

    private var valuePublishers: [VitalPublisher] = []

    private var lastFrameTimestamp: CFTimeInterval?
    private var nextFrameDuration: CFTimeInterval?

    /// `VitalRefreshRateReader` keeps pushing data to its `observers` at every new frame.
    /// - Parameter observer: receiver of refresh rate per frame.
    func register(_ valuePublisher: VitalPublisher) {
        DispatchQueue.main.async {
            self.valuePublishers.append(valuePublisher)
        }
    }

    /// `VitalRefreshRateReader` stops pushing data to `observer` once unregistered.
    /// - Parameter observer: already added observer; otherwise nothing happens.
    func unregister(_ valuePublisher: VitalPublisher) {
        DispatchQueue.main.async {
            self.valuePublishers.removeAll { existingPublisher in
                return existingPublisher === valuePublisher
            }
        }
    }
}

extension VitalRefreshRateReader: RenderLoopReader {
    var isActive: Bool { lastFrameTimestamp != nil }

    func stop() {
        lastFrameTimestamp = nil
    }

    func didUpdateFrame(link: FrameInfoProvider) {
        if let fps = framesPerSecond(provider: link) {
            valuePublishers.forEach {
                $0.mutateAsync { currentInfo in
                    currentInfo.addSample(fps)
                }
            }
        }
    }

    func framesPerSecond(provider: FrameInfoProvider) -> Double? {
        var fps: Double? = nil

        if let lastFrameTimestamp {
            let currentFrameDuration = provider.currentFrameTimestamp - lastFrameTimestamp
            guard currentFrameDuration > 0 else {
                return nil
            }
            let currentFPS = 1.0 / currentFrameDuration

            // ProMotion displays (e.g. iPad Pro and newer iPhone Pro) can have refresh rate higher than 60 FPS.
            if let expectedCurrentFrameDuration = self.nextFrameDuration, provider.adaptiveFrameRateSupported {
                guard expectedCurrentFrameDuration > 0 else {
                    return nil
                }
                let expectedFPS = 1.0 / expectedCurrentFrameDuration
                let normalizedFPS = currentFPS * (Self.backendSupportedFrameRate / expectedFPS)
                fps = min(normalizedFPS, Self.backendSupportedFrameRate)
            } else {
                fps = currentFPS
            }
        }

        self.lastFrameTimestamp = provider.currentFrameTimestamp
        self.nextFrameDuration = provider.nextFrameTimestamp - provider.currentFrameTimestamp

        return fps
    }
}
