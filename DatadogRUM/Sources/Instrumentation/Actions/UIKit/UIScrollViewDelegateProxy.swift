/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(tvOS)

import UIKit

/// A proxy that wraps the original UIScrollView delegate to intercept scroll lifecycle events
/// while forwarding all calls to the original delegate transparently.
internal final class UIScrollViewDelegateProxy: NSObject, UIScrollViewDelegate {
    /// The original delegate receiving forwarded calls.
    weak var originalDelegate: UIScrollViewDelegate?

    /// The handler notified of scroll lifecycle events.
    let handler: UIScrollViewScrollHandler

    init(
        originalDelegate: UIScrollViewDelegate?,
        handler: UIScrollViewScrollHandler
    ) {
        self.handler = handler
        self.originalDelegate = originalDelegate
        super.init()
    }

    // MARK: - UIScrollViewDelegate (intercepted)

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        handler.scrollViewWillBeginDragging(scrollView)
        originalDelegate?.scrollViewWillBeginDragging?(scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        handler.scrollViewDidEndDragging(scrollView, willDecelerate: decelerate)
        originalDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        handler.scrollViewDidEndDecelerating(scrollView)
        originalDelegate?.scrollViewDidEndDecelerating?(scrollView)
    }

    // MARK: - Forwarding

    // swiftlint:disable:next implicitly_unwrapped_optional
    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) {
            return true
        }
        return originalDelegate?.responds(to: aSelector) ?? false
    }

    // swiftlint:disable:next implicitly_unwrapped_optional
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let original = originalDelegate, original.responds(to: aSelector) {
            return original
        }
        return super.forwardingTarget(for: aSelector)
    }
}

#endif
