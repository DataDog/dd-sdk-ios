/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import protocol Datadog.OTSpanContext

internal class DDSpanContextObjc: NSObject, OTSpanContext {
    let swiftSpanContext: Datadog.OTSpanContext

    internal init(swiftSpanContext: Datadog.OTSpanContext) {
        self.swiftSpanContext = swiftSpanContext
    }

    // MARK: - Open Tracing Objective-C Interface

    func forEachBaggageItem(_ callback: (_ key: String, _ value: String) -> Bool) {
        // Corresponds to:
        // - (void)forEachBaggageItem:(BOOL (^) (NSString* key, NSString* value))callback;
        swiftSpanContext.forEachBaggageItem(callback: callback)
    }
}
