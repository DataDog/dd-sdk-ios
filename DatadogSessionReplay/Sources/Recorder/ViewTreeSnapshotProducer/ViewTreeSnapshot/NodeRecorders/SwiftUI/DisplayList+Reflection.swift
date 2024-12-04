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
    init(from reflector: Reflector) throws {
        items = try reflector.descendant("items")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.Identity: Reflection {
    init(from reflector: Reflector) throws {
        value = try reflector.descendant("value")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.Seed: Reflection {
    init(from reflector: Reflector) throws {
        value = try reflector.descendant("value")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.ViewRenderer: Reflection {
    init(from reflector: Reflector) throws {
        renderer = try reflector.descendant("renderer")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.ViewUpdater: Reflection {
    init(from reflector: Reflector) throws {
        viewCache = try reflector.descendant("viewCache")
        lastList = try reflector.descendant("lastList")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.Effect: Reflection {
    init(from reflector: Reflector) throws {
        switch (reflector.displayStyle, reflector.descendantIfPresent(0)) {
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
    init(from reflector: Reflector) throws {
        map = try reflector.descendant("map")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.ViewUpdater.ViewCache.Key: Reflection {
    init(from reflector: Reflector) throws {
        id = try reflector.descendant("id")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.Index.ID: Reflection {
    init(from reflector: Reflector) throws {
        identity = try reflector.descendant("identity")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.ViewUpdater.ViewInfo: Reflection {
    init(from reflector: Reflector) throws {
        // do not retain the views or layer, only get values required
        // for building wireframe

        let layer = try reflector.descendant(type: CALayer.self, "layer")
        // The view is the rendering context of an item
        let view = try reflector.descendant(type: UIView.self, "view")
        // The container view is where the item is actually rendered.
        // The container is usually the same as the view, except when applying
        // a `.platformGroup` effect. e.g: A `SwiftUI.ScrollView` will create a
        // `.platformGroup` effect where the `Content` is rendered in a `UIScrollView`,
        // in this case the container is the content of the `UIScrollView`.
        let container = try reflector.descendant(type: UIView.self, "container")

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
    init(from reflector: Reflector) throws {
        seed = try reflector.descendant("seed")
        value = try reflector.descendant("value")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.Content.Value: Reflection {
    init(from reflector: Reflector) throws {
        switch (reflector.displayStyle, reflector.descendantIfPresent(0)) {
        case let (.enum("shape"), tuple as (SwiftUI.Path, Any, SwiftUI.FillStyle)):
            self = try .shape(tuple.0, reflector.reflect(tuple.1), tuple.2)

        case let (.enum("text"), tuple as (Any, CGSize)):
            self = try .text(reflector.reflect(tuple.0), tuple.1)

        case (.enum("platformView"), _):
            self = .platformView

        case let (.enum("image"), image):
            self = try .image(reflector.reflect(image))

        case (.enum("drawing"), _):
            self = .unknown

        case let (.enum("color"), color):
            self = try .color(reflector.reflect(color))

        default:
            self = .unknown
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.Item: Reflection {
    init(from reflector: Reflector) throws {
        identity = try reflector.descendant("identity")
        frame = try reflector.descendant("frame")
        value = try reflector.descendant("value")
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension DisplayList.Item.Value: Reflection {
    init(from reflector: Reflector) throws {
        switch (reflector.displayStyle, reflector.descendantIfPresent(0)) {
        case let (.enum("effect"), tuple as (Any, Any)):
            self = try .effect(
                reflector.reflect(tuple.0),
                reflector.reflect(tuple.1)
            )

        case let (.enum("content"), value):
            self = try .content(reflector.reflect(value))

        default:
            self = .unknown
        }
    }
}
#endif
