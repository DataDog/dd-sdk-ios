/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import UIKit

/// Class that reads the first frame presented to the user.
internal final class FirstFrameReader: RUMCommandPublisher {
    /// The date provider for the first frame date.
    private let dateProvider: DateProvider
    /// The media uptime provider to calculate the deltas of the CADisplayLink timestamps.
    private let mediaTimeProvider: CACurrentMediaTimeProvider

    private var firstFrameTimestamp: Double?
    private var firstFrameDate: Date?

    private(set) var isActive: Bool = true

    private(set) weak var subscriber: RUMCommandSubscriber?

    init(
        dateProvider: DateProvider = SystemDateProvider(),
        mediaTimeProvider: CACurrentMediaTimeProvider = MediaTimeProvider()
    ) {
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
