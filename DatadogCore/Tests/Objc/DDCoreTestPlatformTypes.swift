/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@_spi(objc)
@testable import DatadogRUM

#if os(macOS)
typealias objc_ViewsPredicate = objc_AppKitRUMViewsPredicate
typealias objc_DefaultViewsPredicate = objc_DefaultAppKitRUMViewsPredicate
typealias ViewsPredicate = AppKitRUMViewsPredicateBridge
#elseif !os(watchOS)
typealias objc_ViewsPredicate = objc_UIKitRUMViewsPredicate
typealias objc_DefaultViewsPredicate = objc_DefaultUIKitRUMViewsPredicate
typealias ViewsPredicate = UIKitRUMViewsPredicateBridge
#endif
