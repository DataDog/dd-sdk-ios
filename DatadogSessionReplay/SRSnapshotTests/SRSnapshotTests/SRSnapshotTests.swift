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

        var image = try takeSnapshot(configuration: .init(privacy: .allowAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-allowAll-privacy"),
            record: recordingMode
        )

        image = try takeSnapshot(configuration: .init(privacy: .maskAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-maskAll-privacy"),
            record: recordingMode
        )
    }

    func testSliders() throws {
        show(fixture: .sliders)

        var image = try takeSnapshot(configuration: .init(privacy: .allowAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-allowAll-privacy"),
            record: recordingMode
        )

        image = try takeSnapshot(configuration: .init(privacy: .maskAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-maskAll-privacy"),
            record: recordingMode
        )
    }

    func testSegments() throws {
        show(fixture: .segments)

        var image = try takeSnapshot(configuration: .init(privacy: .allowAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-allowAll-privacy"),
            record: recordingMode
        )

        image = try takeSnapshot(configuration: .init(privacy: .maskAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-maskAll-privacy"),
            record: recordingMode
        )
    }

    func testPickers() throws {
        show(fixture: .pickers)

        var image = try takeSnapshot(configuration: .init(privacy: .allowAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-allowAll-privacy"),
            record: recordingMode
        )

        image = try takeSnapshot(configuration: .init(privacy: .maskAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-maskAll-privacy"),
            record: recordingMode
        )
    }

    func testSwitches() throws {
        show(fixture: .switches)

        var image = try takeSnapshot(configuration: .init(privacy: .allowAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-allowAll-privacy"),
            record: recordingMode
        )

        image = try takeSnapshot(configuration: .init(privacy: .maskAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-maskAll-privacy"),
            record: recordingMode
        )
    }

    func testTextFields() throws {
        show(fixture: .textFields)

        var image = try takeSnapshot(configuration: .init(privacy: .allowAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-allowAll-privacy"),
            record: recordingMode
        )

        image = try takeSnapshot(configuration: .init(privacy: .maskAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-maskAll-privacy"),
            record: recordingMode
        )
    }

    func testSteppers() throws {
        show(fixture: .steppers)

        var image = try takeSnapshot(configuration: .init(privacy: .allowAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-allowAll-privacy"),
            record: recordingMode
        )

        image = try takeSnapshot(configuration: .init(privacy: .maskAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-maskAll-privacy"),
            record: recordingMode
        )
    }

    func testDatePickers() throws {
        let vc1 = show(fixture: .datePickersInline) as! DatePickersInlineViewController
        vc1.set(date: .mockDecember15th2019At10AMUTC())
        wait(seconds: 0.25)

        var image = try takeSnapshot(configuration: .init(privacy: .allowAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-inline-allowAll-privacy"),
            record: recordingMode
        )

        image = try takeSnapshot(configuration: .init(privacy: .maskAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-inline-maskAll-privacy"),
            record: recordingMode
        )

        let vc2 = show(fixture: .datePickersCompact) as! DatePickersCompactViewController
        vc2.set(date: .mockDecember15th2019At10AMUTC())
        vc2.openCalendarPopover()
        wait(seconds: 0.25)

        image = try takeSnapshot(configuration: .init(privacy: .allowAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-compact-allowAll-privacy"),
            record: recordingMode
        )

        image = try takeSnapshot(configuration: .init(privacy: .maskAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-compact-maskAll-privacy"),
            record: recordingMode
        )

        let vc3 = show(fixture: .datePickersWheels) as! DatePickersWheelsViewController
        vc3.set(date: .mockDecember15th2019At10AMUTC())
        wait(seconds: 0.25)

        image = try takeSnapshot(configuration: .init(privacy: .allowAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-wheels-allowAll-privacy"),
            record: recordingMode
        )

        image = try takeSnapshot(configuration: .init(privacy: .maskAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-wheels-maskAll-privacy"),
            record: recordingMode
        )
    }

    func testTimePickers() throws {
        show(fixture: .timePickersCountDown)

        var image = try takeSnapshot(configuration: .init(privacy: .allowAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-count-down-allowAll-privacy"),
            record: recordingMode
        )

        image = try takeSnapshot(configuration: .init(privacy: .maskAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-count-down-maskAll-privacy"),
            record: recordingMode
        )

        let vc1 = show(fixture: .timePickersWheels) as! TimePickersWheelViewController
        vc1.set(date: .mockDecember15th2019At10AMUTC())
        wait(seconds: 0.25)

        image = try takeSnapshot(configuration: .init(privacy: .allowAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-wheels-allowAll-privacy"),
            record: recordingMode
        )

        image = try takeSnapshot(configuration: .init(privacy: .maskAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-wheels-maskAll-privacy"),
            record: recordingMode
        )

        let vc2 = show(fixture: .timePickersCompact) as! TimePickersCompactViewController
        vc2.set(date: .mockDecember15th2019At10AMUTC())
        vc2.openTimePickerPopover()
        wait(seconds: 0.25)

        image = try takeSnapshot(configuration: .init(privacy: .allowAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-compact-allowAll-privacy"),
            record: recordingMode
        )

        image = try takeSnapshot(configuration: .init(privacy: .maskAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-compact-maskAll-privacy"),
            record: recordingMode
        )
    }

    func testImages() throws {
        show(fixture: .images)

        var image = try takeSnapshot(configuration: .init(privacy: .allowAll))
        DDAssertSnapshotTest(
            newImage: image,

            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-allowAll-privacy"),
            record: recordingMode
        )

        image = try takeSnapshot(configuration: .init(privacy: .maskAll))
        DDAssertSnapshotTest(
            newImage: image,
            snapshotLocation: .folder(named: snapshotsFolderName, fileNameSuffix: "-maskAll-privacy"),
            record: recordingMode
        )
    }
}
