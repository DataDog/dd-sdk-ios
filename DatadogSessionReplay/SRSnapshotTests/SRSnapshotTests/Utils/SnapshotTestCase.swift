/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import SRFixtures
import TestUtilities
@_spi(Internal)
@testable import DatadogSessionReplay
@testable import SRHost

private var defaultPrivacyLevel: SessionReplayPrivacyLevel {
    return SessionReplay.Configuration(replaySampleRate: 100).defaultPrivacyLevel
}

private var defaultImagePrivacyLevel: ImagePrivacyLevel {
    return .maskNonBundledOnly
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

    /// Helper method for most snapshot tests
    func takeSnapshotFor(
        _ fixture: Fixture,
        with privacyModes: [SessionReplayPrivacyLevel] = [defaultPrivacyLevel],
        imagePrivacyLevel: ImagePrivacyLevel = defaultImagePrivacyLevel,
        shouldRecord: Bool,
        folderPath: String,
        fileNamePrefix: String? = nil,
        file: StaticString = #filePath,
        function: StaticString = #function
    ) throws {
        show(fixture: fixture)
        // Give time for the view to appear and lay out properly
        wait(seconds: 0.2)

        try forPrivacyModes(privacyModes) { privacyMode in
            let image = try takeSnapshot(with: privacyMode, imagePrivacyLevel: imagePrivacyLevel)
            let fileNameSuffix = fileNamePrefix == nil ? "-\(privacyMode)-privacy" : "-\(fileNamePrefix!)-\(privacyMode)-privacy"
            let snapshotLocation: ImageLocation = .folder(named: folderPath, fileNameSuffix: fileNameSuffix, file: file, function: function)

            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: snapshotLocation,
                record: shouldRecord
            )
        }
    }

    /// Helper method for date and time picker snapshot tests
    func takeSnapshotForPicker(
        fixture: Fixture,
        additionalSetup: ((UIViewController) -> Void)? = nil,
        waitTime: TimeInterval,
        shouldRecord: Bool,
        folderPath: String,
        fileNamePrefix: String,
        file: StaticString = #filePath,
        function: StaticString = #function
    ) throws {
        let vc = show(fixture: fixture) as! DateSetting
        vc.set(date: .mockDecember15th2019At10AMUTC(), timeZone: .UTC)
        additionalSetup?(vc as! UIViewController)
        wait(seconds: waitTime)

        try forPrivacyModes { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: folderPath, fileNameSuffix: "-\(fileNamePrefix)-\(privacyMode)-privacy", file: file, function: function),
                record: shouldRecord
            )
        }
    }

    /// Helper method for snapshot tests showing PopupsViewController
    func takeSnapshotForPopup(
        fixture: Fixture,
        showPopup: (PopupsViewController) -> Void,
        waitTime: TimeInterval,
        privacyModes: [SessionReplayPrivacyLevel] = [defaultPrivacyLevel],
        shouldRecord: Bool,
        folderPath: String,
        file: StaticString = #filePath,
        function: StaticString = #function
    ) throws {
        let vc = show(fixture: fixture) as! PopupsViewController
        showPopup(vc)
        wait(seconds: waitTime)
        print("privacyModes:", privacyModes)

        for privacyMode in privacyModes {
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: folderPath, fileNameSuffix: "-\(privacyMode)-privacy", file: file, function: function),
                record: shouldRecord
            )
        }
    }

    /// Captures side-by-side snapshot of the app UI and recorded wireframes.
    func takeSnapshot(
        with privacyLevel: SessionReplayPrivacyLevel = defaultPrivacyLevel,
        imagePrivacyLevel: ImagePrivacyLevel = defaultImagePrivacyLevel
    ) throws -> UIImage {
        let expectWireframes = self.expectation(description: "Wait for wireframes")
        let expectResources = self.expectation(description: "Wait for resources")

        // Set up SR recorder:
        let resourceProcessor = ResourceProcessor(
            queue: NoQueue(),
            resourcesWriter: ResourcesWriter(scope: FeatureScopeMock())
        )

        let snapshotProcessor = SnapshotProcessor(
            queue: NoQueue(),
            recordWriter: RecordWriter(core: PassthroughCoreMock()),
            resourceProcessor: resourceProcessor,
            srContextPublisher: SRContextPublisher(core: PassthroughCoreMock()),
            telemetry: TelemetryMock()
        )

        let recorder = try Recorder(
            snapshotProcessor: snapshotProcessor,
            additionalNodeRecorders: []
        )

        // Set up wireframes interception:
        var wireframes: [SRWireframe]?
        snapshotProcessor.interceptWireframes = {
            wireframes = $0
            expectWireframes.fulfill()
        }

        // Set up resource interception:
        var resources: [Resource]?
        resourceProcessor.interceptResources = {
            resources = $0
            expectResources.fulfill()
        }

        // Capture next record with mock RUM Context
        try recorder.captureNextRecord(
            .init(
                privacy: privacyLevel,
                textAndInputPrivacy: .maskSensitiveInputs,
                imagePrivacy: imagePrivacyLevel,
                touchPrivacy: .show,
                applicationID: "",
                sessionID: "",
                viewID: "",
                viewServerTimeOffset: 0
            )
        )

        waitForExpectations(timeout: 30) // very pessimistic timeout to mitigate CI lags

        // Render images:
        guard let wireframes = wireframes, !wireframes.isEmpty else {
            XCTFail("Recorded no wireframes.")
            return UIImage()
        }
        let renderedWireframes = renderImage(for: wireframes, resources: resources ?? [])
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

    func forPrivacyModes(
        _ modes: [SessionReplayPrivacyLevel] = [.mask, .allow, .maskUserInput],
        do work: (SessionReplayPrivacyLevel) throws -> Void) rethrows {
        try modes.forEach { try work($0) }
    }
}

// MARK: - SR Mocks

private class NoQueue: Queue {
    func run(_ block: @escaping () -> Void) { block() }
}
