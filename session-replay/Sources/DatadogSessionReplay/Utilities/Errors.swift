/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// An exception thrown by the SDK.
/// It is always handled by SDK (keeps it functional) and never passed to the user unless SDK verbosity is configured (then it might be printed in debugger console).
/// `InternalError` might be thrown due to programmer error (API misuse) or SDK internal inconsistency or external issues (e.g.  I/O errors).
/// The SDK should always recover from these failures.
internal struct InternalError: Error, CustomStringConvertible {
    let description: String
}
