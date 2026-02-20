/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore
import UIKit
import WebKit

@available(iOS 13.0, tvOS 13.0, *)
extension LayerSnapshot {
    enum Semantics: Sendable, Equatable {
        case generic
        case webView(slotID: Int)

        enum SubtreeStrategy: Sendable {
            case record
            case ignore
        }

        var subtreeStrategy: SubtreeStrategy {
            switch self {
            case .generic:
                return .record
            case .webView:
                return .ignore
            }
        }
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension CALayer {
    @MainActor
    func semantics(in context: LayerSnapshotContext) -> LayerSnapshot.Semantics {
        if let webView = delegate as? WKWebView {
            context.webViewCache.add(webView)
            return .webView(slotID: webView.hash)
        }

        return .generic
    }
}
#endif
