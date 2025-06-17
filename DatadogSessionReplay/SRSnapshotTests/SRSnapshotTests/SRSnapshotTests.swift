/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import SRFixtures
import TestUtilities
import DatadogSessionReplay
@testable import SRHost

final class SRSnapshotTests: SnapshotTestCase {
    /// The path for storing PNG files.
    /// In practice, PNGs can be segregated in any subfolder(s) structure under `_snapshots_/png/**` if it makes sense.
    private let snapshotsFolderPath = "_snapshots_/png"
    /// Current recording mode:
    /// - `true` - overwrite PNGs with new versions if the difference is higher than the threshold;
    /// - `false` - do not overwrite PNGs, no matter the difference.
    private var shouldRecord = false

    func testBasicShapes() throws {
        try takeSnapshotFor(.basicShapes, shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testBasicTexts() throws {
        try takeSnapshotFor(.basicTexts, with: allTextAndInputPrivacyLevels, shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testSliders() throws {
        try takeSnapshotFor(.sliders, with: allTextAndInputPrivacyLevels, shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testProgressViews() throws {
        try takeSnapshotFor(.progressViews, with: [.maskSensitiveInputs, .maskAll], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testActivityIndicators() throws {
        try takeSnapshotFor(.activityIndicators, shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testSegments() throws {
        try takeSnapshotFor(.segments, with: allTextAndInputPrivacyLevels, shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testPickers() throws {
        try takeSnapshotFor(.pickers, with: allTextAndInputPrivacyLevels, shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testSwitches() throws {
        try takeSnapshotFor(.switches, with: allTextAndInputPrivacyLevels, shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testTextFields() throws {
        try takeSnapshotFor(.textFields, with: allTextAndInputPrivacyLevels, shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testSteppers() throws {
        try takeSnapshotFor(.steppers, with: allTextAndInputPrivacyLevels, shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testDatePickers() throws {
        try takeSnapshotForPicker(
            fixture: .datePickersInline,
            waitTime: 1.0,
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath,
            fileNamePrefix: "inline"
        )

        try takeSnapshotForPicker(
            fixture: .datePickersCompact,
            additionalSetup: { ($0 as! DatePickersCompactViewController).openCalendarPopover() },
            waitTime: 1.0,
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath,
            fileNamePrefix: "compact"
        )

        try takeSnapshotForPicker(
            fixture: .datePickersWheels,
            waitTime: 1.0,
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath,
            fileNamePrefix: "wheels"
        )
    }

    func testTimePickers() throws {
        try takeSnapshotFor(
            .timePickersCountDown,
            with: allTextAndInputPrivacyLevels,
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath,
            fileNamePrefix: "count-down"
        )

        try takeSnapshotForPicker(
            fixture: .timePickersWheels,
            waitTime: 1.0,
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath,
            fileNamePrefix: "wheels"
        )

        try takeSnapshotForPicker(
            fixture: .timePickersCompact,
            additionalSetup: { ($0 as! DatePickersCompactViewController).openTimePickerPopover() },
            waitTime: 1.0,
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath,
            fileNamePrefix: "compact"
        )
    }

    func testImages() throws {
        try takeSnapshotFor(
            .images,
            with: [.maskSensitiveInputs, .maskAll],
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath
        )
    }

    func testImages_MaskAll() throws {
        try takeSnapshotFor(
            .images,
            with: [.maskSensitiveInputs, .maskAll],
            imagePrivacyLevel: .maskAll,
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath
        )
    }

    func testImages_MaskNone() throws {
        try takeSnapshotFor(
            .images,
            with: [.maskSensitiveInputs, .maskAll],
            imagePrivacyLevel: .maskNone,
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath
        )
    }

    func testAlert() throws {
        try takeSnapshotForPopup(
            fixture: .popups,
            showPopup: { $0.showAlert() },
            waitTime: 1.0,
            textPrivacyModes: allTextAndInputPrivacyLevels,
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath
        )
    }

    func testSafari() throws {
        try takeSnapshotForPopup(
            fixture: .popups,
            showPopup: { $0.showSafari() },
            waitTime: 1.0,
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath
        )
    }

    func testActivity() throws {
        try takeSnapshotForPopup(
            fixture: .popups,
            showPopup: { $0.showActivity() },
            waitTime: 1.0,
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath
        )
    }

    func testSwiftUI() throws {
        // Mask all
        try takeSnapshotFor(
            .swiftUI,
            with: [.maskAll],
            imagePrivacyLevel: .maskAll,
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath,
            fileNamePrefix: "maskAll_images"
        )

        // Intermediate levels
        try takeSnapshotFor(
            .swiftUI,
            with: [.maskAllInputs],
            imagePrivacyLevel: .maskNonBundledOnly,
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath,
            fileNamePrefix: "maskNonBundledOnly_images"
        )

        // Mask none
        try takeSnapshotFor(
            .swiftUI,
            with: [.maskSensitiveInputs],
            imagePrivacyLevel: .maskNone,
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath,
            fileNamePrefix: "maskNone_images"
        )
    }

    func testSwiftUIWithPrivacyOverrides() throws {
        let core = FeatureRegistrationCoreMock()
        // SwiftUI privacy overrides only work when SessionReplay is enabled
        SessionReplay.enable(
            with: .init(
                // Just to silence the deprecation warning (these are trumped by `takeSnapshotFor` parameters)
                textAndInputPrivacyLevel: .maskSensitiveInputs,
                imagePrivacyLevel: .maskNone,
                touchPrivacyLevel: .show
            ),
            in: core
        )

        // Mask none
        try takeSnapshotFor(
            .swiftUIWithPrivacyOverrides(core),
            with: [.maskSensitiveInputs],
            imagePrivacyLevel: .maskNone,
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath,
            fileNamePrefix: "maskNone_images"
        )
    }

    func testNavigationBars() throws {
        // - Static Navigation Bars -

        // Note: Static Navigation Bars are not representative of realistic rendering at runtime.
        // Therefore, Embedded Navigation Bars snapshot tests are also included for more accurate simulations.

        // Test Static Navigation Bars without tinted color
        try takeSnapshotFor(.navigationBars, with: [.maskSensitiveInputs, .maskAll], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath, fileNamePrefix: Fixture.navigationBars.slug)

        // Test Static Navigation Bars with tinted color
        let vc2 = show(fixture: .navigationBars) as! NavigationBarControllers
        vc2.setTintColor()
        wait(seconds: 0.1)

        try forPrivacyModes([.maskSensitiveInputs, .maskAll]) { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            let fileNamePrefix = Fixture.navigationBars.slug
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-\(fileNamePrefix)-itemTintColor-\(privacyMode)-privacy"),
                record: shouldRecord
            )
        }

        // - Embedded Navigation Bars -

        // Note: Although Embedded Navigation Bars are more realistic than Static Navigation Bars,
        // they still lack some realism as their appearance changes when the view is scrolled.

        let navBarFixtures: [Fixture] = [
            .navigationBarDefaultTranslucent,
            .navigationBarDefaultNonTranslucent,
            .navigationBarBlackTranslucent,
            .navigationBarBlackNonTranslucent,
            .navigationBarDefaultTranslucentBarTint,
            .navigationBarDefaultNonTranslucentBarTint,
            .navigationBarDefaultTranslucentBackground,
            .navigationBarDefaultNonTranslucentBackground
        ]

        for fixture in navBarFixtures {
            let navController = show(fixture: fixture) as! TestNavigationController
            navController.pushNextView()
            wait(seconds: 0.5)

            try forPrivacyModes([.maskSensitiveInputs, .maskAll]) { privacyMode in
                let image = try takeSnapshot(with: privacyMode)
                let fileNamePrefix = fixture.slug
                DDAssertSnapshotTest(
                    newImage: image,
                    snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-\(fileNamePrefix)-\(privacyMode)-privacy"),
                    record: shouldRecord
                )
            }
        }
    }

    func testTabBars() throws {
        // - Static Tab Bars
        try takeSnapshotFor(.tabbar, with: [.maskSensitiveInputs, .maskAll], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)

        // - Embedded Tab Bar
        try takeSnapshotFor(.embeddedTabbar, with: [.maskSensitiveInputs, .maskAll], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath, fileNamePrefix: Fixture.embeddedTabbar.slug)

        // - Embedded Tab Bar, with unselected item tint color
        try takeSnapshotFor(.embeddedTabbarUnselectedTintColor, with: [.maskSensitiveInputs, .maskAll], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath, fileNamePrefix: Fixture.embeddedTabbarUnselectedTintColor.slug)
    }

    // MARK: Privacy Overrides
    func testMaskingPrivacyOverrides() throws {
        try takeSnapshotFor(
            .basicShapes,
            privacyTags: [
                .hideView(tag: 2)
            ],
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath,
            fileNamePrefix: "hideOverride_masking"
        )

        try takeSnapshotFor(
            .basicTexts,
            with: [.maskSensitiveInputs],
            privacyTags: [
                .maskAllText(tag: 2),
                .hideView(tag: 3)
            ],
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath,
            fileNamePrefix: "textOverrides_masking"
        )

        try takeSnapshotFor(
            .images,
            imagePrivacyLevel: .maskNone,
            privacyTags: [
                .maskAllImages(tag: 2),
                .maskNonBundledImages(tag: 3),
                .hideView(tag: 4)
            ],
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath,
            fileNamePrefix: "imageOverrides_masking"
        )
    }

    func testMaskingPrivacyOverridesOnParentView() throws {
        try takeSnapshotFor(
            .basicShapes,
            privacyTags: [
                .hideView(tag: 1)
            ],
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath,
            fileNamePrefix: "hideOverride_masking_parentView"
        )

        try takeSnapshotFor(
            .basicTexts,
            with: [.maskSensitiveInputs],
            privacyTags: [
                .maskAllText(tag: 1)
            ],
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath,
            fileNamePrefix: "textOverride_masking_parentView"
        )

        try takeSnapshotFor(
            .images,
            imagePrivacyLevel: .maskNone,
            privacyTags: [
                .maskAllImages(tag: 1)
            ],
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath,
            fileNamePrefix: "imageOverride_masking_parentView"
        )
    }

    func testUnmaskingPrivacyOverrides() throws {
        try takeSnapshotFor(
            .basicTexts,
            with: [.maskAll],
            privacyTags: [
                .unmaskText(tag: 2),
                .unmaskText(tag: 3)
            ],
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath,
            fileNamePrefix: "textOverrides_unmasking"
        )

        try takeSnapshotFor(
            .images,
            imagePrivacyLevel: .maskAll,
            privacyTags: [
                .unmaskImages(tag: 2),
                .unmaskImages(tag: 3),
                .unmaskImages(tag: 4)
            ],
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath,
            fileNamePrefix: "imageOverrides_unmasking"
        )
    }
}
