/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@_spi(Internal)
import TestUtilities
@_spi(Internal)
@testable import DatadogSessionReplay

class WireframesBuilderTests: XCTestCase {
    func testBuildingVisibleWebVieWireframes_ItRemovesSlotFromCache() {
        let slots: Set<Int> = .mockRandom(count: 10)
        let builder = WireframesBuilder(webViewSlotIDs: slots)

        slots.forEach { id in
            let frame: CGRect = .mockRandom()
            let wireframe = builder.visibleWebViewWireframe(id: id, frame: frame, clip: frame)
            guard case let .webviewWireframe(wireframe) = wireframe else {
                return XCTFail("The wireframe must be webviewWireframe case")
            }

            XCTAssertEqual(wireframe.id, Int64(id))
            XCTAssertEqual(wireframe.slotId, String(id))
            XCTAssertTrue(wireframe.isVisible ?? false)
            XCTAssertNil(wireframe.border)
            XCTAssertNil(wireframe.clip)
            XCTAssertEqual(wireframe.height, Int64.ddWithNoOverflow( frame.height))
            XCTAssertNil(wireframe.shapeStyle)
            XCTAssertEqual(wireframe.width, Int64.ddWithNoOverflow( frame.size.width))
            XCTAssertEqual(wireframe.x, Int64.ddWithNoOverflow( frame.minX))
            XCTAssertEqual(wireframe.y, Int64.ddWithNoOverflow( frame.minY))
        }

        XCTAssertTrue(builder.hiddenWebViewWireframes().isEmpty)
    }

    func testBuildingHiddenWebVieWireframes_ItRemovesSlotFromCache() {
        let slots: Set<Int> = .mockRandom(count: 10)
        let builder = WireframesBuilder(webViewSlotIDs: slots)

        builder.hiddenWebViewWireframes().forEach { wireframe in
            guard case let .webviewWireframe(wireframe) = wireframe else {
                return XCTFail("The wireframe must be webviewWireframe case")
            }

            XCTAssertEqual(String(wireframe.id), wireframe.slotId)
            XCTAssertFalse(wireframe.isVisible ?? true)
            XCTAssertNil(wireframe.border)
            XCTAssertNil(wireframe.clip)
            XCTAssertEqual(wireframe.height, 0)
            XCTAssertNil(wireframe.shapeStyle)
            XCTAssertEqual(wireframe.width, 0)
            XCTAssertEqual(wireframe.x, 0)
            XCTAssertEqual(wireframe.y, 0)
        }

        XCTAssertTrue(builder.hiddenWebViewWireframes().isEmpty)
    }

    func testBuildingImageWireframe_ItCreatesAResource() throws {
        let id: WireframeID = .mockRandom()
        let resource: MockResource = .mockRandom()
        let frame: CGRect = .mockRandom()
        let clip = frame.insetBy(dx: 1, dy: 1)
        let builder = WireframesBuilder()

        let wireframe = builder.createImageWireframe(
            id: id,
            resource: resource,
            frame: frame,
            clip: clip
        )

        guard case let .imageWireframe(wireframe) = wireframe else {
            return XCTFail("The wireframe must be imageWireframe case")
        }

        XCTAssertEqual(wireframe.id, id)
        XCTAssertNil(wireframe.border)
        XCTAssertEqual(wireframe.clip, .init(bottom: 1, left: 1, right: 1, top: 1))
        XCTAssertEqual(wireframe.height, Int64.ddWithNoOverflow( frame.height))
        XCTAssertNil(wireframe.shapeStyle)
        XCTAssertEqual(wireframe.width, Int64.ddWithNoOverflow( frame.width))
        XCTAssertEqual(wireframe.x, Int64.ddWithNoOverflow( frame.minX))
        XCTAssertEqual(wireframe.y, Int64.ddWithNoOverflow( frame.minY))
        XCTAssertEqual(builder.resources.first?.calculateIdentifier(), resource.identifier)
        XCTAssertEqual(builder.resources.first?.calculateData(), resource.data)
    }

