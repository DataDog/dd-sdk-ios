/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import TestUtilities
import QuartzCore
import SwiftUI
import Testing

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
struct PathCornerRadiiTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Creates path for elliptical corner radii")
    func createsPathForEllipticalCornerRadii() {
        // Given
        let cornerRadii = CALayerSnapshot.CornerRadii(
            topLeft: CGSize(width: 10, height: 5),
            topRight: CGSize(width: 20, height: 10),
            bottomLeft: CGSize(width: 5, height: 20),
            bottomRight: CGSize(width: 30, height: 15)
        )

        // When
        let path = SwiftUI.Path(
            roundedRect: CGRect(x: 0, y: 0, width: 100, height: 50),
            cornerRadii: cornerRadii,
            cornerCurve: .circular
        )

        // Then
        #expect(
            path.dd.svgString == """
                M 10.000 0.000 L 80.000 0.000 \
                C 91.046 0.000 100.000 4.477 100.000 10.000 \
                L 100.000 35.000 \
                C 100.000 43.284 86.569 50.000 70.000 50.000 \
                L 5.000 50.000 \
                C 2.239 50.000 0.000 41.046 0.000 30.000 \
                L 0.000 5.000 \
                C 0.000 2.239 4.477 0.000 10.000 0.000 Z
                """
        )
    }
}
#endif
