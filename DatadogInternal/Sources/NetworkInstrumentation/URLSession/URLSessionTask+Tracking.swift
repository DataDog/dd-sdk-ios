/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

private var sessionFirstPartyHostsKey: UInt8 = 31
internal extension URLSessionTask {
    /// Returns the first party hosts for this task.
    var firstPartyHosts: FirstPartyHosts {
        get {
            return sessionFirstPartyHosts ?? .init()
        }
    }

    /// Extension property for storing first party hosts passed from `URLSession` to `URLSessionTask`.
    /// This is used for `URLSessionTask` based APIs.
    var sessionFirstPartyHosts: FirstPartyHosts? {
        set {
            objc_setAssociatedObject(self, &sessionFirstPartyHostsKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
        }
        get {
            return objc_getAssociatedObject(self, &sessionFirstPartyHostsKey) as? FirstPartyHosts
        }
    }
}
