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

class DiffSRWireframes: XCTestCase {
    // MARK: - Diffable Conformance

    func testDiffID() {
        let randomID: Int64 = .mockRandom()
        let wireframes: [SRWireframe] = [
            .shapeWireframe(value: .mockWith(id: randomID)),
            .textWireframe(value: .mockWith(id: randomID)),
            .imageWireframe(value: .mockWith(id: randomID)),
            .placeholderWireframe(value: .mockWith(id: randomID))
        ]

        wireframes.forEach { XCTAssertEqual($0.id, randomID) }
    }

    func testIsDifferentThan() {
        let wireframeA: SRWireframe = .mockRandomWith(id: 0)
        let wireframeB: SRWireframe = .mockRandomWith(id: 1)
        XCTAssertTrue(wireframeA.isDifferent(than: wireframeB))
    }

    // MARK: - Mutations

    func testsWhenMergingMutationsToTheOriginalShapeWireframe_itShouldProduceTheOtherOne() throws {
        // Given
        let originalWireframe: SRWireframe = .shapeWireframe(value: .mockRandom())
        let otherWireframe: SRWireframe = .shapeWireframe(value: .mockRandomWith(id: originalWireframe.id))

        // When
        let mutations = try XCTUnwrap(otherWireframe.mutations(from: originalWireframe), "Failed to compute mutations")

        // Then
        let result = try XCTUnwrap(originalWireframe.merge(mutation: mutations), "Failed to merge mutations")
        DDAssertReflectionEqual(result, otherWireframe)
    }

    func testsWhenMergingMutationsToTheOriginalTextWireframe_itShouldProduceTheOtherOne() throws {
        // Given
        let originalWireframe: SRWireframe = .textWireframe(value: .mockRandom())
        let otherWireframe: SRWireframe = .textWireframe(value: .mockRandomWith(id: originalWireframe.id))

        // When
        let mutations = try XCTUnwrap(otherWireframe.mutations(from: originalWireframe), "Failed to compute mutations")

        // Then
        let result = try XCTUnwrap(originalWireframe.merge(mutation: mutations), "Failed to merge mutations")
        DDAssertReflectionEqual(result, otherWireframe)
    }

    func testsWhenMergingMutationsToTheOriginalImageWireframe_itShouldProduceTheOtherOne() throws {
        // Given
        let originalWireframe: SRWireframe = .imageWireframe(value: .mockRandom())
        let otherWireframe: SRWireframe = .imageWireframe(value: .mockRandomWith(id: originalWireframe.id))

        // When
        let mutations = try XCTUnwrap(otherWireframe.mutations(from: originalWireframe), "Failed to compute mutations")

        // Then
        let result = try XCTUnwrap(originalWireframe.merge(mutation: mutations), "Failed to merge mutations")
        DDAssertReflectionEqual(result, otherWireframe)
    }

    func testsWhenMergingMutationsToTheOriginalPlaceholderWireframe_itShouldProduceTheOtherOne() throws {
        // Given
        let originalWireframe: SRWireframe = .placeholderWireframe(value: .mockRandom())
        let otherWireframe: SRWireframe = .placeholderWireframe(value: .mockRandomWith(id: originalWireframe.id))

        // When
        let mutations = try XCTUnwrap(otherWireframe.mutations(from: originalWireframe), "Failed to compute mutations")

        // Then
        let result = try XCTUnwrap(originalWireframe.merge(mutation: mutations), "Failed to merge mutations")
        DDAssertReflectionEqual(result, otherWireframe)
    }

    func testWhenComputingMutationsForWireframesWithDifferentID_itThrows() throws {
        let randomID: WireframeID = .mockRandom()
        let otherID: WireframeID = .mockRandom(otherThan: [randomID])

        // Given
        let wireframes: [(SRWireframe, SRWireframe)] = [
            (.shapeWireframe(value: .mockRandomWith(id: randomID)), .shapeWireframe(value: .mockRandomWith(id: otherID))),
            (.textWireframe(value: .mockRandomWith(id: randomID)), .textWireframe(value: .mockRandomWith(id: otherID))),
        ]

        // When
        try wireframes.forEach { wireframeA, wireframeB in
            XCTAssertThrowsError(try wireframeB.mutations(from: wireframeA)) { error in
                // Then
                XCTAssertEqual(error as? WireframeMutationError, WireframeMutationError.idMismatch)
            }
        }
    }

