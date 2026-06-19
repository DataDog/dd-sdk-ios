/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import QuartzCore

@available(iOS 13.0, tvOS 13.0, *)
extension CATransform3D {
    /// A Boolean value indicating whether the transform contains no rotation, skew, or perspective.
    var isAxisAligned: Bool {
        m12 == 0 && m21 == 0
            && m13 == 0 && m23 == 0
            && m31 == 0 && m32 == 0
            && m14 == 0 && m24 == 0
            && m34 == 0
    }
}
#endif
