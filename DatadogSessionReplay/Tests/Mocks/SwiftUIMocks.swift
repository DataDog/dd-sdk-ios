/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit
import SwiftUI
import TestUtilities

@testable import DatadogSessionReplay

@objc
@available(iOS 13.0, *)
internal class UIHostingViewMock: UIView {
    let renderer: ViewRendererMock

    init(frame: CGRect = .mockAny(), renderer: ViewRendererMock = .mockAny()) {
        self.renderer = renderer
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        self.renderer = .mockAny()
        super.init(coder: coder)
    }
}

@available(iOS 13.0, *)
final class ViewRendererMock: AnyMockable, RandomMockable {
    let renderer: ViewUpdaterMock

    init(renderer: ViewUpdaterMock = .mockAny()) {
        self.renderer = renderer
    }

    static func mockAny() -> ViewRendererMock {
        .init(renderer: .mockAny())
    }

    static func mockRandom() -> ViewRendererMock {
        .init(renderer: .mockRandom())
    }
}

@available(iOS 13.0, *)
final class ViewUpdaterMock: AnyMockable, RandomMockable {
    let viewCache: ViewCacheMock
    let lastList: DisplayList

    init(viewCache: ViewCacheMock, lastList: DisplayList) {
        self.viewCache = viewCache
        self.lastList = lastList
    }

    static func mockAny() -> ViewUpdaterMock {
        .mockWith()
    }

    static func mockWith(list: DisplayList = .mockAny()) -> ViewUpdaterMock {
        self.init(
            viewCache: .mockAny(for: list),
            lastList: list
        )
    }

    static func mockRandom() -> ViewUpdaterMock {
        let list: DisplayList = .mockRandom()
        return mockWith(list: list)
    }
}

@available(iOS 13.0, *)
final class ViewCacheMock: AnyMockable, RandomMockable {
    struct Value {
        let view: UIView
    }

    let map: [DisplayList.ViewUpdater.ViewCache.Key: Value]

    init(map: [DisplayList.ViewUpdater.ViewCache.Key: Value]) {
        self.map = map
    }

    static func mockWith(map: [DisplayList.ViewUpdater.ViewCache.Key: Value] = [:]) -> Self {
        .init(map: map)
    }

    static func mockAny() -> Self {
        .mockWith()
    }

    static func mockRandom() -> Self {
        .mockWith(map: .mockRandom())
    }

    static func mockAny(for list: DisplayList) -> Self {
        var ids: [DisplayList.Identity] = []
        identities(from: list, &ids)
        return .mockWith(
            map: ids.reduce(into: [:]) { map, identity in
                map[.mockWith(identity: identity)] = .mockAny()
            }
        )
    }

    static func mockRandom(for list: DisplayList) -> Self {
        var ids: [DisplayList.Identity] = []
        identities(from: list, &ids)
        return .mockWith(
            map: ids.reduce(into: [:]) { map, identity in
                map[.mockWith(identity: identity)] = .mockRandom()
            }
        )
    }

    /// Collect identities from the dispay list recursively to build a mocked cache.
    private static func identities(from list: DisplayList, _ identities: inout [DisplayList.Identity]) {
        list.items.forEach { item in
            identities.append(item.identity)

            if case let .effect(_, list) = item.value {
                self.identities(from: list, &identities)
            }
        }
    }
}

@available(iOS 13.0, *)
extension ViewCacheMock.Value: AnyMockable, RandomMockable {
    static func mockWith(view: UIView = .mockAny()) -> Self {
        .init(view: view)
    }

    public static func mockAny() -> Self {
        .mockWith()
    }

    public static func mockRandom() -> Self {
        .mockWith(view: .mockRandom())
    }
}

@available(iOS 13.0, *)
extension DisplayList: AnyMockable, RandomMockable {
    static func mockWith(items: [Item] = .mockAny()) -> DisplayList {
        .init(items: items)
    }

    static func mockWith(item: Item) -> DisplayList {
        .init(items: [item])
    }

    public static func mockAny() -> DisplayList {
        .mockWith()
    }

    public static func mockRandom() -> DisplayList {
        let items: [Item] = (0..<arc4random_uniform(10)).map { _ in .mockRandom() }
        return .mockWith(items: items)
    }
}

@available(iOS 13.0, *)
extension DisplayList.ViewUpdater.ViewCache.Key: AnyMockable, RandomMockable {
    static func mockWith(identity: DisplayList.Identity = .mockAny()) -> Self {
        .init(id: .init(identity: identity))
    }

    public static func mockAny() -> Self {
        .mockWith()
    }

    public static func mockRandom() -> Self {
        .init(id: .init(identity: .mockRandom()))
    }
}

