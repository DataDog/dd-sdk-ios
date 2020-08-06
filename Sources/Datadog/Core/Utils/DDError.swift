/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Common representation of Swift `Error` used by different features.
internal struct DDError {
    let title: String
    let message: String
    let details: String

    init(error: Error) {
        if isNSErrorOrItsSubclass(error) {
            let nsError = error as NSError
            self.title = "\(nsError.domain) - \(nsError.code)"
            if nsError.userInfo[NSLocalizedDescriptionKey] != nil {
                self.message = nsError.localizedDescription
            } else {
                self.message = nsError.description
            }
            self.details = "\(nsError)"
        } else {
            let swiftError = error
            self.title = "\(type(of: swiftError))"
            self.message = "\(swiftError)"
            self.details = "\(swiftError)"
        }
    }
}

private func isNSErrorOrItsSubclass(_ error: Error) -> Bool {
    var mirror: Mirror? = Mirror(reflecting: error)

    while mirror != nil {
        if mirror?.subjectType == NSError.self {
            return true
        }
        mirror = mirror?.superclassMirror
    }
    return false
}
