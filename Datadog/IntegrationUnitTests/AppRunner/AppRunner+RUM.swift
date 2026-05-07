/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import TestUtilities
@testable import DatadogCore
@testable import DatadogRUM

extension AppRunner {
    typealias RUMSetup = (inout RUM.Configuration) -> Void

    /// Enables RUM with optional configuration.
    func enableRUM(_ rumSetup: RUMSetup = { _ in }) {
        var config = RUM.Configuration(applicationID: "mock-application-id")
        config.dateProvider = dateProvider
        config.mediaTimeProvider = MediaTimeProviderMock(current: 0)
        config.notificationCenter = notificationCenter
        #if !os(watchOS)
        config.frameInfoProviderFactory = { [weak self] in
            let frameInfoProvider = FrameInfoProviderMock(target: $0, selector: $1)
            self?.frameInfoProvider = frameInfoProvider
            return frameInfoProvider
        }
        #endif
        rumSetup(&config)
        RUM.enable(with: config, in: core)
    }

    /// Provides convenient access to the current `RUMMonitor`.
    var rum: RUMMonitorProtocol { RUMMonitor.shared(in: core) }

    /// Simulates the first frame of an app launch.
    func displayFirstFrame(after interval: TimeInterval) {
        #if !os(watchOS)
        self.frameInfoProvider.triggerCallback(interval: interval)
        #endif
    }

    #if !os(watchOS)
    /// Simulates `viewDidAppear()` for a given view controller.
    /// If another view controller had previously appeared, it will automatically simulate `viewDidDisappear()` for it.
    func viewDidAppear(vc: UIViewController) {
        if let lastAppearedViewController {
            viewDidDisappear(vc: lastAppearedViewController)
        }
        vc.viewDidAppear(true)
        lastAppearedViewController = vc
    }

    /// Simulates `viewDidDisappear()` for a given view controller.
    func viewDidDisappear(vc: UIViewController) {
        vc.viewDidDisappear(true)
        if lastAppearedViewController === vc {
            lastAppearedViewController = nil
        }
    }
    #endif

    /// Returns grouped RUM sessions recorded during the test.
    /// - Returns: An array of `RUMSessionMatcher` grouped by `session.id`.
    func recordedRUMSessions() throws -> [RUMSessionMatcher] {
        return try RUMSessionMatcher.groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
    }
}
