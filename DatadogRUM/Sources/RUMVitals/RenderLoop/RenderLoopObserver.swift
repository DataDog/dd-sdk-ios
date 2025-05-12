/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation
import UIKit

internal protocol RenderLoopReader: AnyObject {
    var isActive: Bool { get }

    func stop()
    func didUpdateFrame(link: FrameInfoProvider)
}

internal protocol RenderLoopObserver {
    /// `RenderLoopObserver` registers the render loop reader to get updates of frame rendering.
    /// - Parameters:
    ///   - renderLoopReader: The render loop reader to be notified.
    func register(_ renderLoopReader: RenderLoopReader)

    /// `RenderLoopObserver` stops notifying the render loop reader.
    /// - Parameters:
    ///   - renderLoopReader: The render loop reader to stop receiving frame rendering updates.
    func unregister(_ renderLoopReader: RenderLoopReader)
}

/// A class reading information from the display vsync.
internal class DisplayLinker {
    private var renderLoopReaders: [RenderLoopReader] = []
    private var displayLink: FrameInfoProvider?
    private let notificationCenter: NotificationCenter

    var isActive: Bool { displayLink != nil }

    init(notificationCenter: NotificationCenter) {
        self.notificationCenter = notificationCenter

        notificationCenter.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: ApplicationNotifications.willResignActive,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: ApplicationNotifications.didBecomeActive,
            object: nil
        )

        start()
    }

    deinit {
        stop()
        notificationCenter.removeObserver(self)
    }

    private func start() {
        guard displayLink == nil else {
            return
        }

        displayLink = CADisplayLink(target: self, selector: #selector(self.didUpdateFrame(link:)))

        // NOTE: RUMM-1544 `.default` mode doesn't get fired while scrolling the UI, `.common` does.
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stop() {
        renderLoopReaders.forEach { $0.stop() }

        displayLink?.invalidate()
        displayLink = nil
    }

    @objc
    private func appDidBecomeActive() {
        start()
    }

    @objc
    private func appWillResignActive() {
        stop()
    }

    @objc
    private func didUpdateFrame(link: CADisplayLink) {
        renderLoopReaders.forEach { $0.didUpdateFrame(link: link) }
    }
}

extension DisplayLinker: RenderLoopObserver {
    func register(_ renderLoopReader: RenderLoopReader) {
        DispatchQueue.main.async {
            self.renderLoopReaders.append(renderLoopReader)
        }
    }

    func unregister(_ renderLoopReader: RenderLoopReader) {
        DispatchQueue.main.async {
            renderLoopReader.stop()
            self.renderLoopReaders.removeAll { $0 === renderLoopReader }
        }
    }
}
