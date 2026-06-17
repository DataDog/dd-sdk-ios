/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

@available(iOS 13.0, tvOS 13.0, *)
extension NSObject {
    static func makeCAFilter(type: String) throws -> NSObject {
        guard
            let filterClass = NSClassFromString("CAFilter"),
            let filter = (filterClass as AnyObject).perform(
                NSSelectorFromString("filterWithType:"),
                with: type
            )?
            .takeUnretainedValue() as? NSObject
        else {
            struct CAFilterNotFound: Error {}
            throw CAFilterNotFound()
        }

        filter.perform(NSSelectorFromString("setDefaults"))
        return filter
    }
}
#endif
