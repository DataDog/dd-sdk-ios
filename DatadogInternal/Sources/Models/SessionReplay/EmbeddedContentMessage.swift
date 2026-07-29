/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Session Replay records produced by an embedded renderer.
public struct EmbeddedContentMessage {
    /// A single serialized Session Replay record.
    public typealias Record = [String: Any]

    /// The serialized Session Replay records.
    public let records: [Record]

    /// The identifier shared with the native view hosting the embedded content.
    public let slotID: String

    /// The RUM view identifier associated with the records.
    public let viewID: String

    /// Creates a message containing a batch of embedded Session Replay records.
    public init(records: [Record], slotID: String, viewID: String) {
        self.records = records
        self.slotID = slotID
        self.viewID = viewID
    }
}
