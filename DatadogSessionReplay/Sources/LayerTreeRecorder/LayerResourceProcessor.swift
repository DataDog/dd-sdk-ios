/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Resource-processing adapter for the layer-tree recording pipeline.
//
// The layer pipeline runs with async processors (`AsyncProcessor`) instead of the
// queue-based infrastructure. This file bridges the shared `ResourceProcessor`
// logic to the async pipeline by exposing a dedicated protocol for dependency
// injection from `LayerSnapshotProcessor`.

#if os(iOS)
import Foundation

@available(iOS 13.0, tvOS 13.0, *)
extension ResourceProcessor: Processor {
}

@available(iOS 13.0, tvOS 13.0, *)
internal protocol LayerResourceProcessing {
    /// Processes resources produced by one layer snapshot frame.
    func process(_ input: ResourceProcessor.Input) async
}

@available(iOS 13.0, tvOS 13.0, *)
extension AsyncProcessor: LayerResourceProcessing where Input == ResourceProcessor.Input {
}
#endif
