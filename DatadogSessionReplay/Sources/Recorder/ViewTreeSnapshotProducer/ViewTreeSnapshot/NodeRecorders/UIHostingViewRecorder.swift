/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
import UIKit
import SwiftUI
import DatadogInternal

@available(iOS 13, tvOS 13, *)
internal class UIHostingViewRecorder: NodeRecorder {
    let identifier: UUID

    let _UIGraphicsViewClass: AnyClass? = NSClassFromString("SwiftUI._UIGraphicsView")

    /// An option for overriding default semantics from parent recorder.
    var semanticsOverride: (UIView, ViewAttributes) -> NodeSemantics?
    var textObfuscator: (ViewTreeRecordingContext, ViewAttributes) -> TextObfuscating

    private let imageRenderer = ImageRenderer()

    private static let rendererKeyPath: [String] = if #available(iOS 26, tvOS 26, *) {
        ["_base", "viewGraph", "renderer"]
    } else if #available(iOS 18.1, tvOS 18.1, *) {
        ["_base", "renderer"]
    } else {
        ["renderer"]
    }

    init(
        identifier: UUID,
        semanticsOverride: @escaping (UIView, ViewAttributes) -> NodeSemantics? = { _, _ in nil },
        textObfuscator: @escaping (ViewTreeRecordingContext, ViewAttributes) -> TextObfuscating = { context, viewAttributes in
            return viewAttributes.resolveTextAndInputPrivacyLevel(in: context).staticTextObfuscator
        }
    ) {
        self.identifier = identifier
        self.semanticsOverride = semanticsOverride
        self.textObfuscator = textObfuscator
    }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        // Ignore views of type `SwiftUI._UIGraphicsView`
        if let cls = _UIGraphicsViewClass, type(of: view).isSubclass(of: cls) {
            return IgnoredElement(subtreeStrategy: .ignore)
        }

        do {
            let nodeID = context.ids.nodeID(view: view, nodeRecorder: self)
            return try semantics(reflecting: view, nodeID: nodeID, with: attributes, in: context)
        } catch {
            return nil
        }
    }

    func semantics(reflecting subject: AnyObject, nodeID: NodeID, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) throws -> NodeSemantics? {
        guard let renderer = extractObject(from: subject, keyPath: Self.rendererKeyPath) else {
            return nil
        }

        return try semantics(renderer: renderer, nodeID: nodeID, with: attributes, in: context)
    }

    private func semantics(renderer subject: Any, nodeID: NodeID, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) throws -> NodeSemantics {
        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        let reflector = Reflector(subject: subject, telemetry: context.recorder.telemetry)
        let renderer = try DisplayList.ViewRenderer(from: reflector)

        let builder = SwiftUIWireframesBuilder(
            wireframeID: nodeID,
            renderer: renderer.renderer,
            imageRenderer: imageRenderer,
            textObfuscator: textObfuscator(context, attributes),
            fontScalingEnabled: false,
            imagePrivacyLevel: attributes.resolveImagePrivacyLevel(in: context),
            attributes: attributes
        )

        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .record, nodes: [node])
    }

    private func extractObject(from subject: AnyObject, keyPath: [String]) -> AnyObject? {
        var current = subject
        for component in keyPath {
            guard
                let ivar = class_getInstanceVariable(type(of: current), component),
                let next = object_getIvar(current, ivar) as? AnyObject
            else {
                return nil
            }
            current = next
        }
        return current
    }
}

#endif