@available(iOS 13.0, *)
extension DisplayList.Item: AnyMockable, RandomMockable {
    static func mockWith(
        identity: DisplayList.Identity = .mockAny(),
        frame: CGRect = .mockAny(),
        value: Value = .unknown
    ) -> DisplayList.Item {
        self.init(
            identity: identity,
            frame: frame,
            value: value
        )
    }

    public static func mockAny() -> DisplayList.Item {
        .mockWith()
    }

    public static func mockRandom() -> DisplayList.Item {
        .mockWith(
            identity: .mockRandom(),
            frame: .mockRandom(),
            value: .mockRandom()
        )
    }
}

@available(iOS 13.0, *)
extension DisplayList.Identity: AnyMockable, RandomMockable {
    public static func mockAny() -> DisplayList.Identity {
        .init(value: .mockAny())
    }

    public static func mockRandom() -> DisplayList.Identity {
        .init(value: .mockRandom())
    }
}

@available(iOS 13.0, *)
extension DisplayList.Seed: AnyMockable, RandomMockable {
    public static func mockAny() -> DisplayList.Seed {
        .init(value: .mockAny())
    }

    public static func mockRandom() -> DisplayList.Seed {
        .init(value: .mockRandom())
    }
}

@available(iOS 13.0, *)
extension DisplayList.Item.Value: AnyMockable, RandomMockable {
    static func mockEffect(
        effect: DisplayList.Effect = .identify,
        list: DisplayList = .mockAny()
    ) -> Self {
        .effect(effect, list)
    }

    public static func mockAny() -> Self { .unknown }

    public static func mockRandom() -> Self {
        switch arc4random_uniform(10) % 5 /* 2/5 */ {
        case 0: return .mockEffect(effect: .mockRandom(), list: .mockRandom())
        default: return .content(.mockRandom())
        }
    }
}

@available(iOS 13.0, *)
extension DisplayList.Effect {
    static func mockClip(path: SwiftUI.Path = .init(), style: SwiftUI.FillStyle = .init()) -> Self {
        .clip(path, style)
    }

    public static func mockRandom() -> Self {
        switch arc4random_uniform(2) /* [0-1] */ {
        case 0: return .identify
        case 1: return .mockClip()
        default: return .unknown
        }
    }
}

@available(iOS 13.0, *)
extension DisplayList.Content: AnyMockable, RandomMockable {
    static func mockWith(
        seed: DisplayList.Seed = .mockAny(),
        value: Value = .unknown
    ) -> DisplayList.Content {
        .init(
            seed: seed,
            value: value
        )
    }

    public static func mockAny() -> DisplayList.Content {
        .mockWith()
    }

    public static func mockRandom() -> DisplayList.Content {
        .mockWith(
            seed: .mockRandom(),
            value: .mockRandom()
        )
    }
}

@available(iOS 13.0, *)
extension DisplayList.Content.Value: RandomMockable {
    static func mockText(string: NSAttributedString, size: CGSize = .mockAny()) -> Self {
        .text(.init(text: .init(storage: string)), size)
    }

    static func mockShape(
        path: SwiftUI.Path = .init(),
        color: SwiftUI.Color._Resolved = .mockAny(),
        style: SwiftUI.FillStyle = .init()
    ) -> Self {
        .shape(path, .init(paint: color), style)
    }

    static func mockColor(
        color: SwiftUI.Color._Resolved = .mockAny()
    ) -> Self {
        .color(color)
    }

    static func mockImage(
        image: GraphicsImage = .mockAny()
    ) -> Self {
        .image(image)
    }

    public static func mockRandom() -> Self {
        switch arc4random_uniform(5) /* [0-4] */ {
        case 0: return .mockShape()
        case 1: return .mockText(string: NSAttributedString(string: .mockRandom()))
        case 2: return .platformView
        case 3: return .mockColor(color: .mockRandom())
        case 4: return .mockImage(image: .mockRandom())
        default: return .unknown
        }
    }
}

@available(iOS 13.0, *)
extension SwiftUI.Color._Resolved: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        .init(linearRed: .mockAny(), linearGreen: .mockAny(), linearBlue: .mockAny(), opacity: .mockAny())
    }

    public static func mockRandom() -> Self {
        .init(linearRed: .mockRandom(), linearGreen: .mockRandom(), linearBlue: .mockRandom(), opacity: .mockRandom())
    }
}

@available(iOS 13.0, *)
extension GraphicsImage: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        .init(contents: nil, scale: .mockAny(), unrotatedPixelSize: .mockAny(), orientation: .up, maskColor: .mockAny(), interpolation: .none)
    }

    public static func mockRandom() -> Self {
        let image: UIImage = .mockRandom()
        return .init(
            contents: image.cgImage.map { .init(cgImage: $0) },
            scale: image.scale,
            unrotatedPixelSize: .mockRandom(),
            orientation: .up,
            maskColor: .mockRandom(),
            interpolation: .none
        )
    }
}

#endif
