/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import QuartzCore

/// TODO: this should be, likely, a "dropped frames instrument". The `displaylink.duration` describes the actual frame time, so
/// the main thing we can figure out here is how many frames exceeded the "smooth duration" (of ~16 ms). Eventually, we can reason
/// about the app FPS with this, like in mobile vitals.
internal class DroppedFramesInstrument {
    private var displayLink: CADisplayLink!

    init() {
        displayLink = CADisplayLink(target: self, selector: #selector(step(displaylink:)))
        displayLink.isPaused = true
        displayLink.add(to: .main, forMode: .common)
    }

    func start() { displayLink.isPaused = false }
    func stop() { displayLink.isPaused = true }

    @objc
    func step(displaylink: CADisplayLink) {
        let remainingTime = displaylink.targetTimestamp - CACurrentMediaTime()
        print("⏱️ frame duration: \(displaylink.duration.toMs), remaining: \(remainingTime.toMs)")
    }
}
