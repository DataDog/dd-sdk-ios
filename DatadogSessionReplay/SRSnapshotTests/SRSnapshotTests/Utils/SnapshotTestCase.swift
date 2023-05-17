/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
@testable import SRHost

internal class SnapshotTestCase: XCTestCase {
    private var app: AppDelegate { UIApplication.shared.delegate as! AppDelegate }

    /// Shows view controller for given fixture in full screen.
    @discardableResult
    func show(fixture: Fixture) -> UIViewController? {
        let expectation = self.expectation(description: "Wait for view controller being shown")

        var viewController: UIViewController?

        app.show(fixture: fixture) {
            viewController = $0
            expectation.fulfill()
        }

        waitForExpectations(timeout: 30) // very pessimistic timeout to mitigate CI lags

        return viewController
    }

    /// Captures side-by-side snapshot of the app UI and recorded wireframes.
    func takeSnapshot(configuration: SessionReplayConfiguration = .init()) throws -> UIImage {
        let expectation = self.expectation(description: "Wait for wireframes")

        // Set up SR recorder:
        let scheduler = TestScheduler()
        let processor = Processor(queue: NoQueue(), writer: Writer())
        let recorder = try Recorder(
            configuration: configuration,
            rumContextObserver: RUMContextObserverMock(),
            processor: processor,
            scheduler: scheduler
        )

        // Set up wireframes interception and trigger recorder once:
        var wireframes: [SRWireframe]?

        processor.interceptWireframes = {
            wireframes = $0
            expectation.fulfill()
        }

        recorder.start()
        scheduler.triggerOnce()
        recorder.stop()

        waitForExpectations(timeout: 10) // very pessimistic timeout to mitigate CI lags

        // Render images:
        let wireframesImage = wireframes.map { renderImage(for: $0) } ?? UIImage()
        let appImage = app.keyWindow.map { renderImage(for: $0) } ?? UIImage()

        return createSideBySideImage(appImage, wireframesImage)
    }

    func wait(seconds: TimeInterval) {
        let expectation = self.expectation(description: "Wait \(seconds)")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: seconds * 2)
    }

    func forEachPrivacyMode(do work: (SessionReplayPrivacy) throws -> Void) rethrows {
        let modes: [SessionReplayPrivacy] = [.maskAll, .allowAll, .maskUserInput]
        try modes.forEach { try work($0) }
    }

    /// Puts two images side-by-side, adds titles and returns new, composite image.
    private func createSideBySideImage(_ image1: UIImage, _ image2: UIImage) -> UIImage {
        var leftRect = CGRect(origin: .zero, size: image1.size)
        var rightRect = CGRect(origin: .init(x: image1.size.width, y: 0), size: image2.size)
        let imageRect = leftRect.union(rightRect)
            .inset(by: .init(top: -30, left: -5, bottom: -5, right: -5))

        leftRect = leftRect.offsetBy(dx: 5, dy: 30)
        rightRect = rightRect.offsetBy(dx: 5, dy: 30)

        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: imageRect.size, format: format)

        return renderer.image { context in
            // Fill the image:
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.addRect(CGRect(origin: .zero, size: imageRect.size))
            context.cgContext.fillPath()

            // Draw both images:
            image1.draw(at: leftRect.origin)
            image2.draw(at: rightRect.origin)

            // Draw strokes around both images
            context.cgContext.setLineWidth(2)
            context.cgContext.setStrokeColor(UIColor.black.cgColor)
            context.cgContext.addRect(leftRect)
            context.cgContext.addRect(rightRect)
            context.cgContext.strokePath()

            // Add image titles
            let textAttributes: [NSAttributedString.Key : Any] = [
                NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 15),
                NSAttributedString.Key.foregroundColor: #colorLiteral(red: 0.3882352941, green: 0.1725490196, blue: 0.6509803922, alpha: 1),
            ]

            let leftTextRect = leftRect.offsetBy(dx: 2, dy: -25)
            let rightTextRect = rightRect.offsetBy(dx: 2, dy: -25)

            "Actual UI:".draw(in: leftTextRect, withAttributes: textAttributes)
            "Wireframes:".draw(in: rightTextRect, withAttributes: textAttributes)
        }
    }
}

// MARK: - SR Mocks

private struct NoQueue: Queue {
    func run(_ block: @escaping () -> Void) { block() }
}

private struct RUMContextObserverMock: RUMContextObserver {
    func observe(on queue: Queue, notify: @escaping (RUMContext?) -> Void) {
        queue.run {
            notify(RUMContext(ids: .init(applicationID: "", sessionID: "", viewID: ""), viewServerTimeOffset: 0))
        }
    }
}

private class TestScheduler: Scheduler {
    private var operations: [() -> Void] = []

    let queue: Queue = NoQueue()

    func schedule(operation: @escaping () -> Void) {
        operations.append(operation)
    }

    func start() {}
    func stop() {}

    func triggerOnce() {
        operations.forEach { $0() }
    }
}
