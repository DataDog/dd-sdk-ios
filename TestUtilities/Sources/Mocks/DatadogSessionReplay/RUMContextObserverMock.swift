/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

@testable import DatadogSessionReplay

class RUMContextObserverMock: RUMContextObserver {
    private var queue: Queue?
    private var onNew: ((RUMCoreContext?) -> Void)?

    func observe(on queue: Queue, notify: @escaping (RUMCoreContext?) -> Void) {
        self.queue = queue
        self.onNew = notify
    }

    func notify(rumContext: RUMCoreContext?) {
        queue?.run { self.onNew?(rumContext) }
    }
}
#endif
