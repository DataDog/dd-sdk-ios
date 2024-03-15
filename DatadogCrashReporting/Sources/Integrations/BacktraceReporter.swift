/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

internal struct BacktraceReporter: DatadogInternal.BacktraceReporting {
    let reporter: ThirdPartyCrashReporter

    func generateBacktrace(threadID: ThreadID) throws -> DatadogInternal.BacktraceReport? {
        return try reporter.generateBacktrace(threadID: threadID)
    }
}
