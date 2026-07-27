/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import CoreGraphics
import TestUtilities
import Testing

@testable import DatadogSessionReplay

@Suite(.datadogTesting)
struct OcclusionMapTests {
    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Reports nothing as covered when the map is empty")
    func emptyMapReportsNothingAsCovered() {
        // Given
        var map = OcclusionMap(size: .zero)

        // When
        map.insert(CGRect(x: 0, y: 0, width: 100, height: 100))
        let isCovered = map.isCovered(CGRect(x: 0, y: 0, width: 10, height: 10))

        // Then
        #expect(!isCovered)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Ignores inserts one pixel short of a tile")
    func ignoresInsertsOnePixelShortOfATile() {
        // Given
        var map = OcclusionMap(size: CGSize(width: 64, height: 64))
        map.insert(CGRect(x: 0, y: 0, width: 15, height: 15))

        // When
        let isCovered = map.isCovered(CGRect(x: 0, y: 0, width: 4, height: 4))

        // Then
        #expect(!isCovered)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Does not cover a query that overlaps an unmarked tile")
    func doesNotCoverQueryOverlappingAnUnmarkedTile() {
        // Given
        var map = OcclusionMap(size: CGSize(width: 64, height: 64))
        map.insert(CGRect(x: 0, y: 0, width: 16, height: 64))

        // When
        let isCovered = map.isCovered(CGRect(x: 8, y: 0, width: 16, height: 16))

        // Then
        #expect(!isCovered)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Covers a query that spans the union of adjacent inserts")
    func coversQuerySpanningUnionOfAdjacentInserts() {
        // Given
        var map = OcclusionMap(size: CGSize(width: 64, height: 64))
        map.insert(CGRect(x: 0, y: 0, width: 32, height: 32))
        map.insert(CGRect(x: 32, y: 0, width: 32, height: 32))

        // When
        let isCovered = map.isCovered(CGRect(x: 0, y: 0, width: 64, height: 32))

        // Then
        #expect(isCovered)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test(
        "Does not cover an invalid candidate rect",
        arguments: [
            CGRect.null,
            .infinite,
            CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100),
        ]
    )
    func doesNotCoverAnInvalidCandidateRect(rect: CGRect) {
        // Given
        var map = OcclusionMap(size: CGSize(width: 64, height: 64))
        map.insert(CGRect(x: 0, y: 0, width: 64, height: 64))

        // When
        let isCovered = map.isCovered(rect)

        // Then
        #expect(!isCovered)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test(
        "Treats invalid sizes as empty",
        arguments: [
            CGSize(width: -10, height: 10),
            CGSize(width: 10, height: CGFloat.infinity),
        ]
    )
    func treatsInvalidSizesAsEmpty(size: CGSize) {
        // Given
        var map = OcclusionMap(size: size)
        map.insert(CGRect(x: 0, y: 0, width: 10, height: 10))

        // When
        let isCovered = map.isCovered(CGRect(x: 0, y: 0, width: 5, height: 5))

        // Then
        #expect(!isCovered)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Ignores partial tiles at the canvas edge")
    func ignoresPartialTilesAtCanvasEdge() {
        // Given
        var map = OcclusionMap(size: CGSize(width: 24, height: 16))
        map.insert(CGRect(x: 0, y: 0, width: 24, height: 16))

        // When
        let fullTileCovered = map.isCovered(CGRect(x: 0, y: 0, width: 16, height: 16))
        let partialTileCovered = map.isCovered(CGRect(x: 16, y: 0, width: 8, height: 16))

        // Then
        #expect(fullTileCovered)
        #expect(!partialTileCovered)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Supports canvases wider than 64 tiles")
    func supportsCanvasesWiderThan64Tiles() {
        // Given
        var map = OcclusionMap(size: CGSize(width: 1_040, height: 32))
        map.insert(CGRect(x: 0, y: 0, width: 1_040, height: 32))

        // When
        let isCovered = map.isCovered(CGRect(x: 1_024, y: 16, width: 16, height: 16))

        // Then
        #expect(isCovered)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Covers a query whose columns cross a word boundary")
    func coversQueryCrossingAWordBoundary() {
        // Given
        var map = OcclusionMap(size: CGSize(width: 1_600, height: 16))
        map.insert(CGRect(x: 256, y: 0, width: 1_024, height: 16))

        // When
        let coveredInsideRange = map.isCovered(CGRect(x: 512, y: 0, width: 768, height: 16))
        let coveredJustBeforeRange = map.isCovered(CGRect(x: 240, y: 0, width: 16, height: 16))
        let coveredJustAfterRange = map.isCovered(CGRect(x: 1_280, y: 0, width: 16, height: 16))

        // Then
        #expect(coveredInsideRange)
        #expect(!coveredJustBeforeRange)
        #expect(!coveredJustAfterRange)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Covers a non-aligned query inside a marked region")
    func coversNonAlignedQueryInsideMarkedRegion() {
        // Given
        var map = OcclusionMap(size: CGSize(width: 64, height: 64))
        map.insert(CGRect(x: 0, y: 0, width: 64, height: 64))

        // When
        let isCovered = map.isCovered(CGRect(x: 5, y: 5, width: 30, height: 30))

        // Then
        #expect(isCovered)
    }

    @available(iOS 13.0, tvOS 13.0, *)
    @Test("Marks only fully-enclosed tiles when insert starts and ends mid-tile")
    func marksOnlyFullyEnclosedTilesWhenInsertStartsAndEndsMidTile() {
        // Given
        var map = OcclusionMap(size: CGSize(width: 64, height: 64))
        map.insert(CGRect(x: 5, y: 5, width: 30, height: 30))

        // When
        let middleTileCovered = map.isCovered(CGRect(x: 16, y: 16, width: 16, height: 16))
        let edgeTileCovered = map.isCovered(CGRect(x: 0, y: 0, width: 16, height: 16))

        // Then
        #expect(middleTileCovered)
        #expect(!edgeTileCovered)
    }
}
#endif
