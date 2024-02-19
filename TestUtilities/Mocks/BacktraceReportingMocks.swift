/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

public struct BacktraceReporterMock: BacktraceReporting {
    public var backtrace: BacktraceReport?

    public init(backtrace: BacktraceReport? = .mockAny()) {
        self.backtrace = backtrace
    }

    public func generateBacktrace() -> BacktraceReport? {
        return backtrace
    }
}
