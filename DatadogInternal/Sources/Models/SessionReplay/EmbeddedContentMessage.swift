/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Session Replay data produced by an embedded renderer.
public enum EmbeddedContentMessage {
    /// A batch of serialized Session Replay records.
    public struct RecordBatch {
        /// A single serialized Session Replay record.
        public typealias Record = [String: Any]

        /// The serialized Session Replay records.
        public let records: [Record]

        /// The identifier shared with the native view hosting the embedded content.
        public let slotID: String

        /// The RUM view identifier associated with the records.
        public let viewID: String

        /// Creates a batch of embedded Session Replay records.
        public init(records: [Record], slotID: String, viewID: String) {
            self.records = records
            self.slotID = slotID
            self.viewID = viewID
        }
    }

    /// An encoded resource referenced by embedded Session Replay records.
    public struct Resource {
        /// The content identifier referenced by Session Replay records.
        public let identifier: String

        /// The encoded resource bytes.
        public let data: Data

        /// The resource media type.
        public let mimeType: String

        /// Creates an embedded Session Replay resource.
        public init(identifier: String, data: Data, mimeType: String) {
            self.identifier = identifier
            self.data = data
            self.mimeType = mimeType
        }
    }

    /// A batch of records associated with an embedded native container.
    case records(RecordBatch)

    /// A resource referenced by embedded Session Replay records.
    case resource(Resource)
}
