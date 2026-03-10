/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

internal final class ResourceProcessor {
    struct Input {
        let resources: [Resource]
        let context: EnrichedResource.Context
    }

    private let resourcesWriter: any ResourcesWriting
    private var processedIdentifiers = Set<String>()

    init(resourcesWriter: ResourcesWriting) {
        self.resourcesWriter = resourcesWriter
    }

    func process(_ input: Input) {
        let resources = input.resources
            .compactMap {
                let identifier = $0.calculateIdentifier()
                let isProcessed = processedIdentifiers.contains(identifier)
                if !isProcessed {
                    processedIdentifiers.insert(identifier)
                }
                return !isProcessed ? EnrichedResource(
                    identifier: identifier,
                    data: $0.calculateData(),
                    mimeType: $0.mimeType,
                    context: input.context
                ) : nil
            }
        guard !resources.isEmpty else {
            return
        }
        resourcesWriter.write(resources: resources)
    }
}

internal protocol ResourceProcessing {
    func process(resources: [Resource], context: EnrichedResource.Context)
}

internal class ResourceProcessorQueue: ResourceProcessing {
    /// Interception callback for snapshot tests.
    /// Only available in Debug configuration, solely made for testing purpose.
    var interceptResources: (([Resource]) -> Void)? = nil

    private let queue: Queue
    private let processor: ResourceProcessor

    func process(resources: [Resource], context: EnrichedResource.Context) {
        interceptResources?(resources)
        queue.run { [processor] in
            processor.process(.init(resources: resources, context: context))
        }
    }

    init(queue: Queue, resourcesWriter: ResourcesWriting) {
        self.queue = queue
        self.processor = ResourceProcessor(resourcesWriter: resourcesWriter)
    }
}
#endif
