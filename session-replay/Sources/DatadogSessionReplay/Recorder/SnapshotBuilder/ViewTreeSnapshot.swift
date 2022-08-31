/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import CoreGraphics
import UIKit

/// The `ViewTreeSnapshot` is an intermediate representation of the app UI in Session Replay
/// recording: [views hierarchy] → [`ViewTreeSnapshot`] → [wireframes].
///
/// Although it's being built from the actual views hierarchy, it doesn't correspond 1:1 to it. Similarly,
/// it doesn't translate 1:1 into wireframes that get uploaded to the SR BE. Instead, it provides its
/// own description of the view hierarchy, which can be optimised for efficiency in SR recorder (e.g. unlike
/// the real views hierarchy, `ViewTreeSnapshot` is meant to be safe when accesed on a background thread).
internal struct ViewTreeSnapshot {
    /// The time of taking this snapshot.
    let date: Date

    /// The node indicating the root view of this snapshot.
    let root: Node
}

/// An individual node in `ViewTreeSnapshot`. It abstracts an individual view or part of views hierarchy.
///
/// The `Node` can describe a view by nesting nodes for each of its subviews OR it can abstract the view along with its childs
/// by merging their information into single node. This stands for the key difference between the hierarchy of native views and
/// hierarchy of nodes - typically there is significantly less nodes than number of native views they describe.
///
/// **Note:** The purpose of this structure is to be lightweight and create minimal overhead when the view-tree
/// is captured on the main thread (the `Recorder` constantly creates `Nodes` for views residing in the hierarchy).
internal struct Node {
    /// Attributes of the `UIView` that this node was created for.
    let viewAttributes: ViewAttributes

    /// The semantics of this node.
    let semantics: NodeSemantics

    /// Nodes created for subviews of this node's `UIView`.
    let children: [Node]
}

/// Attributes of the `UIView` that the node was created for.
///
/// It is used by the `Recorder` to capture view attributes on the main thread.
/// It enforces immutability for later (thread safe) access from background queue in `Processor`.
internal struct ViewAttributes: Equatable {
    /// The view's `frame`, in VTS's root view's coordinate space (usually, the screen coordinate space).
    let frame: CGRect

    /// Original view's `.backgorundColor`.
    let backgroundColor: CGColor?

    /// Original view's `layer.backgorundColor`.
    let layerBorderColor: CGColor?

    /// Original view's `layer.backgorundColor`.
    let layerBorderWidth: CGFloat

    /// Original view's `layer.cornerRadius`.
    let layerCornerRadius: CGFloat

    /// Original view's `.alpha` (between `0.0` and `1.0`).
    let alpha: CGFloat

    /// Original view's `.intrinsicContentSize`.
    let intrinsicContentSize: CGSize

    /// If the view is visible (considering: alpha + hidden state + non-zero frame).
    ///
    /// Example: A can be not visible if it has `.zero` size or it is fully transparent.
    let isVisible: Bool

    /// If the view has any visible appearance (considering: background color + border style)
    ///
    /// Example: A view might have no appearance if it has `0` border width and transparent fill color.
    let hasAnyAppearance: Bool
}

extension ViewAttributes {
    init(frameInRootView: CGRect, view: UIView) {
        self.frame = frameInRootView
        self.backgroundColor = view.backgroundColor?.cgColor
        self.layerBorderColor = view.layer.borderColor
        self.layerBorderWidth = view.layer.borderWidth
        self.layerCornerRadius = view.layer.cornerRadius
        self.intrinsicContentSize = view.intrinsicContentSize
        self.alpha = view.alpha

        let hasBorderAppearance: Bool = {
            guard view.layer.borderWidth > 0, let borderAlpha = view.layer.borderColor?.alpha else {
                return false
            }
            return borderAlpha > 0
        }()

        let hasFillAppearance: Bool = {
            guard let fillAlpha = view.backgroundColor?.cgColor.alpha else {
                return false
            }
            return fillAlpha > 0
        }()

        self.isVisible = !view.isHidden && view.alpha > 0 && frame != .zero
        self.hasAnyAppearance = self.isVisible && (hasBorderAppearance || hasFillAppearance)
    }
}

