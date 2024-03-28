/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A snapshot of all running threads in the current process. It focuses on tracing back from the error point (where backtrace
/// generation started) to the root cause or the origin of the problem.
///
/// - Unlike `DDCrashReport`, the backtrace report can be generated on-demand without the actual crash being triggered.
/// - Like in `DDCrashReport`, threads and stacks information in `BacktraceReport` follows the format compatible with Datadog symbolication.
public struct BacktraceReport: Codable {
    /// The stack trace of the thread for which the backtrace is generated.
    public let stack: String
    /// Represents all threads currently running in the process.
    public let threads: [DDThread]
    /// A list of binary images referenced from all stack traces.
    public let binaryImages: [BinaryImage]
    /// Indicates whether any stack trace information in `threads` was truncated due to stack trace minimization.
    public let wasTruncated: Bool

    /// Initializes a new instance of `BacktraceReport`.
    /// - Parameters:
    ///   - stack: The stack trace of the thread.
    ///   - threads: All threads currently running in the process.
    ///   - binaryImages: A list of binary images referenced from all stack traces.
    ///   - wasTruncated: Indicates whether stack trace information was truncated.
    public init(
        stack: String,
        threads: [DDThread],
        binaryImages: [BinaryImage],
        wasTruncated: Bool
    ) {
        self.stack = stack
        self.threads = threads
        self.binaryImages = binaryImages
        self.wasTruncated = wasTruncated
    }
}
