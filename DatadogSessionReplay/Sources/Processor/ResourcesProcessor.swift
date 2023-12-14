/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

internal protocol ResourceProcessing {
    func process(resources: [Resource], context: EnrichedResource.Context)
}

internal class ResourceProcessor: ResourceProcessing {
    private let queue: Queue
    private let resourcesWriter: ResourcesWriting

    func process(resources: [Resource], context: EnrichedResource.Context) {
        queue.run { [resourcesWriter] in
            resourcesWriter.write(resources: Set(resources.map { EnrichedResource(resource: $0, context: context) }))
        }
    }

    init(queue: Queue, resourcesWriter: ResourcesWriting) {
        self.queue = queue
        self.resourcesWriter = resourcesWriter
    }
}
#endif
