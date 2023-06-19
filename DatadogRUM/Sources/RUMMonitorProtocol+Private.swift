/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

/// An internal interface of RUM monitor.
///
/// Unlike public `RUMMonitorProtocol` dedicated for actual users,
/// it abstracts the RUM monitor with extra methods for internal working.
internal protocol RUMMonitorInternalProtocol: AnyObject {
    /// Performs initial work in RUM monitor.
    func notifySDKInit()

    func addError(
        message: String,
        type: String?,
        stack: String?,
        source: RUMInternalErrorSource,
        attributes: [AttributeKey: AttributeValue]
    )

    /// Completes all asynchronous operations with blocking the caller thread.
    func flush()
}
