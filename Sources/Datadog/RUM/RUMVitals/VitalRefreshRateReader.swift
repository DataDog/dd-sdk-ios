/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit

/// A class reading the refresh rate (frames per second) of the main screen
internal class VitalRefreshRateReader: ContinuousVitalReader {
    private var valuePublishers = [VitalPublisher]()

    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval?
    private var nextFrameDuration: CFTimeInterval?
    private static var backendSupportedFrameRate = 60.0

    init(notificationCenter: NotificationCenter = .default) {
        notificationCenter.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        start()
    }

    deinit {
        stop()
    }

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

    // MARK: - Internal

    internal func framesPerSecond(provider: FrameInfoProvider) -> Double? {
        var fps: Double? = nil

        if let lastFrameTimestamp = self.lastFrameTimestamp {
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
                fps = currentFPS * (Self.backendSupportedFrameRate / expectedFPS)
            } else {
                fps = currentFPS
            }
        }

        self.lastFrameTimestamp = provider.currentFrameTimestamp
        self.nextFrameDuration = provider.nextFrameTimestamp - provider.currentFrameTimestamp

        return fps
    }

    // MARK: - Private

    @objc
    private func displayTick(link: CADisplayLink) {
        guard let fps = framesPerSecond(provider: link) else {
            return
        }

        for publisher in valuePublishers {
            publisher.mutateAsync { currentInfo in
                currentInfo.addSample(fps)
            }
        }
    }

    private func start() {
        guard displayLink == nil else {
            return
        }

        displayLink = CADisplayLink(target: self, selector: #selector(displayTick(link:)))
        // NOTE: RUMM-1544 `.default` mode doesn't get fired while scrolling the UI, `.common` does.
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastFrameTimestamp = nil
    }

    @objc
    private func appWillResignActive() {
        stop()
    }

    @objc
    private func appDidBecomeActive() {
        start()
    }
}

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
}

private let adaptiveFrameRateThreshold = 60
extension FrameInfoProvider {
    /// `true` if the device supports adaptive frame rate
    var adaptiveFrameRateSupported: Bool {
        maximumDeviceFramesPerSecond > adaptiveFrameRateThreshold
    }
}

extension CADisplayLink: FrameInfoProvider {
    var maximumDeviceFramesPerSecond: Int {
        #if os(xrOS)
        120
        #else
        UIScreen.main.maximumFramesPerSecond
        #endif
    }

    var currentFrameTimestamp: CFTimeInterval {
        timestamp
    }

    var nextFrameTimestamp: CFTimeInterval {
        targetTimestamp
    }
}
