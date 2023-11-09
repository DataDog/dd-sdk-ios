/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
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
    /// The recorder context containing RUM information from the moment of taking this snapshot.
    let context: Recorder.Context
    /// The size of a viewport in this snapshot.
    let viewportSize: CGSize
    /// An array of nodes recorded for this snapshot - sequenced in DFS order.
    let nodes: [Node]
}

/// An individual node in `ViewTreeSnapshot`. A `Node` describes a single view - similar: an array of nodes describes
/// view and its subtree (in depth-first order).
///
/// Typically, to describe certain view-tree we need significantly less nodes than number of views, because some views
/// are meaningless for session replay (e.g. hidden views or containers with no appearance).
///
/// **Note:** The purpose of this structure is to be lightweight and create minimal overhead when the view-tree
/// is captured on the main thread (the `Recorder` constantly creates `Nodes` for views residing in the hierarchy).
@_spi(Internal)
public struct SessionReplayNode {
    /// Attributes of the `UIView` that this node was created for.
    public let viewAttributes: SessionReplayViewAttributes
    /// A type defining how to build SR wireframes for the UI element described by this node.
    public let wireframesBuilder: SessionReplayNodeWireframesBuilder

    public init(viewAttributes: SessionReplayViewAttributes, wireframesBuilder: SessionReplayNodeWireframesBuilder) {
        self.viewAttributes = viewAttributes
        self.wireframesBuilder = wireframesBuilder
    }
}

// This alias enables us to have a more unique name exposed through public-internal access level
internal typealias Node = SessionReplayNode

/// Attributes of the `UIView` that the node was created for.
///
/// It is used by the `Recorder` to capture view attributes on the main thread.
/// It enforces immutability for later (thread safe) access from background queue in `Processor`.
@_spi(Internal)
public struct SessionReplayViewAttributes: Equatable {
    /// The view's `frame`, in VTS's root view's coordinate space (usually, the screen coordinate space).
    public let frame: CGRect

    /// Original view's `.backgorundColor`.
    public let backgroundColor: CGColor?

    /// Original view's `layer.borderColor`.
    public let layerBorderColor: CGColor?

    /// Original view's `layer.borderWidth`.
    public let layerBorderWidth: CGFloat

    /// Original view's `layer.cornerRadius`.
    public let layerCornerRadius: CGFloat

    /// Original view's `.alpha` (between `0.0` and `1.0`).
    public let alpha: CGFloat

    /// Original view's `.isHidden`.
    let isHidden: Bool

    /// Original view's `.intrinsicContentSize`.
    let intrinsicContentSize: CGSize

    /// If the view is technically visible (different than `!isHidden` because it also considers `alpha` and `frame != .zero`).
    /// A view can be technically visible, but it may have no appearance in practise (e.g. if its colors use `0` alpha component).
    ///
    /// Example 1: A view is invisible if it has `.zero` size or it is fully transparent (`alpha == 0`).
    /// Example 2: A view can be visible if it has fully transparent background color, but its `alpha` is `0.5` or it occupies non-zero area.
    var isVisible: Bool { !isHidden && alpha > 0 && frame != .zero }

    /// If the view has any visible appearance (considering: background color + border style).
    /// In other words: if this view brings anything visual.
    ///
    /// Example: A view might have no appearance if it has `0` border width and transparent fill color.
    var hasAnyAppearance: Bool {
        let borderAlpha = layerBorderColor?.alpha ?? 0
        let hasBorderAppearance = layerBorderWidth > 0 && borderAlpha > 0

        let fillAlpha = backgroundColor?.alpha ?? 0
        let hasFillAppearance = fillAlpha > 0

        return isVisible && (hasBorderAppearance || hasFillAppearance)
    }

    /// If the view is translucent, meaining if any content underneath it can be seen.
    ///
    /// Example 1: A view with blue background of alpha `0.5` is considered "translucent".
    /// Example 2: A view with blue semi-transparent background, but alpha `1` is also conisdered "translucent".
    var isTranslucent: Bool { !isVisible || alpha < 1 || backgroundColor?.alpha ?? 0 < 1 }
}

// This alias enables us to have a more unique name exposed through public-internal access level
internal typealias ViewAttributes = SessionReplayViewAttributes

extension ViewAttributes {
    init(frameInRootView: CGRect, view: UIView) {
        self.frame = frameInRootView
        self.backgroundColor = view.backgroundColor?.cgColor.safeCast
        self.layerBorderColor = view.layer.borderColor?.safeCast
        self.layerBorderWidth = view.layer.borderWidth
        self.layerCornerRadius = view.layer.cornerRadius
        self.alpha = view.alpha
        self.isHidden = view.isHidden
        self.intrinsicContentSize = view.intrinsicContentSize
    }
}

/// A type defining semantics of portion of view-tree hierarchy (one or more `Nodes`).
///
/// It is leveraged during view-tree traversal in `Recorder`:
/// - for each view, a sequence of `NodeRecorders` is queried to find best semantics of the view and its subtree;
/// - if multiple `NodeRecorders` find few semantics, the one with higher `.importance` is used;
/// - each `NodeRecorder` can construct `semantic.nodes` according to its own routines, in particular:
///     - it can create virtual nodes that define custom wireframes;
///     - it can use other node recorders to tarverse the subtree of certain view and find `semantic.nodes` with custom rules;
///     - it can return `semantic.nodes` and ask parent recorder to traverse the rest of subtree following global rules (`subtreeStrategy: .record`).
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
@_spi(Internal)
public protocol SessionReplayNodeSemantics {
    /// The severity of this semantic.
    ///
    /// While querying certain `view` with an array of supported `NodeRecorders` each recorder can spot different semantics of
    /// the same view. In that case, the semantics with higher `importance` takes precedence.
    static var importance: Int { get }

