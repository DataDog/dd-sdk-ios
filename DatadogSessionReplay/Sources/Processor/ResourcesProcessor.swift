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
    /// Interception callback for snapshot tests.
    /// Only available in Debug configuration, solely made for testing purpose.
    var interceptResources: (([Resource]) -> Void)? = nil

    private let queue: Queue
    private let resourcesWriter: ResourcesWriting

    private var processedIdentifiers = Set<String>()

    func process(resources: [Resource], context: EnrichedResource.Context) {
        interceptResources?(resources)
        queue.run { [weak self] in
            guard let self = self else {
                return
            }

            let resources = resources
                .compactMap { resource -> EnrichedResource? in
                    let identifier = resource.calculateIdentifier()
                    guard !identifier.isEmpty, !self.processedIdentifiers.contains(identifier) else {
                        return nil
                    }

                    let data = resource.calculateData()
                    // Avoid uploading empty resources
                    guard !data.isEmpty else {
                        return nil
                    }

                    self.processedIdentifiers.insert(identifier)

                    return EnrichedResource(
                        identifier: identifier,
                        data: data,
                        mimeType: resource.mimeType,
                        context: context
                    )
                }
            guard !resources.isEmpty else {
                return
            }
            self.resourcesWriter.write(resources: resources)
        }
    }

    init(queue: Queue, resourcesWriter: ResourcesWriting) {
        self.queue = queue
        self.resourcesWriter = resourcesWriter
    }
}
#endif
