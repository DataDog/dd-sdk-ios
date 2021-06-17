/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import UIKit

/// A class reading the refresh rate (frames per second) of the main screen
internal class VitalRefreshRateReader {
    private var observers = [VitalObserver]()
    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval?
    private(set) var isRunning = false

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
    }

    deinit {
        stop()
    }

    /// `VitalRefreshRateReader` keeps pushing data to its `observers` at every new frame.
    /// - Parameter observer: receiver of refresh rate per frame.
    func register(_ observer: VitalObserver) {
        DispatchQueue.main.async {
            self.observers.append(observer)
        }
    }

    /// `VitalRefreshRateReader` stops pushing data to `observer` once unregistered.
    /// - Parameter observer: already added observer; otherwise nothing happens.
    func unregister(_ observer: VitalObserver) {
        DispatchQueue.main.async {
            self.observers.removeAll { existingObserver in
                return existingObserver === observer
            }
        }
    }

    /// Starts listening to frame paints.
    /// - Throws: only if `UIScreen.main` cannot generate its `CADisplayLink`
    func start() throws {
        try private_start()
        isRunning = true
    }

    /// Stops listening frame paints. Automatically called at `deinit()`.
    func stop() {
        private_stop()
        isRunning = false
    }

    // MARK: - Private

    @objc
    private func displayTick(link: CADisplayLink) {
        if let lastTimestamp = self.lastFrameTimestamp {
            let frameDuration = link.timestamp - lastTimestamp
            let currentFPS = 1.0 / frameDuration
            // NOTE: RUMM-1278 `oldValue` is not used
            observers.forEach {
                $0.onValueChanged(oldValue: 0.0, newValue: currentFPS)
            }
        }
        lastFrameTimestamp = link.timestamp
    }

    @objc
    private func appWillResignActive() {
        private_stop()
    }

    @objc
    private func appDidBecomeActive() {
        if isRunning {
            try? private_start()
        }
    }

    private func private_start() throws {
        stop()

        guard let link = UIScreen.main.displayLink(
            withTarget: self,
            selector: #selector(displayTick(link:))
        ) else {
            throw InternalError(description: "CADisplayLink could not be created!")
        }
        link.add(to: .main, forMode: .default)
        self.displayLink = link
    }

    private func private_stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastFrameTimestamp = nil
    }
}
