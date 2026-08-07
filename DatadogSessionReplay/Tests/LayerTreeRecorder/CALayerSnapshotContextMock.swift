/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogInternal
import UIKit
import WebKit

@testable import DatadogSessionReplay

@available(iOS 13.0, tvOS 13.0, *)
extension CALayerSnapshot.Context {
    static func mockAny(
        textAndInputPrivacyLevel: TextAndInputPrivacyLevel = .maskAll,
        imagePrivacyLevel: ImagePrivacyLevel = .maskAll,
        webViewCache: NSHashTable<WKWebView> = .weakObjects(),
        embeddedContentViewCache: NSHashTable<UIView> = .weakObjects()
    ) -> Self {
        .init(
            textAndInputPrivacyLevel: textAndInputPrivacyLevel,
            imagePrivacyLevel: imagePrivacyLevel,
            webViewCache: webViewCache,
            embeddedContentViewCache: embeddedContentViewCache
        )
    }
}
#endif
