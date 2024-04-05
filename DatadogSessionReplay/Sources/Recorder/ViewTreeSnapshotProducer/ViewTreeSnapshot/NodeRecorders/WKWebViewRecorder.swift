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
        guard let webview = view as? WKWebView else {
            return nil
        }

        // Record all webviews regardless of their visibility
        let slot = WKWebViewSlot(webview: webview)
        // Add or update the webview slot in cache
        context.webviewCache.update(slot)

        let builder = WKWebViewWireframesBuilder(slot: slot, attributes: attributes)
        let node = Node(viewAttributes: attributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
    }
}

/// The slot recorded for a `WKWebView`.
internal struct WKWebViewSlot: WebViewSlot {
    /// Weak reference to the web view represented by this slot.
    ///
    /// If the webview become `nil`, the slot will diseappear at the
    /// next recording cycle during `reset`
    weak var webview: WKWebView?

    /// The slot id.
    let id: Int

    init(webview: WKWebView) {
        self.webview = webview
        self.id = webview.hash
    }

    func purge() -> WebViewSlot? {
        webview.map(WKWebViewSlot.init(webview:))
    }
}

internal struct WKWebViewWireframesBuilder: NodeWireframesBuilder {
    /// The webview slot.
    let slot: WebViewSlot

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
                id: slot.id,
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
