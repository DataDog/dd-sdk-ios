/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import CoreGraphics
#if !os(watchOS)
import UIKit
#endif

extension CGFloat: AnyMockable, RandomMockable {
    public static func mockAny() -> CGFloat {
        return 42
    }

    public static func mockRandom() -> CGFloat {
        return mockRandom(min: .leastNormalMagnitude, max: .greatestFiniteMagnitude)
    }

    public static func mockRandom(min: CGFloat, max: CGFloat?) -> CGFloat {
        return .random(in: min...(max ?? 1_000))
    }
}

extension CGRect: AnyMockable, RandomMockable {
    public static func mockAny() -> CGRect {
        return .init(x: 0, y: 0, width: 400, height: 200)
    }

    public static func mockRandom() -> CGRect {
        return mockRandom(minWidth: 0, minHeight: 0)
    }

    public static func mockRandom(
        minX: CGFloat = 0,
        maxX: CGFloat? = nil,
        minY: CGFloat = 0,
        maxY: CGFloat? = nil,
        minWidth: CGFloat = 0,
        maxWidth: CGFloat? = nil,
        minHeight: CGFloat = 0,
        maxHeight: CGFloat? = nil
    ) -> CGRect {
        return .init(
            origin: .mockRandom(minX: minX, maxX: maxX, minY: minY, maxY: maxY),
            size: .mockRandom(minWidth: minWidth, maxWidth: maxWidth, minHeight: minHeight, maxHeight: maxHeight)
        )
    }
}

extension CGPoint: AnyMockable, RandomMockable {
    public static func mockAny() -> CGPoint {
        return .init(x: 0, y: 0)
    }

    public static func mockRandom() -> CGPoint {
        return mockRandom(minX: -1_000, maxX: 1_000, minY: -1_000, maxY: 1_000)
    }

    public static func mockRandom(
        minX: CGFloat,
        maxX: CGFloat?,
        minY: CGFloat,
        maxY: CGFloat?
    ) -> CGPoint {
        return .init(
            x: .mockRandom(min: minX, max: maxX),
            y: .mockRandom(min: minY, max: maxY)
        )
    }
}

extension CGSize: AnyMockable, RandomMockable {
    public static func mockAny() -> CGSize {
        return .init(width: 400, height: 200)
    }

    public static func mockRandom() -> CGSize {
        return .mockRandom(minWidth: 0, minHeight: 0)
    }

    public static func mockRandom(
        minWidth: CGFloat = 0,
        maxWidth: CGFloat? = nil,
        minHeight: CGFloat = 0,
        maxHeight: CGFloat? = nil
    ) -> CGSize {
        return .init(
            width: .mockRandom(min: minWidth, max: maxWidth ?? (minWidth + 1_000)),
            height: .mockRandom(min: minHeight, max: maxHeight ?? (minHeight + 1_000))
        )
    }
}

#if !os(watchOS)
extension CGColor: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        return UIColor.mockAny().cgColor as! Self
    }

    public static func mockRandom() -> Self {
        return UIColor.mockRandom().cgColor as! Self
    }
}
#endif
