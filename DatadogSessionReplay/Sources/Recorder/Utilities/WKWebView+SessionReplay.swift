/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import WebKit

internal extension WKWebView {
    // Adjust the frame for webviews that extends beyond safe area (RUM-6227)
    func contentInsetAdjustedFrame(for frame: CGRect) -> CGRect {
        // When `contentInsetAdjustmentBehavior` is set to `.automatic` or `.always`, WebKit
        // internally adjusts the web content viewport to account for safe area insets. This
        // creates a mismatch between the native frame position (which can start at y=0) and
        // where the web content actually renders (which starts below the safe area).
        //
        // To compensate for this, we need to offset the webview frame ensuring that:
        // - Native touch coordinates align with web content touch coordinates
        // - Web content from the Browser SDK integration displays at the expected position
        guard
            scrollView.contentInsetAdjustmentBehavior != .never,
            frame.minY < safeAreaInsets.top
        else {
            return frame
        }

        let offset = safeAreaInsets.top / (window?.screen.scale ?? 1)
        return frame.offsetBy(dx: 0, dy: offset)
    }
}
#endif
