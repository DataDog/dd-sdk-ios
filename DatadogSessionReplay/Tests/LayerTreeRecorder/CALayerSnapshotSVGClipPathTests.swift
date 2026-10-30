/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import SwiftUI
import Testing
import TestUtilities

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
@MainActor
struct CALayerSnapshotSVGClipPathTests {
    typealias CornerRadii = CALayerSnapshot.CornerRadii
    private let size = CGSize(width: 100, height: 50)
    private let cornerRadii = CornerRadii(
        topLeft: CGSize(width: 10, height: 10),
        topRight: CGSize(width: 10, height: 10),
        bottomLeft: CGSize(width: 10, height: 10),
        bottomRight: CGSize(width: 10, height: 10)
    )

    @Test(
        "Changing either dimension produces the correct clip path",
        arguments: [
            CGSize(width: 101, height: 50),
            CGSize(width: 100, height: 51)
        ]
    )
    func returnsUpdatedClipPathWhenSizeChanges(size: CGSize) {
        // Given
        let formatter = ClipPathFormatter()
        var snapshot = CALayerSnapshot.mockWith(
            absoluteFrame: CGRect(origin: CGPoint(x: 10, y: 20), size: self.size),
            cornerRadii: cornerRadii,
            masksToBounds: true
        )
        _ = snapshot.svgClipPath(using: formatter)
        let expectedPath = Path(
            roundedRect: CGRect(origin: .zero, size: size),
            cornerRadii: cornerRadii,
            cornerCurve: .circular
        ).dd.svgString

        // When
        snapshot.absoluteFrame.size = size
        let path = snapshot.svgClipPath(using: formatter)

        // Then
        #expect(path == expectedPath)
    }

    @Test(
        "Changing any corner-radius component produces the correct clip path",
        arguments: [
            \CornerRadii.topLeft.width,
            \CornerRadii.topLeft.height,
            \CornerRadii.topRight.width,
            \CornerRadii.topRight.height,
            \CornerRadii.bottomLeft.width,
            \CornerRadii.bottomLeft.height,
            \CornerRadii.bottomRight.width,
            \CornerRadii.bottomRight.height
        ]
    )
    func returnsUpdatedClipPathWhenCornerRadiusChanges(component: WritableKeyPath<CornerRadii, CGFloat>) {
        // Given
        let formatter = ClipPathFormatter()
        let snapshot = CALayerSnapshot.mockWith(
            absoluteFrame: CGRect(origin: .zero, size: size),
            cornerRadii: cornerRadii,
            masksToBounds: true
        )
        _ = snapshot.svgClipPath(using: formatter)
        var modifiedCornerRadii = cornerRadii
        modifiedCornerRadii[keyPath: component] += 1
        let modifiedSnapshot = CALayerSnapshot.mockWith(
            absoluteFrame: snapshot.absoluteFrame,
            cornerRadii: modifiedCornerRadii,
            masksToBounds: true
        )
        let expectedPath = Path(
            roundedRect: CGRect(origin: .zero, size: size),
            cornerRadii: modifiedCornerRadii,
            cornerCurve: .circular
        ).dd.svgString

        // When
        let path = modifiedSnapshot.svgClipPath(using: formatter)

        // Then
        #expect(path == expectedPath)
    }

    @Test("Changing the corner curve produces the correct clip path")
    func returnsUpdatedClipPathWhenCornerCurveChanges() {
        // Given
        let formatter = ClipPathFormatter()
        let snapshot = CALayerSnapshot.mockWith(
            absoluteFrame: CGRect(origin: .zero, size: size),
            cornerRadii: cornerRadii,
            masksToBounds: true
        )
        _ = snapshot.svgClipPath(using: formatter)
        let modifiedSnapshot = CALayerSnapshot.mockWith(
            absoluteFrame: snapshot.absoluteFrame,
            cornerRadii: cornerRadii,
            cornerCurve: .continuous,
            masksToBounds: true
        )
        let expectedPath = Path(
            roundedRect: CGRect(origin: .zero, size: size),
            cornerRadii: cornerRadii,
            cornerCurve: .continuous
        ).dd.svgString

        // When
        let path = modifiedSnapshot.svgClipPath(using: formatter)

        // Then
        #expect(path == expectedPath)
    }

    @Test("Layers without clipping have no SVG clip path")
    func returnsNilWhenClippingDoesNotApply() {
        // Given
        let snapshot = CALayerSnapshot.mockWith(
            absoluteFrame: CGRect(origin: .zero, size: size),
            cornerRadii: cornerRadii,
            masksToBounds: false
        )

        // When
        let path = snapshot.svgClipPath(using: ClipPathFormatter())

        // Then
        #expect(path == nil)
    }
}
#endif
