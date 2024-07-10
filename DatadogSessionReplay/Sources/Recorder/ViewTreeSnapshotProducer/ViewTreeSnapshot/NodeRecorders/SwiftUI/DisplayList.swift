/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

#if os(iOS) && canImport(SwiftUI)
import SwiftUI
import UIKit
import QuartzCore

/// The `DisplayList` is a reflection of the private `SwiftUI.DisplayList`.
///
/// All inner types strictly follow naming and structure of private `SwiftUI` definitions.
@available(iOS 13.0, *)
internal struct DisplayList {
    internal struct Identity: Hashable {
        let value: UInt32
    }

    internal struct Seed: Hashable {
        let value: UInt16
    }

    internal struct ViewRenderer {
        let renderer: ViewUpdater
    }

    internal struct ViewUpdater {
        /// The view cache maps an items from the display tree
        /// to a platform view.
        internal struct ViewCache {
            internal struct Key: Hashable {
                let id: Index.ID
            }

            let map: [ViewCache.Key: ViewInfo]
        }

        internal struct ViewInfo {
            /// Original view's `.backgorundColor`.
            let backgroundColor: CGColor?

            /// Original view's `layer.borderColor`.
            let borderColor: CGColor?

            /// Original view's `layer.borderWidth`.
            let borderWidth: CGFloat

            /// Original view's `layer.cornerRadius`.
            let cornerRadius: CGFloat

            /// Original view's `.alpha` (between `0.0` and `1.0`).
            let alpha: CGFloat

            /// Original view's `.isHidden`.
            let isHidden: Bool

            /// Original view's `.intrinsicContentSize`.
            let intrinsicContentSize: CGSize
        }

        /// The view cache holds references to UIKit instances.
        ///
        /// Children must be reflected on the main thread to inspect values
        /// without retaining views or layers references.
        let viewCache: ViewCache

        /// The display list reflects the SwiftUI rendering tree.
        ///
        /// Reflection is made lazely and can be performed on a
        /// background thread.
        let lastList: DisplayList.Lazy
    }

    internal struct Index {
        internal struct ID: Hashable {
            let identity: Identity
        }
    }

    internal enum Effect {
        case identify
        case clip(SwiftUI.Path, SwiftUI.FillStyle)
        case unknown
    }

    /// The content of a leaf item in the display list.
    internal struct Content {
        internal enum Value {
            case shape(SwiftUI.Path, ResolvedPaint, SwiftUI.FillStyle)
            case text(StyledTextContentView, CGSize)
            case platformView
            case color(Color._Resolved)
            case image(GraphicsImage)
            case unknown
        }

        let seed: Seed
        let value: Value
    }

    /// An item is an element of the displayed tree in `SwiftUI`.
    ///
    /// The item has a unique identity, a frame in the current branch, and a value.
    /// A value can be:
    /// - An effect (node): which applied an effect on a sub-tree.
    /// - A content (leaf): The content of the displayed item.
    internal struct Item {
        internal enum Value {
            case effect(Effect, DisplayList)
            case content(Content)
            case unknown
        }

        let identity: Identity
        let frame: CGRect
        let value: Value
    }

    let items: [Item]
}

@available(iOS 13.0, *)
extension DisplayList: Reflection {
    init(_ mirror: Mirror) throws {
        items = try mirror.descendant(path: "items")
    }
}

@available(iOS 13.0, *)
extension DisplayList.Identity: Reflection {
    init(_ mirror: Mirror) throws {
        value = try mirror.descendant(path: "value")
    }
}

@available(iOS 13.0, *)
extension DisplayList.Seed: Reflection {
    init(_ mirror: Mirror) throws {
        value = try mirror.descendant(path: "value")
    }
}

@available(iOS 13.0, *)
extension DisplayList.ViewRenderer: Reflection {
    init(_ mirror: Mirror) throws {
        renderer = try mirror.descendant(path: "renderer")
    }
}

