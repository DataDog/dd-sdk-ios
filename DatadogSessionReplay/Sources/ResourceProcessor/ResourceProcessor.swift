/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

internal protocol ResourceProcessing {
    func process(resources: [Resource], context: CodableResource.Context)
}

internal class ResourceProcessor: ResourceProcessing {
    /// The background queue for executing all logic.
    private let queue: Queue
    /// Writes records to `DatadogCore`.
    private let writer: Writing
    /// Sends telemetry through sdk core.
    private let telemetry: Telemetry

    func process(resources: [Resource], context: CodableResource.Context) {
        queue.run { [writer] in
            Set(resources.map { CodableResource(resource: $0, context: context) })
                .forEach(writer.write(resource:))
        }
    }

    init(queue: Queue, writer: Writing, telemetry: Telemetry) {
        self.queue = queue
        self.writer = writer
        self.telemetry = telemetry
    }
}

internal struct CodableResource: Codable, Hashable, Resource {
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

    internal init(resource: Resource, context: Context) {
        self.identifier = resource.identifier
        self.data = resource.data
        self.context = context
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}
#endif