    func testContentClip_fromIntersection() {
        let frame: CGRect = .mockRandom(minWidth: 21, minHeight: 21)

        // Inner clip
        let clip = SRContentClip(
            frame,
            intersecting: frame.insetBy(dx: 10, dy: 10)
        )

        XCTAssertEqual(clip?.top, 10)
        XCTAssertEqual(clip?.left, 10)
        XCTAssertEqual(clip?.bottom, 10)
        XCTAssertEqual(clip?.right, 10)
    }

    func testContentClip_whenIntersection_isEqualToFrame() {
        let frame: CGRect = .mockRandom()

        // Intersectin is equal to frame
        let clip = SRContentClip(
            frame,
            intersecting: frame.insetBy(dx: -10, dy: -10)
        )

        XCTAssertNil(clip)
    }

    func testContentClip_fromNoRectIntersection() {
        let frame: CGRect = .mockRandom()

        // Not intersecting clip
        let clip = SRContentClip(
            frame,
            intersecting: frame.offsetBy(dx: frame.width, dy: frame.height)
        )

        XCTAssertEqual(clip?.top, Int64.ddWithNoOverflow( frame.height))
        XCTAssertEqual(clip?.left, Int64.ddWithNoOverflow( frame.width))
        XCTAssertNil(clip?.bottom)
        XCTAssertNil(clip?.right)
    }

    func testCreateShapeWireframe_withNaNValues_filtersNaNProperties() {
        // Given
        let builder = WireframesBuilder()
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        let clip = frame
        let backgroundColor = UIColor.red.cgColor
        let nanCornerRadius: CGFloat = .nan
        let nanOpacity: CGFloat = .nan

        // When
        let wireframe = builder.createShapeWireframe(
            id: 1,
            frame: frame,
            clip: clip,
            backgroundColor: backgroundColor,
            cornerRadius: nanCornerRadius,
            opacity: nanOpacity
        )

        // Then
        guard case let .shapeWireframe(shapeWireframe) = wireframe else {
            return XCTFail("Expected shapeWireframe")
        }

        XCTAssertNotNil(shapeWireframe.shapeStyle?.backgroundColor, "backgroundColor should not be nil")
        XCTAssertNil(shapeWireframe.shapeStyle?.cornerRadius, "NaN cornerRadius should be filtered to nil")
        XCTAssertNil(shapeWireframe.shapeStyle?.opacity, "NaN opacity should be filtered to nil")
    }

    func testCreateTextWireframe_withTruncationMode() throws {
        // Given
        let builder = WireframesBuilder()
        let frame: CGRect = .mockRandom()

        // When
        let wireframe = builder.createTextWireframe(
            id: .mockRandom(),
            frame: frame,
            clip: frame,
            text: "Test text with truncation",
            truncationMode: .tail
        )

        // Then
        guard case let .textWireframe(textWireframe) = wireframe else {
            return XCTFail("Expected text wireframe")
        }

        XCTAssertEqual(textWireframe.textStyle.truncationMode, .tail)
        XCTAssertEqual(textWireframe.text, "Test text with truncation")
    }

    func testCreateTextWireframe_withoutTruncationMode() throws {
        // Given
        let builder = WireframesBuilder()
        let frame: CGRect = .mockRandom()

        // When
        let wireframe = builder.createTextWireframe(
            id: .mockRandom(),
            frame: frame,
            clip: frame,
            text: "Test text without truncation"
        )

        // Then
        guard case let .textWireframe(textWireframe) = wireframe else {
            return XCTFail("Expected text wireframe")
        }

        XCTAssertNil(textWireframe.textStyle.truncationMode, "truncationMode should be nil when not specified")
        XCTAssertEqual(textWireframe.text, "Test text without truncation")
    }
}
#endif
