/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit
import WebKit

@preconcurrency import DatadogInternal

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot {
    /// State shared by all layers captured in one snapshot.
    final class Context {
        let textAndInputPrivacyLevel: TextAndInputPrivacyLevel
        let imagePrivacyLevel: ImagePrivacyLevel

        /// Weak references to web views found while capturing the layer tree.
        let webViewCache: NSHashTable<WKWebView>

        /// Weak references to embedded content views found while capturing the layer tree.
        let embeddedContentViewCache: NSHashTable<UIView>

        init(
            textAndInputPrivacyLevel: TextAndInputPrivacyLevel,
            imagePrivacyLevel: ImagePrivacyLevel,
            webViewCache: NSHashTable<WKWebView> = .weakObjects(),
            embeddedContentViewCache: NSHashTable<UIView> = .weakObjects()
        ) {
            self.textAndInputPrivacyLevel = textAndInputPrivacyLevel
            self.imagePrivacyLevel = imagePrivacyLevel
            self.webViewCache = webViewCache
            self.embeddedContentViewCache = embeddedContentViewCache
        }
    }
}
#endif