    func testWhenComputingMutationsForWireframesWithDifferentType_itThrows() throws {
        let randomID: WireframeID = .mockRandom()

        // Given
        let wireframes: [(SRWireframe, SRWireframe)] = [
            (.shapeWireframe(value: .mockRandomWith(id: randomID)), .textWireframe(value: .mockRandomWith(id: randomID))),
            (.textWireframe(value: .mockRandomWith(id: randomID)), .shapeWireframe(value: .mockRandomWith(id: randomID))),
        ]

        // When
        try wireframes.forEach { wireframeA, wireframeB in
            XCTAssertThrowsError(try wireframeB.mutations(from: wireframeA)) { error in
                // Then
                XCTAssertEqual(
                    error as? WireframeMutationError,
                    WireframeMutationError.typeMismatch(
                        fromType: wireframeA.type,
                        toType: wireframeB.type
                    )
                )
            }
        }
    }

    func testWhenComputingMutationsForImageWireframe_isNotDifferentButUpdateBase64() {
        // Given
        let randomID: WireframeID = .mockRandom()
        let base64: String = .mockRandom()
        let wireframeA: SRWireframe = .imageWireframe(value: .mockWith(base64: .mockRandom(), id: randomID))
        let wireframeB: SRWireframe = .imageWireframe(value: .mockWith(base64: base64, id: randomID))

        // When
        let mutations = try? wireframeB.mutations(from: wireframeA)
        let isDifferent = wireframeA.isDifferent(than: wireframeB)

        // Then
        XCTAssertFalse(isDifferent)
        if case let .imageWireframeUpdate(update) = mutations {
            XCTAssertEqual(update.base64, base64)
        } else {
            XCTFail("mutations are expected to be `.imageWireframeUpdate`")
        }
    }

    func testUpdatingContentClip() throws {
        let id: WireframeID = .mockRandom()

        // Given
        let clip0 = SRContentClip(bottom: nil, left: nil, right: nil, top: nil)
        let wireframe0: SRWireframe = .shapeWireframe(value: .mockWith(clip: clip0, id: id))

        let clip1 = SRContentClip(bottom: nil, left: nil, right: 10, top: 10)
        let wireframe1: SRWireframe = .shapeWireframe(value: .mockWith(clip: clip1, id: id))

        let clip2 = SRContentClip(bottom: 10, left: 10, right: nil, top: nil)
        let wireframe2: SRWireframe = .shapeWireframe(value: .mockWith(clip: clip2, id: id))

        // When
        let mutation1 = try XCTUnwrap(wireframe1.mutations(from: wireframe0))
        let result1 = try XCTUnwrap(wireframe0.merge(mutation: mutation1)?.shapeWireframe)

        let mutation2 = try XCTUnwrap(wireframe2.mutations(from: wireframe1))
        let result2 = try XCTUnwrap(wireframe1.merge(mutation: mutation2)?.shapeWireframe)

        let mutation3 = try XCTUnwrap(wireframe0.mutations(from: wireframe2))
        let result3 = try XCTUnwrap(wireframe2.merge(mutation: mutation3)?.shapeWireframe)

        let mutation4 = try XCTUnwrap(wireframe0.mutations(from: wireframe0))
        let result4 = try XCTUnwrap(wireframe0.merge(mutation: mutation4)?.shapeWireframe)

        // Then
        XCTAssertEqual(result1.clip, SRContentClip(bottom: nil, left: nil, right: 10, top: 10))
        XCTAssertEqual(result2.clip, SRContentClip(bottom: 10, left: 10, right: 0, top: 0))
        XCTAssertEqual(result3.clip, SRContentClip(bottom: 0, left: 0, right: nil, top: nil))
        XCTAssertEqual(result4.clip, SRContentClip(bottom: nil, left: nil, right: nil, top: nil))
    }
}

