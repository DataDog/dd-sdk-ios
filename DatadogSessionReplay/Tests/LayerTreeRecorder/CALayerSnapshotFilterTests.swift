/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import QuartzCore
import TestUtilities
import Testing

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
struct CALayerSnapshotFilterTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Ignores unsupported filter values")
    func ignoresUnsupportedFilterValues() {
        // Given
        let filter = NSObject()

        // When
        let snapshotFilter = CALayerSnapshot.Filter(filter)

        // Then
        #expect(snapshotFilter == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Ignores disabled filters")
    func ignoresDisabledFilters() throws {
        // Given
        let filter = try NSObject.makeCAFilter(type: "glassBackground")
        filter.setValue(false, forKey: "enabled")

        // When
        let snapshotFilter = CALayerSnapshot.Filter(filter)

        // Then
        #expect(snapshotFilter == nil)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Captures gaussian blur filter", arguments: ["gaussianBlur", "variableBlur"])
    func capturesGaussianBlurFilter(type: String) throws {
        // Given
        let filter = try NSObject.makeCAFilter(type: type)
        let radius: CGFloat = 12
        filter.setValue(radius, forKey: "inputRadius")

        // When
        let snapshotFilter = CALayerSnapshot.Filter(filter)

        // Then
        #expect(snapshotFilter == .gaussianBlur(radius))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Captures color matrix filter")
    func capturesColorMatrixFilter() throws {
        // Given
        let filter = try NSObject.makeCAFilter(type: "colorMatrix")
        // swiftlint:disable multiline_arguments
        let matrix = CALayerSnapshot.ColorMatrix(
            m11: 1, m12: 2, m13: 3, m14: 4, m15: 5,
            m21: 6, m22: 7, m23: 8, m24: 9, m25: 10,
            m31: 11, m32: 12, m33: 13, m34: 14, m35: 15,
            m41: 16, m42: 17, m43: 18, m44: 19, m45: 20
        )
        // swiftlint:enable multiline_arguments
        filter.setValue(matrix.nsValue, forKey: "inputColorMatrix")

        // When
        let snapshotFilter = CALayerSnapshot.Filter(filter)

        // Then
        #expect(snapshotFilter == .colorMatrix(matrix))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Captures vibrant color matrix filter")
    func capturesVibrantColorMatrixFilter() throws {
        // Given
        let filter = try NSObject.makeCAFilter(type: "vibrantColorMatrix")
        // swiftlint:disable multiline_arguments
        let matrix = CALayerSnapshot.ColorMatrix(
            m11: 1, m12: 2, m13: 3, m14: 4, m15: 5,
            m21: 6, m22: 7, m23: 8, m24: 9, m25: 10,
            m31: 11, m32: 12, m33: 13, m34: 14, m35: 15,
            m41: 16, m42: 17, m43: 18, m44: 19, m45: 20
        )
        // swiftlint:enable multiline_arguments
        filter.setValue(matrix.nsValue, forKey: "inputColorMatrix")

        // When
        let snapshotFilter = CALayerSnapshot.Filter(filter)

        // Then
        #expect(snapshotFilter == .vibrantColorMatrix(matrix))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Captures color saturate filter")
    func capturesColorSaturateFilter() throws {
        // Given
        let filter = try NSObject.makeCAFilter(type: "colorSaturate")
        let amount: CGFloat = 0.75
        filter.setValue(amount, forKey: "inputAmount")

        // When
        let snapshotFilter = CALayerSnapshot.Filter(filter)

        // Then
        #expect(snapshotFilter == .saturate(amount))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Captures color brightness filter")
    func capturesColorBrightnessFilter() throws {
        // Given
        let filter = try NSObject.makeCAFilter(type: "colorBrightness")
        let amount: CGFloat = 0.75
        filter.setValue(amount, forKey: "inputAmount")

        // When
        let snapshotFilter = CALayerSnapshot.Filter(filter)

        // Then
        #expect(snapshotFilter == .brightness(amount))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Captures multiply color filter")
    func capturesMultiplyColorFilter() throws {
        // Given
        let filter = try NSObject.makeCAFilter(type: "multiplyColor")
        let color = CGColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1)
        filter.setValue(color, forKey: "inputColor")

        // When
        let snapshotFilter = CALayerSnapshot.Filter(filter)

        // Then
        #expect(snapshotFilter == .multiplyColor(color))
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Captures unknown filter names")
    func capturesUnknownFilterNames() throws {
        // Given
        let filter = try NSObject.makeCAFilter(type: "displacementMap")
        let name = try #require(filter.value(forKey: "name") as? String)

        // When
        let snapshotFilter = CALayerSnapshot.Filter(filter)

        // Then
        #expect(snapshotFilter == .unknown(name))
    }
}

@available(iOS 13.0, tvOS 13.0, *)
private extension CALayerSnapshot.ColorMatrix {
    var nsValue: NSValue {
        var value = self
        return withUnsafePointer(to: &value) {
            NSValue(bytes: $0, objCType: "{CAColorMatrix=ffffffffffffffffffff}")
        }
    }
}
#endif
