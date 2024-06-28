/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import SRFixtures
import TestUtilities
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
        try takeSnapshotFor(.basicTexts, with: [.allow, .mask, .maskUserInput], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testSliders() throws {
        try takeSnapshotFor(.sliders, with: [.allow, .mask, .maskUserInput], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testProgressViews() throws {
        try takeSnapshotFor(.progressViews, with: [.allow, .mask], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testSegments() throws {
        try takeSnapshotFor(.segments, with: [.allow, .mask, .maskUserInput], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testPickers() throws {
        try takeSnapshotFor(.pickers, with: [.allow, .mask, .maskUserInput], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testSwitches() throws {
        try takeSnapshotFor(.switches, with: [.allow, .mask, .maskUserInput], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testTextFields() throws {
        try takeSnapshotFor(.textFields, with: [.allow, .mask, .maskUserInput], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testSteppers() throws {
        try takeSnapshotFor(.steppers, with: [.allow, .mask, .maskUserInput], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
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
            with: [.allow, .mask, .maskUserInput],
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
        try takeSnapshotFor(.images, with: [.allow, .mask], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testUnsupportedView() throws {
        try takeSnapshotFor(.unsupportedViews, with: [.allow], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testAlert() throws {
        try takeSnapshotForPopup(
            fixture: .popups,
            showPopup: { $0.showAlert() },
            waitTime: 1.0,
            privacyModes: [.allow, .mask, .maskUserInput],
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
        try takeSnapshotFor(.swiftUI, with: [.allow, .mask], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testNavigationBars() throws {
        // - Static Navigation Bars -

        // Note: Static Navigation Bars are not representative of realistic rendering at runtime.
        // Therefore, Embedded Navigation Bars snapshot tests are also included for more accurate simulations.

        // Test Static Navigation Bars without tinted color
        try takeSnapshotFor(.navigationBars, with: [.allow, .mask], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath, fileNamePrefix: Fixture.navigationBars.slug)

        // Test Static Navigation Bars with tinted color
        let vc2 = show(fixture: .navigationBars) as! NavigationBarControllers
        vc2.setTintColor()
        wait(seconds: 0.1)

        try forPrivacyModes([.allow, .mask]) { privacyMode in
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

            try forPrivacyModes([.allow, .mask]) { privacyMode in
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
        try takeSnapshotFor(.tabbar, with: [.allow, .mask], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)

        // - Embedded Tab Bar
        try takeSnapshotFor(.embeddedTabbar, with: [.allow, .mask], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath, fileNamePrefix: Fixture.embeddedTabbar.slug)

        // - Embedded Tab Bar, with unselected item tint color
        try takeSnapshotFor(.embeddedTabbarUnselectedTintColor, with: [.allow, .mask], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath, fileNamePrefix: Fixture.embeddedTabbarUnselectedTintColor.slug)
    }
}
