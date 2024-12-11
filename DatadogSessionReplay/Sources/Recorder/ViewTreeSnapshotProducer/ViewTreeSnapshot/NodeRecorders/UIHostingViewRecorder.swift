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
    var textObfuscator: (ViewTreeRecordingContext) -> TextObfuscating

    init(
        identifier: UUID,
        semanticsOverride: @escaping (UIView, ViewAttributes) -> NodeSemantics? = { _, _ in nil },
        textObfuscator: @escaping (ViewTreeRecordingContext) -> TextObfuscating = { context in
            return context.recorder.textAndInputPrivacy.staticTextObfuscator
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
            return try semantics(refelecting: view, nodeID: nodeID, with: attributes, in: context)
        } catch {
            return nil
        }
    }

    func semantics(refelecting subject: AnyObject, nodeID: NodeID, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) throws -> NodeSemantics? {
        guard
            let ivar = class_getInstanceVariable(type(of: subject), "renderer"),
            let renderer = object_getIvar(subject, ivar) as? AnyObject
        else {
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
            textObfuscator: textObfuscator(context),
            fontScalingEnabled: false,
            imagePrivacyLevel: context.recorder.imagePrivacy,
            attributes: attributes
        )

        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .record, nodes: [node])
    }
}

@available(iOS 18, tvOS 18, *)
internal class iOS18HostingViewRecorder: UIHostingViewRecorder {
    override func semantics(refelecting subject: AnyObject, nodeID: NodeID, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) throws -> NodeSemantics? {
        guard
            let ivar = class_getInstanceVariable(type(of: subject), "_base"),
            let _base = object_getIvar(subject, ivar) as? AnyObject
        else {
            return nil
        }

        return try super.semantics(refelecting: _base, nodeID: nodeID, with: attributes, in: context)
    }
}

#endif
