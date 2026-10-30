/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Class that reads the first frame presented to the user.
internal final class FirstFrameReader: RUMCommandPublisher {
    /// The date provider for the first frame date.
    private let dateProvider: DateProvider
    /// The media uptime provider to calculate the deltas of the CADisplayLink timestamps.
    private let mediaTimeProvider: CACurrentMediaTimeProvider

    private var firstFrameTimestamp: Double?
    private var firstFrameDate: Date?

    @ReadWriteLock
    private(set) var isActive: Bool = true

    private(set) weak var subscriber: RUMCommandSubscriber?

    init(dateProvider: DateProvider, mediaTimeProvider: CACurrentMediaTimeProvider) {
        self.dateProvider = dateProvider
        self.mediaTimeProvider = mediaTimeProvider
    }

    func publish(to subscriber: RUMCommandSubscriber) {
        self.subscriber = subscriber
    }
}

extension FirstFrameReader: RenderLoopReader {
    func stop() { self.isActive = false }

    func didUpdateFrame(link: FrameInfoProvider) {
        if firstFrameTimestamp == nil && isActive {
            let firstFrameDate = dateProvider.now.addingTimeInterval(link.currentFrameTimestamp - mediaTimeProvider.current)

            firstFrameTimestamp = link.currentFrameTimestamp
            self.firstFrameDate = firstFrameDate
            isActive = false

            subscriber?.process(command: RUMTimeToInitialDisplayCommand(time: firstFrameDate))
        }
    }
}

#if os(macOS)
/// Class that reads the first window presented to the user on macOS.
///
/// macOS has no render loop observer, so the initial display is the first update of a window that the app has put on screen,
/// which follows its first draw. Any window counts, including the window of a menu bar item, even if other windows cover it.
internal final class FirstWindowReader: NSObject, RUMCommandPublisher {
    /// The date provider for the first window date.
    private let dateProvider: DateProvider
    /// The notification center where window notifications are posted.
    private let notificationCenter: NotificationCenter

    @ReadWriteLock
    private(set) var isActive: Bool = true

    private(set) weak var subscriber: RUMCommandSubscriber?

    init(dateProvider: DateProvider, notificationCenter: NotificationCenter) {
        self.dateProvider = dateProvider
        self.notificationCenter = notificationCenter
    }

    /// Sets the subscriber and starts observing windows.
    ///
    /// Observing starts here rather than at initialization, so the first window is never reported before there is a subscriber.
    /// A window shown before this call is reported at its next update.
    func publish(to subscriber: RUMCommandSubscriber) {
        self.subscriber = subscriber
        notificationCenter.addObserver(
            self,
            selector: #selector(windowDidUpdate(_:)),
            name: NSWindow.didUpdateNotification,
            object: nil
        )
    }

    func stop() {
        isActive = false
        notificationCenter.removeObserver(self, name: NSWindow.didUpdateNotification, object: nil)
    }

    @objc
    private func windowDidUpdate(_ notification: Notification) {
        // The occlusion state is not used: it does not change for a window that other windows cover from the start,
        // and a menu bar item hidden behind the notch stays occluded.
        guard let window = notification.object as? NSWindow, window.isVisible else {
            return
        }

        var isFirstWindow = false
        _isActive.mutate { isActive in
            isFirstWindow = isActive
            isActive = false
        }
        guard isFirstWindow else {
            return
        }

        stop()
        subscriber?.process(command: RUMTimeToInitialDisplayCommand(time: dateProvider.now))
    }
}
#endif
