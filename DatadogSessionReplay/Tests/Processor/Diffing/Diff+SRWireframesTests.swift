/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import TestUtilities
@testable import DatadogSessionReplay

class DiffSRWireframes: XCTestCase {
    // MARK: - Diffable Conformance

    func testDiffID() {
        let randomID: Int64 = .mockRandom()
        let wireframes: [SRWireframe] = [
            .shapeWireframe(value: .mockWith(id: randomID)),
            .textWireframe(value: .mockWith(id: randomID))
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
                XCTAssertEqual(error as? WireframeMutationError, WireframeMutationError.typeMismatch)
            }
        }
    }
}

// MARK: - Helpers

private typealias TextWireframeUpdate = SRIncrementalSnapshotRecord.Data.MutationData.Updates.TextWireframeUpdate
private typealias ShapeWireframeUpdate = SRIncrementalSnapshotRecord.Data.MutationData.Updates.ShapeWireframeUpdate

extension SRWireframe {
    func merge(mutation: WireframeMutation) -> SRWireframe? {
        switch (self, mutation) {
        case let (.shapeWireframe(wireframe), .shapeWireframeUpdate(update)):
            return .shapeWireframe(value: merge(update: update, into: wireframe))
        case let (.textWireframe(wireframe), .textWireframeUpdate(update)):
            return .textWireframe(value: merge(update: update, into: wireframe))
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
}
