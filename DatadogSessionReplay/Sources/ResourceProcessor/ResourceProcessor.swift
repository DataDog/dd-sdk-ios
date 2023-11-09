/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

internal protocol ResourceProcessing {
    func process(resources: [Resource])
}

internal class ResourceProcessor: ResourceProcessing {
    /// The background queue for executing all logic.
    private let queue: Queue
    /// Writes records to `DatadogCore`.
    private let writer: Writing
    /// Sends telemetry through sdk core.
    private let telemetry: Telemetry

    func process(resources: [Resource]) {
        queue.run { [writer] in
            Set(resources.map(CodableResource.init))
                .forEach(writer.write(resource:))
        }
    }

    init(queue: Queue, writer: Writing, telemetry: Telemetry) {
        self.queue = queue
        self.writer = writer
        self.telemetry = telemetry
    }
}

struct CodableResource: Codable, Hashable, Resource {
    var identifier: String
    var data: Data

    init(resource: Resource) {
        self.identifier = resource.identifier
        self.data = resource.data
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}
#endif
