/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Abstraction for obtaining the root `CALayer` to capture.
//
// This keeps layer-tree recording decoupled from app/window discovery details and
// makes the recorder easy to test with custom providers.

#if os(iOS)
import Foundation
import QuartzCore

@available(iOS 13.0, tvOS 13.0, *)
internal protocol LayerProvider {
    @MainActor var rootLayer: CALayer? { get }
}

@available(iOS 13.0, tvOS 13.0, *)
extension KeyWindowObserver: LayerProvider {
    var rootLayer: CALayer? {
        relevantWindow?.layer
    }
}
#endif
