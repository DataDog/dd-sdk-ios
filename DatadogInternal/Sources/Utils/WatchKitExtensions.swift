/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

#if canImport(WatchKit)
import WatchKit

extension DatadogExtension where ExtendedType == WKExtension {
    public static var shared: WKExtension {
        .shared()
    }
}

extension WKExtension: DatadogExtended { }
#endif
