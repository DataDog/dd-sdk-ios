/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

private var coreKey: UInt8 = 43

public extension URLSessionDelegate {
     /// Returns the `DatadogCore` for this delegate.
    weak var core: DatadogCoreProtocol? {
        set {
            objc_setAssociatedObject(self, &coreKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_ASSIGN)
        }
        get {
            return objc_getAssociatedObject(self, &coreKey) as? DatadogCoreProtocol
        }
    }

    /// Returns the `URLSessionInterceptor` for this delegate.
    var interceptor: URLSessionInterceptor? {
        let core = self.core ?? CoreRegistry.default
        return URLSessionInterceptor.shared(in: core)
    }
}
