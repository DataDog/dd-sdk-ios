/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
@testable import DatadogSessionReplay

/// Spies the interaction with `Processing`.
@_spi(Internal)
public class ResourceProcessorSpy: ResourceProcessing {
    public var processedResources: [(resources: [Resource], context: EnrichedResource.Context)] = []

    public var resources: [Resource] { processedResources.reduce([]) { $0 + $1.resources } }

    public init() {}

    public func process(resources: [Resource], context: EnrichedResource.Context) {
        processedResources.append((resources: resources, context: context))
    }
}
#endif
