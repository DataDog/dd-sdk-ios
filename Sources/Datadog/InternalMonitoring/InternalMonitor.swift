/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Bundles internal monitoring tools, adding observability to the `dd-sdk-ios`.
internal struct InternalMonitor {
    /// The logger sending SDK monitoring & observability logs to Datadog org.
    /// **It should be used wisely to only log critical and important events**.
    let sdkLogger: Logger
}
