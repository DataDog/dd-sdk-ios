/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
@testable import DatadogCore
@testable import DatadogTrace

extension AppRunner {
    /// The currently active span, pinned to runner state so it survives across closure boundaries.
    /// Backed by `state["activeSpan"]`.
    var activeSpan: OTSpan? {
        get { state["activeSpan"] as? OTSpan }
        set { state["activeSpan"] = newValue }
    }

    typealias TraceSetup = (inout Trace.Configuration) -> Void

    /// Enables Trace feature on the SDK core.
    func enableTrace(_ traceSetup: TraceSetup = { _ in }) {
        var config = Trace.Configuration()
        traceSetup(&config)
        Trace.enable(with: config, in: core)
    }
}
