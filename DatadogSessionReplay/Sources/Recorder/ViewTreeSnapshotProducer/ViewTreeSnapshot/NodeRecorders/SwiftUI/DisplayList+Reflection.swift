/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
import SwiftUI

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        items = try mirror.descendant("items")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.Identity: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        value = try mirror.descendant("value")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.Seed: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        value = try mirror.descendant("value")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.ViewRenderer: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        renderer = try mirror.descendant("renderer")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.ViewUpdater: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        viewCache = try mirror.descendant("viewCache")
        lastList = try mirror.descendant("lastList")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.Effect: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        switch (mirror.displayStyle, mirror.descendant(0)) {
        case (.enum("identity"), _):
            self = .identify

        case let (.enum("clip"), tuple as (SwiftUI.Path, SwiftUI.FillStyle, Any)):
            self = .clip(tuple.0, tuple.1)

        case (.enum("platformGroup"), _):
            self = .platformGroup

        default:
            self = .unknown
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.ViewUpdater.ViewCache: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        map = try mirror.descendant("map")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.ViewUpdater.ViewCache.Key: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        id = try mirror.descendant("id")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.Index.ID: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        identity = try mirror.descendant("identity")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.ViewUpdater.ViewInfo: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        // do not retain the views or layer, only get values required
        // for building wireframe

        let layer = try mirror.descendant(type: CALayer.self, "layer")
        // The view is the rendering context of an item
        let view = try mirror.descendant(type: UIView.self, "view")
        // The container view is where the item is actually rendered.
        // The container is usually the same as the view, except when applying
        // a `.platformGroup` effect. e.g: A `SwiftUI.ScrollView` will create a
        // `.platformGroup` effect where the `Content` is rendered in a `UIScrollView`,
        // in this case the container is the content of the `UIScrollView`.
        let container = try mirror.descendant(type: UIView.self, "container")

        // The frame is the container's frame in the view's coordinate space.
        // This is useful for applying the offset in a scroll-view.
        frame = container.convert(container.bounds, to: view)
        backgroundColor = layer.backgroundColor?.safeCast
        borderColor = layer.borderColor?.safeCast
        borderWidth = layer.borderWidth
        cornerRadius = layer.cornerRadius
        alpha = view.alpha
        isHidden = layer.isHidden
        intrinsicContentSize = container.intrinsicContentSize
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.Content: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        seed = try mirror.descendant("seed")
        value = try mirror.descendant("value")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.Content.Value: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        switch (mirror.displayStyle, mirror.descendant(0)) {
        case let (.enum("shape"), tuple as (SwiftUI.Path, Any, SwiftUI.FillStyle)):
            let paint = try ResolvedPaint(reflecting: tuple.1)
            self = .shape(tuple.0, paint, tuple.2)

        case let (.enum("text"), tuple as (Any, CGSize)):
            let view = try StyledTextContentView(reflecting: tuple.0)
            self = .text(view, tuple.1)

        case (.enum("platformView"), _):
            self = .platformView

        case (.enum("image"), _):
            self = .unknown

        case (.enum("drawing"), _):
            self = .unknown

        case let (.enum("color"), color):
            let color = try Color._Resolved(reflecting: color)
            self = .color(color)

        default:
            self = .unknown
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.Item: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        identity = try mirror.descendant("identity")
        frame = try mirror.descendant("frame")
        value = try mirror.descendant("value")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.Item.Value: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        switch (mirror.displayStyle, mirror.descendant(0)) {
        case let (.enum("effect"), tuple as (Any, Any)):
            let effect = try DisplayList.Effect(reflecting: tuple.0)
            let list = try DisplayList(reflecting: tuple.1)
            self = .effect(effect, list)

        case let (.enum("content"), value):
            let content = try DisplayList.Content(reflecting: value)
            self = .content(content)

        default:
            self = .unknown
        }
    }
}
#endif
