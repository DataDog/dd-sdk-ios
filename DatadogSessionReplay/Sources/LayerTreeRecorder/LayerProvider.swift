/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore
import UIKit

/// Provides the root layer for a layer tree capture.
internal protocol LayerProvider {
    @MainActor var rootLayer: CALayer? { get }
}

extension KeyWindowObserver: LayerProvider {
    var rootLayer: CALayer? {
        relevantWindow?.layer
    }
}
#endif
