/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

@testable import DatadogSessionReplay

final class TestRepeatingTimer: RepeatingTimer {
    private(set) var isRunning = false
    private var handler: (() -> Void)?

    func start(interval: TimeInterval, handler: @escaping () -> Void) {
        self.handler = handler
        isRunning = true
    }

    func stop() {
        handler = nil
        isRunning = false
    }

    func tick() {
        handler?()
    }
}
#endif
