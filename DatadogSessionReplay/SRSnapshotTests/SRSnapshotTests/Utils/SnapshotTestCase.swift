/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import SRFixtures
import DatadogInternal
import TestUtilities
@_spi(Internal)
@testable import DatadogSessionReplay
@testable import SRHost

private var defaultImagePrivacyLevel: ImagePrivacyLevel = .maskNonBundledOnly
private var defaultTextAndInputPrivacyLevel: TextAndInputPrivacyLevel = .maskSensitiveInputs
internal var allTextAndInputPrivacyLevels: [TextAndInputPrivacyLevel] {
    return TextAndInputPrivacyLevel.allCases
}

internal class SnapshotTestCase: XCTestCase {
    private var app: AppDelegate { UIApplication.shared.delegate as! AppDelegate }

    /// Shows view controller for given fixture in full screen.
    @discardableResult
    func show(fixture: any FixtureProtocol, with privacyTags: [PrivacyTag] = []) -> UIViewController? {
        let expectation = self.expectation(description: "Wait for view controller being shown")

        var viewController: UIViewController?

        app.show(fixture: fixture) {
            viewController = $0
            for privacyTag in privacyTags {
                if let view = viewController?.view.viewWithTag(privacyTag.tag) {
                    privacyTag.createPrivacyApplier().apply(to: view)
                } else {
                    print("Warning: No view found with tag \(privacyTag.tag)")
                }
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 30) // very pessimistic timeout to mitigate CI lags

        return viewController
    }

    // swiftlint:disable function_default_parameter_at_end
    /// Helper method for most snapshot tests
    func takeSnapshotFor(
        _ fixture: any FixtureProtocol,
        with textAndInputPrivacyLevels: [TextAndInputPrivacyLevel] = [defaultTextAndInputPrivacyLevel],
        imagePrivacyLevel: ImagePrivacyLevel = defaultImagePrivacyLevel,
        privacyTags: [PrivacyTag] = [],
        shouldRecord: Bool,
        folderPath: String,
        fileNamePrefix: String? = nil,
        file: StaticString = #filePath,
        function: StaticString = #function
    ) throws {
        show(fixture: fixture, with: privacyTags)
        // Give time for the view to appear and lay out properly
        wait(seconds: 0.2)

        try forPrivacyModes(textAndInputPrivacyLevels) { textPrivacyLevel in
            let image = try takeSnapshot(with: textPrivacyLevel, imagePrivacyLevel: imagePrivacyLevel)
            let fileNameSuffix = fileNamePrefix == nil ? "-\(textPrivacyLevel)-privacy" : "-\(fileNamePrefix!)-\(textPrivacyLevel)-privacy"
            let snapshotLocation: ImageLocation = .folder(named: folderPath, fileNameSuffix: fileNameSuffix, file: file, function: function)

            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: snapshotLocation,
                record: shouldRecord
            )
        }
    }
    // swiftlint:enable function_default_parameter_at_end

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

    // swiftlint:disable function_default_parameter_at_end
    /// Helper method for snapshot tests showing PopupsViewController
    func takeSnapshotForPopup(
        fixture: Fixture,
        showPopup: (PopupsViewController) -> Void,
        waitTime: TimeInterval,
        textPrivacyModes: [TextAndInputPrivacyLevel] = [defaultTextAndInputPrivacyLevel],
        shouldRecord: Bool,
        folderPath: String,
        file: StaticString = #filePath,
        function: StaticString = #function
    ) throws {
        let vc = show(fixture: fixture) as! PopupsViewController
        showPopup(vc)
        wait(seconds: waitTime)

        for textPrivacyMode in textPrivacyModes {
            let image = try takeSnapshot(with: textPrivacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: folderPath, fileNameSuffix: "-\(textPrivacyMode)-privacy", file: file, function: function),
                record: shouldRecord
            )
        }
    }
    // swiftlint:enable function_default_parameter_at_end

    /// Captures side-by-side snapshot of the app UI and recorded wireframes.
    func takeSnapshot(
        with textAndInputPrivacyLevel: TextAndInputPrivacyLevel = defaultTextAndInputPrivacyLevel,
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
            telemetry: NOPTelemetry()
        )

        let recorder = try Recorder(
            snapshotProcessor: snapshotProcessor,
            additionalNodeRecorders: [],
            featureFlags: [.swiftui: true]
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
                textAndInputPrivacy: textAndInputPrivacyLevel,
                imagePrivacy: imagePrivacyLevel,
                touchPrivacy: .show,
                applicationID: "",
                sessionID: "",
                viewID: "",
                viewServerTimeOffset: 0,
                date: Date(),
                telemetry: NOPTelemetry()
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
        wireframesAttachement.name = "recorded-wireframes-(\(textAndInputPrivacyLevel)).json"
        wireframesAttachement.lifetime = .deleteOnSuccess
        add(wireframesAttachement)

        // - attach rendered as blueprint text
        let blueprintAttachement = XCTAttachment(string: renderedWireframes.debugInfo.dumpImageAsBlueprint())
        blueprintAttachement.name = "rendered-blueprint-(\(textAndInputPrivacyLevel)).txt"
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
        _ modes: [TextAndInputPrivacyLevel] = TextAndInputPrivacyLevel.allCases,
        do work: (TextAndInputPrivacyLevel) throws -> Void) rethrows {
        try modes.forEach { try work($0) }
    }
}

// MARK: - SR Mocks

private class NoQueue: Queue {
    func run(_ block: @escaping () -> Void) { block() }
}
