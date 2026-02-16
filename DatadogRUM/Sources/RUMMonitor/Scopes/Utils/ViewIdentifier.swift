/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A unique identifier for a RUM view.
internal enum ViewIdentifier: Equatable {
    #if !os(watchOS)
    case viewController(ObjectIdentifier)
    #endif
    case key(String)
}

extension ViewIdentifier {
    init(_ str: String) {
        self = .key(str)
    }
}

#if !os(watchOS)
import UIKit

extension ViewIdentifier {
    init(_ vc: UIViewController) {
        self = .viewController(ObjectIdentifier(vc))
    }
}
#endif
