/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogSessionReplay
@testable import SRHost

private var defaultPrivacyLevel: SessionReplay.Configuration.PrivacyLevel {
    return SessionReplay.Configuration(replaySampleRate: 100).defaultPrivacyLevel
}

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
    func takeSnapshot(with privacyLevel: SessionReplay.Configuration.PrivacyLevel = defaultPrivacyLevel) throws -> UIImage {
        let expectation = self.expectation(description: "Wait for wireframes")

        // Set up SR recorder:
        let processor = Processor(
            queue: NoQueue(),
            writer: Writer(),
            srContextPublisher: SRContextPublisher(core: PassthroughCoreMock()),
            telemetry: TelemetryMock()
        )
        let recorder = try Recorder(processor: processor, telemetry: TelemetryMock())

        // Set up wireframes interception :
        var wireframes: [SRWireframe]?
        processor.interceptWireframes = {
            wireframes = $0
            expectation.fulfill()
        }

        // Capture next record with mock RUM Context
        recorder.captureNextRecord(
            .init(privacy: privacyLevel, applicationID: "", sessionID: "", viewID: "", viewServerTimeOffset: 0)
        )

        waitForExpectations(timeout: 10) // very pessimistic timeout to mitigate CI lags

        // Render images:
        let wireframesImage = wireframes.map { renderImage(for: $0) } ?? UIImage()
        let appImage = app.keyWindow.map { renderImage(for: $0) } ?? UIImage()

        return createSideBySideImage(actualUI: appImage, wireframes: wireframesImage)
    }

    func wait(seconds: TimeInterval) {
        let expectation = self.expectation(description: "Wait \(seconds)")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: seconds * 2)
    }

    func forEachPrivacyMode(do work: (SessionReplay.Configuration.PrivacyLevel) throws -> Void) rethrows {
        let modes: [SessionReplay.Configuration.PrivacyLevel] = [.mask, .allow, .maskUserInput]
        try modes.forEach { try work($0) }
    }
}

// MARK: - SR Mocks

private struct NoQueue: Queue {
    func run(_ block: @escaping () -> Void) { block() }
}
