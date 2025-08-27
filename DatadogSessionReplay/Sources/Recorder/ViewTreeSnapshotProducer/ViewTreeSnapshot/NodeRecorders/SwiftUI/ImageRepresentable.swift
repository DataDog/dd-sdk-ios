/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
import UIKit

@available(iOS 13.0, tvOS 13.0, *)
internal protocol ImageRepresentable: Hashable {
    func makeImage() -> UIImage?
}

@available(iOS 13.0, tvOS 13.0, *)
internal struct AnyImageRepresentable: ImageRepresentable {
    private let base: any ImageRepresentable

    init(_ base: some ImageRepresentable) {
        if let base = base as? AnyImageRepresentable {
            self = base
        } else {
            self.base = base
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
      AnyHashable(lhs.base) == AnyHashable(rhs.base)
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(base)
    }

    func makeImage() -> UIImage? {
        base.makeImage()
    }
}

#endif