/// A type denoting semantics of given UI element in Session Replay.
///
/// The `NodeSemantics` is attached to each node produced by `Recorder`. During tree traversal,
/// views are queried in available node recorders. Each `NodeRecorder` inspects the view object and
/// tries to infer its identity (a `NodeSemantics`).
///
/// There are two `NodeSemantics` that describe the identity of UI element:
/// - `AmbiguousElement` - element is of `UIView` class and we only know its base attributes (the real identity could be ambiguous);
/// - `SpecificElement` - element is one of `UIView` subclasses and we know its specific identity along with set of subclass-specific
/// attributes (e.g. text in `UILabel` or the "on" / "off" state of `UISwitch` control).
///
/// Additionally, there are two utility semantics that control the processing of nodes in SR:
/// - `InvisibleElement` - element is either `UIView` or one of its known subclasses, but it has no visual appearance in SR, so it can
/// be safely ignored in `Recorder` or `Processor` (e.g. a `UILabel` with no text, no border and fully transparent color).
/// - `UnknownElement` - the element is of unknown kind, which could indicate an error during view tree traversal (e.g. working on
/// assumption that is not met).
///
/// Both `AmbiguousElement` and `SpecificElement` provide an implementation of `NodeWireframesBuilder` which describes
/// how to construct SR wireframes for UI elements they refer to. No builder is provided for `InvisibleElement` and `UnknownElement`.
internal protocol NodeSemantics {
    /// The severity of this semantic.
    ///
    /// While querying certain `view` with an array of supported `NodeRecorders` each recorder can spot different semantics of
    /// the same view. In that case, the semantics with higher `importance` takes precedence.
    static var importance: Int { get }

    /// A type defining how to build SR wireframes for the UI element this semantic was recorded for.
    var wireframesBuilder: NodeWireframesBuilder? { get }
}

extension NodeSemantics {
    /// The severity of this semantic.
    ///
    /// While querying certain `view` with an array of supported `NodeRecorders` each recorder can spot different semantics of
    /// the same view. In that case, the semantics with higher `importance` takes precedence.
    var importance: Int { Self.importance }
}

/// Semantics of an UI element that is of unknown kind. Receiving this semantics in `Processor` could indicate an error
/// in view-tree traversal performed in `Recorder` (e.g. working on assumption that is not met).
internal struct UnknownElement: NodeSemantics {
    static let importance: Int = .min
    let wireframesBuilder: NodeWireframesBuilder? = nil

    /// Use `UnknownElement.constant` instead.
    fileprivate init () {}

    /// A constant value of `UnknownElement` semantics.
    static let constant = UnknownElement()
}

/// A semantics of an UI element that is either `UIView` or one of its known subclasses. This semantics mean that the element
/// has no visual appearance that can be presented in SR (e.g. a `UILabel` with no text, no border and fully transparent color).
/// Nodes with this semantics can be safely ignored in `Recorder` or in `Processor`.
internal struct InvisibleElement: NodeSemantics {
    static let importance: Int = 0
    let wireframesBuilder: NodeWireframesBuilder? = nil

    /// Use `InvisibleElement.constant` instead.
    fileprivate init () {}

    /// A constant value of `InvisibleElement` semantics.
    static let constant = InvisibleElement()
}

/// A semantics of an UI element that is of `UIView` type. This semantics mean that the element has visual appearance in SR, but
/// it will only utilize its base `UIView` attributes. The full identity of the node will remain ambiguous if not overwritten with `SpecificElement`.
internal struct AmbiguousElement: NodeSemantics {
    static let importance: Int = 1
    let wireframesBuilder: NodeWireframesBuilder?
}

/// A semantics of an UI element that is one of `UIView` subclasses. This semantics mean that we know its full identity along with set of
/// subclass-specific attributes that will be used to render it in SR (e.g. all base `UIView` attributes plus the text in `UILabel` or the
/// "on" / "off" state of `UISwitch` control).
internal struct SpecificElement: NodeSemantics {
    static let importance: Int = .max
    let wireframesBuilder: NodeWireframesBuilder?
}
