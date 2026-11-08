/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit
import SwiftUI
import Combine
@testable import TestUtilities
@_spi(Internal)
@testable import DatadogInternal
@_spi(Internal)
@testable import DatadogCore
@testable import DatadogRUM

#if os(iOS) && canImport(SwiftUI)
extension SwiftUINavigationOwnershipTests {
    private enum NavigationSourceRoute: Hashable {
        case home
        case detail(secret: String)
    }




    private struct NavigationSourceReentrantValue: Hashable {
        let value: Int
        let onEquality: () -> Void
        let onHash: () -> Void

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.onEquality()
            return lhs.value == rhs.value
        }

        func hash(into hasher: inout Hasher) {
            onHash()
            hasher.combine(value)
        }
    }


}
#endif
