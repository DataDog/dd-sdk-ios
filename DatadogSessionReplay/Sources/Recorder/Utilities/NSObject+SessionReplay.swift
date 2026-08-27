/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
@preconcurrency import DatadogInternal

extension NSObject {
    func safeValue(forKey key: String) -> Any? {
        try? objc_rethrow {
            value(forKey: key)
        }
    }
}
#endif
