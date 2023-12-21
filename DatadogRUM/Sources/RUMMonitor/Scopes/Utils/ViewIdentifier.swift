/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A unique identifier for a RUM view.
internal struct ViewIdentifier {
    private let hash: Int
    private let isNil: () -> Bool

    /// Returns `true` if the view identifier refers to an object and
    /// that object is still allocated
    internal var exists: Bool { !isNil() }
}

extension ViewIdentifier: Equatable {
    static func == (lhs: ViewIdentifier, rhs: ViewIdentifier) -> Bool {
        lhs.hash == rhs.hash
    }
}

extension ViewIdentifier {
    init(_ str: String) {
        hash = str.hash
        isNil = { false }
    }
}

#if canImport(UIKit)
import UIKit

extension ViewIdentifier {
    init(_ vc: UIViewController) {
        hash = vc.hash
        isNil = { [weak vc] in vc == nil }
    }
}

#endif