// MARK: - Helpers

private typealias TextWireframeUpdate = SRIncrementalSnapshotRecord.Data.MutationData.Updates.TextWireframeUpdate
private typealias ShapeWireframeUpdate = SRIncrementalSnapshotRecord.Data.MutationData.Updates.ShapeWireframeUpdate
private typealias ImageWireframeUpdate = SRIncrementalSnapshotRecord.Data.MutationData.Updates.ImageWireframeUpdate
private typealias PlaceholderWireframeUpdate = SRIncrementalSnapshotRecord.Data.MutationData.Updates.PlaceholderWireframeUpdate

extension SRWireframe {
    func merge(mutation: WireframeMutation) -> SRWireframe? {
        switch (self, mutation) {
        case let (.shapeWireframe(wireframe), .shapeWireframeUpdate(update)):
            return .shapeWireframe(value: merge(update: update, into: wireframe))
        case let (.textWireframe(wireframe), .textWireframeUpdate(update)):
            return .textWireframe(value: merge(update: update, into: wireframe))
        case let (.imageWireframe(wireframe), .imageWireframeUpdate(update)):
            return .imageWireframe(value: merge(update: update, into: wireframe))
        case let (.placeholderWireframe(wireframe), .placeholderWireframeUpdate(update)):
            return .placeholderWireframe(value: merge(update: update, into: wireframe))
        default:
            return nil
        }
    }

    private func merge(update: ShapeWireframeUpdate, into wireframe: SRShapeWireframe) -> SRShapeWireframe {
        return SRShapeWireframe(
            border: update.border ?? wireframe.border,
            clip: update.clip ?? wireframe.clip,
            height: update.height ?? wireframe.height,
            id: update.id,
            shapeStyle: update.shapeStyle ?? wireframe.shapeStyle,
            width: update.width ?? wireframe.width,
            x: update.x ?? wireframe.x,
            y: update.y ?? wireframe.y
        )
    }

    private func merge(update: TextWireframeUpdate, into wireframe: SRTextWireframe) -> SRTextWireframe {
        return SRTextWireframe(
            border: update.border ?? wireframe.border,
            clip: update.clip ?? wireframe.clip,
            height: update.height ?? wireframe.height,
            id: update.id,
            shapeStyle: update.shapeStyle ?? wireframe.shapeStyle,
            text: update.text ?? wireframe.text,
            textPosition: update.textPosition ?? wireframe.textPosition,
            textStyle: update.textStyle ?? wireframe.textStyle,
            width: update.width ?? wireframe.width,
            x: update.x ?? wireframe.x,
            y: update.y ?? wireframe.y
        )
    }

    private func merge(update: ImageWireframeUpdate, into wireframe: SRImageWireframe) -> SRImageWireframe {
        return SRImageWireframe(
            base64: update.base64 ?? wireframe.base64,
            border: update.border ?? wireframe.border,
            clip: update.clip ?? wireframe.clip,
            height: update.height ?? wireframe.height,
            id: update.id,
            isEmpty: update.isEmpty ?? wireframe.isEmpty,
            mimeType: update.mimeType ?? wireframe.mimeType,
            shapeStyle: update.shapeStyle ?? wireframe.shapeStyle,
            width: update.width ?? wireframe.width,
            x: update.x ?? wireframe.x,
            y: update.y ?? wireframe.y
        )
    }

    private func merge(update: PlaceholderWireframeUpdate, into wireframe: SRPlaceholderWireframe) -> SRPlaceholderWireframe {
        return SRPlaceholderWireframe(
            clip: update.clip ?? wireframe.clip,
            height: update.height ?? wireframe.height,
            id: update.id,
            label: update.label ?? wireframe.label,
            width: update.width ?? wireframe.width,
            x: update.x ?? wireframe.x,
            y: update.y ?? wireframe.y
        )
    }
}
#endif
