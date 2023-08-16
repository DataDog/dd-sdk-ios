/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogSessionReplay
@testable import SRHost

private var defaultPrivacyLevel: PrivacyLevel {
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
    func takeSnapshot(with privacyLevel: PrivacyLevel = defaultPrivacyLevel) throws -> UIImage {
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

        waitForExpectations(timeout: 30) // very pessimistic timeout to mitigate CI lags

        // Render images:
        guard let wireframes = wireframes, !wireframes.isEmpty else {
            XCTFail("Recorded no wireframes.")
            return UIImage()
        }
        let renderedWireframes = renderImage(for: wireframes)
        let appImage = app.keyWindow.map { renderImage(for: $0) } ?? UIImage()

        // Add XCTest attachements for debugging and troubleshooting:
        // - attach recorded wireframes as JSON
        let wireframesAttachement = XCTAttachment(string: renderedWireframes.debugInfo.dumpWireframesAsJSON())
        wireframesAttachement.name = "recorded-wireframes-(\(privacyLevel)).json"
        wireframesAttachement.lifetime = .deleteOnSuccess
        add(wireframesAttachement)

        // - attach rendered as blueprint text
        let blueprintAttachement = XCTAttachment(string: renderedWireframes.debugInfo.dumpImageAsBlueprint())
        blueprintAttachement.name = "rendered-blueprint-(\(privacyLevel)).txt"
        blueprintAttachement.lifetime = .deleteOnSuccess
        add(blueprintAttachement)

        return createSideBySideImage(leftImage: appImage, rightImage: renderedWireframes.image)
    }

    func wait(seconds: TimeInterval) {
        // To anticipate lags, await more if running on CI:
        let ciMultiplier: Double = Environment.isCI() ? 5 : 1
        let seconds = seconds * ciMultiplier
        let expectation = self.expectation(description: "Wait \(seconds)")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: seconds * 2)
    }

    func forEachPrivacyMode(do work: (PrivacyLevel) throws -> Void) rethrows {
        let modes: [PrivacyLevel] = [.mask, .allow, .maskUserInput]
        try modes.forEach { try work($0) }
    }
}

// MARK: - SR Mocks

private struct NoQueue: Queue {
    func run(_ block: @escaping () -> Void) { block() }
}
