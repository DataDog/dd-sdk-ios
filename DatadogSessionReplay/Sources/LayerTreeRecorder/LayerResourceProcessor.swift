/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

@available(iOS 13.0, tvOS 13.0, *)
extension ResourceProcessor: Processor {
}

@available(iOS 13.0, tvOS 13.0, *)
internal protocol LayerResourceProcessing {
    func process(_ input: ResourceProcessor.Input) async
}

@available(iOS 13.0, tvOS 13.0, *)
extension AsyncProcessor: LayerResourceProcessing where Input == ResourceProcessor.Input {
}
#endif
