/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import SRHost
import TestUtilities

final class SRSnapshotTests: SnapshotTestCase {
    /// The path for storing PNG files.
    /// In practice, PNGs can be segregated in any subfolder(s) structure under `_snapshots_/png/**` if it makes sense.
    private let snapshotsFolderPath = "_snapshots_/png"
    /// Current recording mode:
    /// - `true` - overwrite PNGs with new versions if the difference is higher than the threshold;
    /// - `false` - do not overwrite PNGs, no matter the difference.
    private var recordingMode = false

    func testBasicShapes() throws {
        show(fixture: .basicShapes)
        let image = try takeSnapshot()
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderPath),
            record: recordingMode
        )
    }

    func testBasicTexts() throws {
        show(fixture: .basicTexts)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testSliders() throws {
        show(fixture: .sliders)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testSegments() throws {
        show(fixture: .segments)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testPickers() throws {
        show(fixture: .pickers)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testSwitches() throws {
        show(fixture: .switches)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testTextFields() throws {
        show(fixture: .textFields)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testSteppers() throws {
        show(fixture: .steppers)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testDatePickers() throws {
        let vc1 = show(fixture: .datePickersInline) as! DatePickersInlineViewController
        vc1.set(date: .mockDecember15th2019At10AMUTC())
        wait(seconds: 1.0)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-inline-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }

        let vc2 = show(fixture: .datePickersCompact) as! DatePickersCompactViewController
        vc2.set(date: .mockDecember15th2019At10AMUTC())
        vc2.openCalendarPopover()
        wait(seconds: 1.0)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-compact-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }

        let vc3 = show(fixture: .datePickersWheels) as! DatePickersWheelsViewController
        vc3.set(date: .mockDecember15th2019At10AMUTC())
        wait(seconds: 1.0)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-wheels-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testTimePickers() throws {
        show(fixture: .timePickersCountDown)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-count-down-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }

        let vc1 = show(fixture: .timePickersWheels) as! TimePickersWheelViewController
        vc1.set(date: .mockDecember15th2019At10AMUTC())
        wait(seconds: 1.0)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-wheels-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }

        let vc2 = show(fixture: .timePickersCompact) as! TimePickersCompactViewController
        vc2.set(date: .mockDecember15th2019At10AMUTC())
        vc2.openTimePickerPopover()
        wait(seconds: 1.0)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-compact-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testImages() throws {
        show(fixture: .images)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: recordingMode
            )
        }
    }

    func testUnsupportedView() throws {
        show(fixture: .unsupportedViews)

        let image = try takeSnapshot(with: .allow)
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-allowAll-privacy"),
            record: recordingMode
        )
    }

    func testAlert() throws {
        (show(fixture: .popups) as! PopupsViewController).showAlert()

        wait(seconds: 1.0)

        try forEachPrivacyMode { privacyMode in
            let image = try takeSnapshot(with: privacyMode)
            DDAssertSnapshotTest(
                newImage: image,
                snapshotLocation: .folder(named: snapshotsFolderPath, fileNameSuffix: "-\(privacyMode)-privacy"),
                record: recordingMode
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
            record: recordingMode
        )
    }

    func testActivity() throws {
        (show(fixture: .popups) as! PopupsViewController).showActivity()

        wait(seconds: 1.0)

        let image = try takeSnapshot()
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderPath),
            record: recordingMode
        )
    }

    func testSwiftUI() throws {
        show(fixture: .swiftUI)

        let image = try takeSnapshot()
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderPath),
            record: recordingMode
        )
    }
}
