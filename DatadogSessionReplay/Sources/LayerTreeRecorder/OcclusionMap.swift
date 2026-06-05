/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import CoreGraphics
import Foundation

/// Spatial index of opaquely covered viewport regions, used for occlusion testing.
internal struct OcclusionMap {
    private static let tileSize: CGFloat = 16

    private let size: CGSize
    private let columns: Int
    private let rows: Int
    private let stride: Int
    private var words: [UInt64]

    /// Creates an empty occlusion map sized to cover a `size` canvas at the origin.
    init(size: CGSize) {
        let width = max(0, size.width.isFinite ? size.width : 0)
        let height = max(0, size.height.isFinite ? size.height : 0)

        self.size = CGSize(width: width, height: height)
        self.columns = Int((width / Self.tileSize).rounded(.up))
        self.rows = Int((height / Self.tileSize).rounded(.up))
        self.stride = (columns + UInt64.bitWidth - 1) / UInt64.bitWidth
        self.words = Array(repeating: 0, count: stride * rows)
    }

    /// Records `rect` as opaquely covered.
    mutating func insert(_ rect: CGRect) {
        guard let tiles = insertTileRange(for: rect) else {
            return
        }

        let span = WordSpan(tiles.columnRange)

        for row in tiles.rowRange {
            for (word, mask) in span {
                words[row * stride + word] |= mask
            }
        }
    }

    /// Returns `true` when every tile overlapping `rect` has been marked by a previous
    /// `insert(_:)` call.
    func isCovered(_ rect: CGRect) -> Bool {
        guard let tiles = queryTileRange(for: rect) else {
            return false
        }

        let span = WordSpan(tiles.columnRange)

        for row in tiles.rowRange {
            for (word, mask) in span {
                if words[row * stride + word] & mask != mask {
                    return false
                }
            }
        }
        return true
    }

    /// Yields each `(word, mask)` pair covering the given tile column range.
    private struct WordSpan: Sequence {
        struct Iterator: IteratorProtocol {
            private let firstWord: Int
            private let lastWord: Int
            private let firstBit: Int
            private let lastBit: Int
            private var current: Int

            init(_ range: ClosedRange<Int>) {
                firstWord = range.lowerBound / UInt64.bitWidth
                lastWord = range.upperBound / UInt64.bitWidth
                firstBit = range.lowerBound % UInt64.bitWidth
                lastBit = range.upperBound % UInt64.bitWidth
                current = firstWord
            }

            mutating func next() -> (word: Int, mask: UInt64)? {
                guard current <= lastWord else {
                    return nil
                }

                let word = current
                current += 1

                let lo = word == firstWord ? firstBit : 0
                let hi = word == lastWord ? lastBit : UInt64.bitWidth - 1
                let mask = (UInt64.max >> (UInt64.bitWidth - 1 - hi)) & (UInt64.max << lo)

                return (word, mask)
            }
        }

        private let range: ClosedRange<Int>

        init(_ range: ClosedRange<Int>) {
            self.range = range
        }

        func makeIterator() -> Iterator {
            Iterator(self.range)
        }
    }

    private struct TileRange {
        let columnRange: ClosedRange<Int>
        let rowRange: ClosedRange<Int>
    }

    /// Tiles fully inside `rect`, clipped to the canvas.
    private func insertTileRange(for rect: CGRect) -> TileRange? {
        guard rows > 0, columns > 0, rect.isFinite else {
            return nil
        }

        let clipped = rect.intersection(CGRect(origin: .zero, size: size))

        guard !clipped.isEmpty else {
            return nil
        }

        let minColumn = Int((clipped.minX / Self.tileSize).rounded(.up))
        let maxColumn = Int((clipped.maxX / Self.tileSize).rounded(.down)) - 1
        let minRow = Int((clipped.minY / Self.tileSize).rounded(.up))
        let maxRow = Int((clipped.maxY / Self.tileSize).rounded(.down)) - 1

        guard minColumn <= maxColumn, minRow <= maxRow else {
            return nil
        }

        return TileRange(
            columnRange: max(0, minColumn)...min(columns - 1, maxColumn),
            rowRange: max(0, minRow)...min(rows - 1, maxRow)
        )
    }

    /// Tiles overlapping `rect`, clipped to the canvas.
    private func queryTileRange(for rect: CGRect) -> TileRange? {
        guard rows > 0, columns > 0, rect.isFinite else {
            return nil
        }

        let clipped = rect.intersection(CGRect(origin: .zero, size: size))

        guard !clipped.isEmpty else {
            return nil
        }

        let minColumn = Int((clipped.minX / Self.tileSize).rounded(.down))
        let maxColumn = Int((clipped.maxX / Self.tileSize).rounded(.up)) - 1
        let minRow = Int((clipped.minY / Self.tileSize).rounded(.down))
        let maxRow = Int((clipped.maxY / Self.tileSize).rounded(.up)) - 1

        guard minColumn <= maxColumn, minRow <= maxRow else {
            return nil
        }

        return TileRange(
            columnRange: max(0, minColumn)...min(columns - 1, maxColumn),
            rowRange: max(0, minRow)...min(rows - 1, maxRow)
        )
    }
}

extension CGRect {
    fileprivate var isFinite: Bool {
        !isInfinite && minX.isFinite && minY.isFinite && maxX.isFinite && maxY.isFinite
    }
}
#endif
