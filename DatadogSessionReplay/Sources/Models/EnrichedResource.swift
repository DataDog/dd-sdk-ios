/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

/// Extends the resource information with context.
internal struct EnrichedResource: Codable, Equatable {
    internal struct Context: Codable, Equatable {
        internal struct Application: Codable, Equatable {
            let id: String
        }
        let type: String
        let application: Application

        init(_ applicationId: String) {
            self.type = "resource"
            self.application = .init(id: applicationId)
        }
    }
    internal var identifier: String
    internal var data: Data
    internal var mimeType: String
    internal var context: Context

    internal init(
        identifier: String,
        data: Data,
        mimeType: String,
        context: Context
    ) {
        self.identifier = identifier
        self.data = data
        self.mimeType = mimeType
        self.context = context
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.identifier = try container.decode(String.self, forKey: .identifier)
        self.data = try container.decode(Data.self, forKey: .data)
        self.context = try container.decode(EnrichedResource.Context.self, forKey: .context)

        // Maintain backward compatibility:
        // Before introducing `mimeType` all resources where PNG images
        self.mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType) ?? "image/png"
    }
}
#endif
