//
//  WatchKitExtensions.swift
//  Datadog
//
//  Created by Jakub Fiser on 26.06.2024.
//  Copyright © 2024 Datadog. All rights reserved.
//

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