@available(iOS 13.0, *)
extension DisplayList.ViewUpdater: Reflection {
    init(_ mirror: Mirror) throws {
        viewCache = try mirror.descendant(path: "viewCache")
        lastList = try mirror.descendant(path: "lastList")
    }
}

@available(iOS 13.0, *)
extension DisplayList.Effect: Reflection {
    init(_ mirror: Mirror) throws {
        if let _ = mirror.descendant("identity") {
            self = .identify // never reached: because enum case has no associated value
        } else if let (path, style, _) = mirror.descendant("clip") as? (SwiftUI.Path, SwiftUI.FillStyle, Any) {
            self = .clip(path, style)
        } else {
            self = .unknown
        }
    }
}

@available(iOS 13.0, *)
extension DisplayList.ViewUpdater.ViewCache: Reflection {
    init(_ mirror: Mirror) throws {
        map = try mirror.descendant(path: "map")
    }
}

@available(iOS 13.0, *)
extension DisplayList.ViewUpdater.ViewCache.Key: Reflection {
    init(_ mirror: Mirror) throws {
        id = try mirror.descendant(path: "id")
    }
}

@available(iOS 13.0, *)
extension DisplayList.Index.ID: Reflection {
    init(_ mirror: Mirror) throws {
        identity = try mirror.descendant(path: "identity")
    }
}

@available(iOS 13.0, *)
extension DisplayList.ViewUpdater.ViewInfo: Reflection {
    init(_ mirror: Mirror) throws {
        let view = try mirror.descendant(UIView.self, path: "view")

        // do not retain the view, only get values required
        // for building wireframes
        backgroundColor = view.layer.backgroundColor?.safeCast
        borderColor = view.layer.borderColor?.safeCast
        borderWidth = view.layer.borderWidth
        cornerRadius = view.layer.cornerRadius
        alpha = view.alpha
        isHidden = view.layer.isHidden
        intrinsicContentSize = view.intrinsicContentSize
    }
}

@available(iOS 13.0, *)
extension DisplayList.Content: Reflection {
    init(_ mirror: Mirror) throws {
        seed = try mirror.descendant(path: "seed")
        value = try mirror.descendant(path: "value")
    }
}

@available(iOS 13.0, *)
extension DisplayList.Content.Value: Reflection {
    init(_ mirror: Mirror) throws {
        if let tuple = mirror.descendant("shape") as? (SwiftUI.Path, Any, SwiftUI.FillStyle) {
            let paint = try ResolvedPaint(reflecting: tuple.1)
            self = .shape(tuple.0, paint, tuple.2)
        } else if let tuple = mirror.descendant("text") as? (Any, CGSize) {
            let view = try StyledTextContentView(reflecting: tuple.0)
            self = .text(view, tuple.1)
        } else if let _ = mirror.descendant("platformView") {
            self = .platformView
        } else if let any = mirror.descendant("color") {
            let content = try Color._Resolved(reflecting: any)
            self = .color(content)
        } else if let any = mirror.descendant("image") {
            let image = try GraphicsImage(reflecting: any)
            self = .image(image)
        } else {
            self = .unknown
        }
    }
}

@available(iOS 13.0, *)
extension DisplayList.Item: Reflection {
    init(_ mirror: Mirror) throws {
        identity = try mirror.descendant(path: "identity")
        frame = try mirror.descendant(path: "frame")
        value = try mirror.descendant(path: "value")
    }
}

@available(iOS 13.0, *)
extension DisplayList.Item.Value: Reflection {
    init(_ mirror: Mirror) throws {
        if let tuple = mirror.descendant("effect") as? (Any, Any) {
            let effect = try DisplayList.Effect(reflecting: tuple.0)
            let list = try DisplayList(reflecting: tuple.1)
            self = .effect(effect, list)
        } else if let any = mirror.descendant("content") {
            let content = try DisplayList.Content(reflecting: any)
            self = .content(content)
        } else {
            self = .unknown
        }
    }
}

#endif
