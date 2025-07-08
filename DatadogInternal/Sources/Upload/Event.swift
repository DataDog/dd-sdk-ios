/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Struct representing a single event.
public struct Event: Equatable {
    /// Data representing the event.
    public let data: Data

    /// Metadata associated with the event.
    /// Metadata is optional and may be `nil` but of very small size.
    /// This allows us to skip resource intensive operations in case such
    /// as filtering of the events.
    public let metadata: Data?

    public init(data: Data, metadata: Data? = nil) {
        self.data = data
        self.metadata = metadata
    }
}
