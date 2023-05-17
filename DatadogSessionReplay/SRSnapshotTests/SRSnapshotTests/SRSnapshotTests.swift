/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import SRHost
import TestUtilities

final class SRSnapshotTests: SnapshotTestCase {
    private let snapshotsFolderName = "_snapshots_"
    private var recordingMode = true

    func testBasicShapes() throws {
        show(fixture: .basicShapes)
        let image = try takeSnapshot()
        DDAssertSnapshotTest(newImage: image, snapshotLocation: .folder(named: snapshotsFolderName), record: recordingMode)
    }

    func testBasicTexts() throws {
        show(fixture: .basicTexts)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(configuration: .init(privacy: privacyMode))
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testSliders() throws {
        show(fixture: .sliders)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(configuration: .init(privacy: privacyMode))
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testSegments() throws {
        show(fixture: .segments)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(configuration: .init(privacy: privacyMode))
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testPickers() throws {
        show(fixture: .pickers)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(configuration: .init(privacy: privacyMode))
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testSwitches() throws {
        show(fixture: .switches)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(configuration: .init(privacy: privacyMode))
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testTextFields() throws {
        show(fixture: .textFields)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(configuration: .init(privacy: privacyMode))
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testSteppers() throws {
        show(fixture: .steppers)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(configuration: .init(privacy: privacyMode))
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testDatePickers() throws {
        let vc1 = show(fixture: .datePickersInline) as! DatePickersInlineViewController
        vc1.set(date: .mockDecember15th2019At10AMUTC())
        wait(seconds: 0.5)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(configuration: .init(privacy: privacyMode))
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-inline-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }

        let vc2 = show(fixture: .datePickersCompact) as! DatePickersCompactViewController
        vc2.set(date: .mockDecember15th2019At10AMUTC())
        vc2.openCalendarPopover()
        wait(seconds: 0.5)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(configuration: .init(privacy: privacyMode))
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-compact-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }

        let vc3 = show(fixture: .datePickersWheels) as! DatePickersWheelsViewController
        vc3.set(date: .mockDecember15th2019At10AMUTC())
        wait(seconds: 0.5)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(configuration: .init(privacy: privacyMode))
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-wheels-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testTimePickers() throws {
        show(fixture: .timePickersCountDown)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(configuration: .init(privacy: privacyMode))
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-count-down-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }

        let vc1 = show(fixture: .timePickersWheels) as! TimePickersWheelViewController
        vc1.set(date: .mockDecember15th2019At10AMUTC())
        wait(seconds: 0.5)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(configuration: .init(privacy: privacyMode))
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-wheels-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }

        let vc2 = show(fixture: .timePickersCompact) as! TimePickersCompactViewController
        vc2.set(date: .mockDecember15th2019At10AMUTC())
        vc2.openTimePickerPopover()
        wait(seconds: 0.5)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(configuration: .init(privacy: privacyMode))
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-compact-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testImages() throws {
        show(fixture: .images)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(configuration: .init(privacy: privacyMode))
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testUnsupportedView() throws {
        show(fixture: .unsupportedViews)

        let image = try takeSnapshot(configuration: .init(privacy: .allowAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-allowAll-privacy"),
            record: recordingMode
        )
    }

    func testAlert() throws {
        (show(fixture: .popups) as! PopupsViewController).showAlert()

        wait(seconds: 0.5)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(configuration: .init(privacy: privacyMode))
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testSafari() throws {
        (show(fixture: .popups) as! PopupsViewController).showSafari()

        wait(seconds: 0.2)

        let image = try takeSnapshot()
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName),
            record: recordingMode
        )
    }

    func testActivity() throws {
        (show(fixture: .popups) as! PopupsViewController).showActivity()

        wait(seconds: 0.5)

        let image = try takeSnapshot()
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName),
            record: recordingMode
        )
    }

    func testSwiftUI() throws {
        show(fixture: .swiftUI)

        wait(seconds: 0.5)

        let image = try takeSnapshot()
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName),
            record: recordingMode
        )
    }
}
