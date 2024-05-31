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

        let span = startSpan()
        defer { span.end() }

        // Add the webview to cache
        context.webViewCache.add(webView)

        let builder = WKWebViewWireframesBuilder(slotID: webView.hash, attributes: attributes)
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
    }
}

internal struct WKWebViewWireframesBuilder: NodeWireframesBuilder {
    /// The webview slot ID.
    let slotID: Int

    let attributes: ViewAttributes

    var wireframeRect: CGRect { attributes.frame }

    func buildWireframes(with builder: WireframesBuilder) -> [SRWireframe] {
        guard attributes.isVisible else {
            // ignore hidden webview, the wireframes will be built
            // for hidden slot
            return []
        }

        return [
            builder.visibleWebViewWireframe(
                id: slotID,
                frame: attributes.frame,
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
