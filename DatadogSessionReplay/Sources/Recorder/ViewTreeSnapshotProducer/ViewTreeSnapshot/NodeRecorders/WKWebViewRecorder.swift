/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import WebKit

internal class WKWebViewRecorder: NodeRecorder {
    internal let identifier: UUID

    init(identifier: UUID) {
        self.identifier = identifier
    }

    func semantics(of view: UIView, with attributes: ViewAttributes, in context: ViewTreeRecordingContext) -> NodeSemantics? {
        guard let webView = view as? WKWebView else {
            return nil
        }

        // Add the webview to cache
        context.webViewCache.add(webView)

        // Adjust the frame for webviews that extends beyond safe area (RUM-6227)
        var adjustedAttributes = attributes
        if let frameAdjustment = calculateFrameOffset(for: webView, with: attributes) {
            adjustedAttributes.frame = attributes.frame.offsetBy(dx: 0, dy: frameAdjustment)
        }

        let builder = WKWebViewWireframesBuilder(slotID: webView.hash, attributes: adjustedAttributes)
        let node = Node(viewAttributes: adjustedAttributes, wireframesBuilder: builder)
        return SpecificElement(subtreeStrategy: .ignore, nodes: [node])
    }

    private func calculateFrameOffset(
        for webView: WKWebView,
        with attributes: ViewAttributes
    ) -> CGFloat? {
        // When `contentInsetAdjustmentBehavior` is set to `.automatic` or `.always`, WebKit
        // internally adjusts the web content viewport to account for safe area insets. This
        // creates a mismatch between the native frame position (which can start at y=0) and
        // where the web content actually renders (which starts below the safe area).
        //
        // To compensate for this, we need to offset the webview frame ensuring that:
        // - Native touch coordinates align with web content touch coordinates
        // - Web content from the Browser SDK integration displays at the expected position
        guard webView.scrollView.contentInsetAdjustmentBehavior != .never else {
            return nil
        }

        let safeAreaTop = webView.safeAreaInsets.top

        if attributes.frame.minY < safeAreaTop {
            // This offset is based on empirical testing and investigation.
            // WebKit appears to apply internal coordinate transformations that
            // create a mismatch between the native frame position and where web
            // content renders.
            // We don't fully understand the exact WebKit internal behavior causing
            // the issue, but applying this offset resolves the coordinate mismatch.
            return safeAreaTop / (webView.window?.screen.scale ?? 1)
        }

        return nil
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
                clip: attributes.clip,
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
