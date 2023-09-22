/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

/// A type recording semantics of a given `UIView` or its subclasses. Different implementations of `NodeRecorder` should
/// recognise specialised subclasses of `UIView` and record their semantics accordingly.
///
/// **Note:** The `NodeRecorder` is used on the main thread by `Recorder`.
internal protocol NodeRecorder {
    /// Finds the semantic of given`view`.
    /// - Parameters:
    ///   - view: the `UIView` to determine semantics for
    ///   - attributes: attributes of this view inferred from its base `UIView` interface
    ///   - context: the context of recording current view-tree
    /// - Returns: the value of `NodeSemantics` or `nil` if the view is a member of view subclass other than the one this recorder is specialised for.
    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics?

    /// Unique identifier of the node recorder.
    var identifier: UUID { get }
}

/// A type producing SR wireframes.
///
/// Each type of UI element (e.g.: label, text field, toggle, button) should provide their own implementaion of `NodeWireframesBuilder`.
///
/// **Note:** The `NodeWireframesBuilder` is used on background thread by `Processor`.
internal protocol NodeWireframesBuilder {
    /// The frame of produced wireframe in screen coordinates.
    var wireframeRect: CGRect { get }

    /// Creates wireframes that are later uploaded to SR backend.
    /// - Parameter builder: the generic builder for constructing SR data models.
    /// - Returns: one or more wireframes that describe a node in SR.
    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe]
}
#endif
