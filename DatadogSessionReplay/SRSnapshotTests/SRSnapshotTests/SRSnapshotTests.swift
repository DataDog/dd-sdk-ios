/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import SRHost

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
}