    /// Defines the strategy which `Recorder` should apply to subtree of this node.
    var subtreeStrategy: SessionReplayNodeSubtreeStrategy { get }
    /// Nodes that share this semantics.
    var nodes: [SessionReplayNode] { get }
}

// This alias enables us to have a more unique name exposed through public-internal access level
internal typealias NodeSemantics = SessionReplayNodeSemantics

extension NodeSemantics {
    /// The severity of this semantic.
    ///
    /// While querying certain `view` with an array of supported `NodeRecorders` each recorder can spot different semantics of
    /// the same view. In that case, the semantics with higher `importance` takes precedence.
    var importance: Int { Self.importance }
}

// This alias enables us to have a more unique name exposed through public-internal access level
internal typealias NodeSubtreeStrategy = SessionReplayNodeSubtreeStrategy

/// Strategies for handling node's subtree by `Recorder`.
@_spi(Internal)
public enum SessionReplayNodeSubtreeStrategy {
    /// Continue traversing subtree of this node to record nested nodes automatically.
    ///
    /// This strategy is particularly useful for semantics that do not make assumption on node's content (e.g. this strategy can be
    /// practical choice for `UITabBar` node to let the recorder automatically capture any labels, images or shapes that are displayed in it).
    case record
    /// Do not enter the subtree of this node.
    ///
    /// This strategy should be used for semantics that fully describe certain elements (e.g. it doesn't make sense to traverse the subtree of `UISwitch`).
    case ignore
}

/// Semantics of an UI element that is of unknown kind. Receiving this semantics in `Processor` could indicate an error
/// in view-tree traversal performed in `Recorder` (e.g. working on assumption that is not met).
internal struct UnknownElement: NodeSemantics {
    static let importance: Int = .min
    let subtreeStrategy: NodeSubtreeStrategy = .record
    let nodes: [Node] = []

    /// Use `UnknownElement.constant` instead.
    private init () {}

    /// A constant value of `UnknownElement` semantics.
    static let constant = UnknownElement()
}

/// A semantics of an UI element that is either `UIView` or one of its known subclasses. This semantics mean that the element
/// has no visual appearance that can be presented in SR (e.g. a `UILabel` with no text, no border and fully transparent color).
/// Unlike `IgnoredElement`, this semantics can be overwritten with another one with higher importance. This means that even
/// if the root view of certain element has no appearance, other node recorders will continue checking it for strictkier semantics.
@_spi(Internal)
public struct SessionReplayInvisibleElement: SessionReplayNodeSemantics {
    public static let importance: Int = 0
    public let subtreeStrategy: SessionReplayNodeSubtreeStrategy
    public let nodes: [SessionReplayNode] = []

    /// Use `InvisibleElement.constant` instead.
    private init () {
        self.subtreeStrategy = .ignore
    }

    init(subtreeStrategy: NodeSubtreeStrategy) {
        self.subtreeStrategy = subtreeStrategy
    }

    /// A constant value of `InvisibleElement` semantics.
    public static let constant = SessionReplayInvisibleElement()
}

// This alias enables us to have a more unique name exposed through public-internal access level
internal typealias InvisibleElement = SessionReplayInvisibleElement

/// A semantics of an UI element that should be ignored when traversing view-tree. Unlike `InvisibleElement` this semantics cannot
/// be overwritten by any other. This means that next node recorders won't be asked for further check of a strictkier semantics.
internal struct IgnoredElement: NodeSemantics {
    static var importance: Int = .max
    let subtreeStrategy: NodeSubtreeStrategy
    let nodes: [Node] = []
}

/// A semantics of an UI element that is of `UIView` type. This semantics mean that the element has visual appearance in SR, but
/// it will only utilize its base `UIView` attributes. The full identity of the node will remain ambiguous if not overwritten with `SpecificElement`.
///
/// The view-tree traversal algorithm will continue visiting the subtree of given `UIView` if it has `AmbiguousElement` semantics.
internal struct AmbiguousElement: NodeSemantics {
    static let importance: Int = 0
    let subtreeStrategy: NodeSubtreeStrategy = .record
    let nodes: [Node]
}

/// A semantics of an UI element that is one of `UIView` subclasses. This semantics mean that we know its full identity along with set of
/// subclass-specific attributes that will be used to render it in SR (e.g. all base `UIView` attributes plus the text in `UILabel` or the
/// "on" / "off" state of `UISwitch` control).
@_spi(Internal)
public struct SessionReplaySpecificElement: SessionReplayNodeSemantics {
    public static let importance: Int = .max
    public let subtreeStrategy: SessionReplayNodeSubtreeStrategy
    public let nodes: [SessionReplayNode]

    public init(subtreeStrategy: SessionReplayNodeSubtreeStrategy, nodes: [SessionReplayNode]) {
        self.subtreeStrategy = subtreeStrategy
        self.nodes = nodes
    }
}

// This alias enables us to have a more unique name exposed through public-internal access level
internal typealias SpecificElement = SessionReplaySpecificElement
#endif
