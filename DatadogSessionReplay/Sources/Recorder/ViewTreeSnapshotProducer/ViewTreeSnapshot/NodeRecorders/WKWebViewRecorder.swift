/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import WebKit

internal class WKWebViewRecorder: NodeRecorder {
    let identifier = UUID()

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let webView = view as? WKWebView else {
            return nil
        }

        guard attributes.isVisible else {
            return InvisibleElement.constant
        }

        let builder = WKWebViewWireframesBuilder(
            wireframeID: context.ids.nodeID(view: view, nodeRecorder: self),
            slotID: webView.configuration.userContentController.hash,
            attributes: attributes
        )

        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
    }
}

internal struct WKWebViewWireframesBuilder: NodeWireframesBuilder {
    let wireframeID: WireframeID
    /// The slot identifier of the webview controller.
    let slotID: Int
    /// Attributes of the `UIView`.
    let attributes: ViewAttributes

    var wireframeRect: CGRect {
        attributes.frame
    }

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        return [
            builder.createWebViewWireframe(
                id: wireframeID,
                frame: wireframeRect,
                slotId: String(slotID),
                borderColor: attributes.layerBorderColor,
                borderWidth: attributes.layerBorderWidth,
                backgroundColor: attributes.backgroundColor,
                cornerRadius: attributes.layerCornerRadius,
                opacity: attributes.alpha
            )
        ]
    }
}
#endif
