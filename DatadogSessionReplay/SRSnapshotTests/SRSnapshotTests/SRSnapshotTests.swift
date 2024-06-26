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
        let vc1 = show(fixture: .datePickersInline) as! DatePickersInlineViewController
        vc1.set(date: .mockDecember15th2019At10AMUTC(), timeZone: .UTC)
        wait(seconds: 1.0)

        try forPrivacyModes { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-inline-\(privacyMode)-privacy"),
                record: shouldRecord
            )
        }

        let vc2 = show(fixture: .datePickersCompact) as! DatePickersCompactViewController
        vc2.set(date: .mockDecember15th2019At10AMUTC(), timeZone: .UTC)
        vc2.openCalendarPopover()
        wait(seconds: 1.0)

        try forPrivacyModes { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-compact-\(privacyMode)-privacy"),
                record: shouldRecord
            )
        }

        let vc3 = show(fixture: .datePickersWheels) as! DatePickersWheelsViewController
        vc3.set(date: .mockDecember15th2019At10AMUTC(), timeZone: .UTC)
        wait(seconds: 1.5)

        try forPrivacyModes { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-wheels-\(privacyMode)-privacy"),
                record: shouldRecord
            )
        }
    }

    func testTimePickers() throws {
        show(fixture: .timePickersCountDown)

        try forPrivacyModes { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-count-down-\(privacyMode)-privacy"),
                record: shouldRecord
            )
        }

        let vc1 = show(fixture: .timePickersWheels) as! TimePickersWheelViewController
        vc1.set(date: .mockDecember15th2019At10AMUTC(), timeZone: .UTC)
        wait(seconds: 1.0)

        try forPrivacyModes { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-wheels-\(privacyMode)-privacy"),
                record: shouldRecord
            )
        }

        let vc2 = show(fixture: .timePickersCompact) as! TimePickersCompactViewController
        vc2.set(date: .mockDecember15th2019At10AMUTC(), timeZone: .UTC)
        vc2.openTimePickerPopover()
        wait(seconds: 1.0)

        try forPrivacyModes { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-compact-\(privacyMode)-privacy"),
                record: shouldRecord
            )
        }
    }

    func testImages() throws {
        try takeSnapshotFor(.images, with: [.allow, .mask], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testUnsupportedView() throws {
        try takeSnapshotFor(.unsupportedViews, with: [.allow], shouldRecord: shouldRecord, folderPath: snapshotsFolderPath)
    }

    func testAlert() throws {
        (show(fixture: .popups) as! PopupsViewController).showAlert()

        wait(seconds: 1.0)

        try forPrivacyModes { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: shouldRecord
            )
        }
    }

    func testSafari() throws {
        (show(fixture: .popups) as! PopupsViewController).showSafari()

        wait(seconds: 1.0)

        let image = try takeSnapshot()
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderPath),
            record: shouldRecord
        )
    }

    func testActivity() throws {
        (show(fixture: .popups) as! PopupsViewController).showActivity()

        wait(seconds: 1.0)

        let image = try takeSnapshot()
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderPath),
            record: shouldRecord
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
        // Wait for colors to appear on screen, so the recorder can capture them.
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
            // Wait for view controller to be pushed onto the navigation stack.
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
