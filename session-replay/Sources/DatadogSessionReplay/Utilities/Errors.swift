/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An exception thrown by the SDK.
/// It is always handled by SDK (keeps it functional) and never passed to the user unless SDK verbosity is configured (then it might be printed in debugger console).
/// `InternalError` might be thrown due to programmer error (API misuse) or SDK internal inconsistency or external issues (e.g.  I/O errors).
/// The SDK should always recover from these failures (if it can not, `FatalError` should be used).
internal struct InternalError: Error, CustomStringConvertible {
    let description: String

    init(description: String, fileID: StaticString = #fileID, line: UInt = #line) {
        self.description = "\(description) (\(fileID):\(line))"
    }
}

/// An exception thrown by the SDK.
/// Denotes situation that cannot be handled by the SDK to keep itself functional.
/// It must be printed to debugger console (bypassing any SDK verbosity configuration) to notify the user that SDK is not working.
internal struct FatalError: Error, CustomStringConvertible {
    let description: String

    init(description: String, fileID: StaticString = #fileID, line: UInt = #line) {
        self.description = "🔥 Datadog Session Replay error: \(description) (\(fileID):\(line))"
    }
}
