/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import WebKit

extension WKWebView {
    func sessionReplayContentFrame(from frame: CGRect) -> CGRect {
        guard let frameOffset = sessionReplayContentFrameOffset(for: frame) else {
            return frame
        }

        return frame.offsetBy(dx: 0, dy: frameOffset)
    }

    private func sessionReplayContentFrameOffset(for frame: CGRect) -> CGFloat? {
        // When `contentInsetAdjustmentBehavior` is set to `.automatic` or `.always`, WebKit
        // internally adjusts the web content viewport to account for safe area insets. This
        // creates a mismatch between the native frame position (which can start at y=0) and
        // where the web content actually renders (which starts below the safe area).
        //
        // To compensate for this, we need to offset the webview frame ensuring that:
        // - Native touch coordinates align with web content touch coordinates
        // - Web content from the Browser SDK integration displays at the expected position
        guard scrollView.contentInsetAdjustmentBehavior != .never else {
            return nil
        }

        let safeAreaTop = safeAreaInsets.top

        if frame.minY < safeAreaTop {
            // This offset is based on empirical testing and investigation.
            // WebKit appears to apply internal coordinate transformations that
            // create a mismatch between the native frame position and where web
            // content renders.
            // We don't fully understand the exact WebKit internal behavior causing
            // the issue, but applying this offset resolves the coordinate mismatch.
            return safeAreaTop / (window?.screen.scale ?? 1)
        }

        return nil
    }
}
#endif
