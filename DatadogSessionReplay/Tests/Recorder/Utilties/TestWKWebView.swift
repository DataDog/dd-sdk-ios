/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit
import WebKit

final class TestWKWebView: WKWebView {
    var testSafeAreaInsets: UIEdgeInsets = .zero

    override var safeAreaInsets: UIEdgeInsets {
        testSafeAreaInsets
    }

    init(
        topSafeAreaInset: CGFloat = 0,
        contentInsetAdjustmentBehavior: UIScrollView.ContentInsetAdjustmentBehavior = .automatic
    ) {
        super.init(frame: .zero, configuration: WKWebViewConfiguration())
        testSafeAreaInsets = UIEdgeInsets(top: topSafeAreaInset, left: 0, bottom: 0, right: 0)
        scrollView.contentInsetAdjustmentBehavior = contentInsetAdjustmentBehavior
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
#endif
