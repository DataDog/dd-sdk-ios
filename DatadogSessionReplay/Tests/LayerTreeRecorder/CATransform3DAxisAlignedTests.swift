/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import TestUtilities
import Testing
import QuartzCore

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
struct CATransform3DAxisAlignedTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test(
        "Is not axis-aligned for transforms with rotation or perspective",
        arguments: [
            CATransform3DMakeRotation(.pi / 4, 0, 0, 1),
            CATransform3DMakeRotation(.pi / 4, 1, 0, 0),
            CATransform3DMakeRotation(.pi / 4, 0, 1, 0),
            {
                var transform = CATransform3DIdentity
                transform.m14 = -1 / 500
                return transform
            }(),
            {
                var transform = CATransform3DIdentity
                transform.m24 = -1 / 500
                return transform
            }(),
            {
                var transform = CATransform3DIdentity
                transform.m34 = -1 / 500
                return transform
            }(),
        ]
    )
    func isNotAxisAlignedForNonTrivialTransforms(transform: CATransform3D) throws {
        #expect(!transform.isAxisAligned)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Is axis-aligned when scaled uniformly")
    func isAxisAlignedWhenScaledUniformly() throws {
        // Given
        let transform = CATransform3DMakeScale(2, 2, 1)

        // Then
        #expect(transform.isAxisAligned)
    }
}
#endif
