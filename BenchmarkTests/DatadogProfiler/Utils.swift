/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal func debug(_ log: @autoclosure () -> String) {
#if DEBUG
    print("⏱️ [PROFILER] \(log())")
#endif
}

internal struct ProfilerError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String = #function) {
        self.description = description
    }
}

internal let mainQueue: DispatchQueue = .main

internal extension Double {
    /// Formats bytes as kilobytes string.
    var bytesAsPrettyKB: String {
        let kB = Int(rounded() / 1_024)
        return "\(kB) kB"
    }
}
