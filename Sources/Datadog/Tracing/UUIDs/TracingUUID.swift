/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct TracingUUID: Equatable, Hashable {
    /// The unique integer (64-bit unsigned) ID of the trace containing this span.
    /// - See also: [Datadog API Reference - Send Traces](https://docs.datadoghq.com/api/?lang=bash#send-traces)
    private let rawValue: UInt64

    internal init?(_ string: String?, _ representation: Representation) {
        guard let string = string else {
            return nil
        }
        switch representation {
        case .decimal:
            guard let rawValue = UInt64(string) else {
                return nil
            }
            self.init(rawValue: rawValue)
        case .hexadecimal:
            guard let rawValue = UInt64(string, radix: 16) else {
                return nil
            }
            self.init(rawValue: rawValue)
        }
    }

    internal init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    func toString(_ representation: Representation) -> String {
        switch representation {
        case .decimal:
            return String(rawValue)
        case .hexadecimal:
            return String(rawValue, radix: 16)
        }
    }
}

extension TracingUUID {
    internal enum Representation {
        case decimal, hexadecimal
    }
}

internal typealias TraceID = TracingUUID
internal typealias SpanID = TracingUUID
