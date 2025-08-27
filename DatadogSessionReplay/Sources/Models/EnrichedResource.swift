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
    internal var context: Context

    internal init(
        identifier: String,
        data: Data,
        context: Context
    ) {
        self.identifier = identifier
        self.data = data
        self.context = context
    }
}
#endif
