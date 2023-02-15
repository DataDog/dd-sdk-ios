/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import SRHost

final class SRSnapshotTests: SnapshotTestCase {
    private let snapshotsFolderName = "_snapshots_"
    private var recordingMode = false

    func testBasicShapes() throws {
        show(fixture: .basicShapes)
        let image = try takeSnapshot()
        try compare(image: image, referenceImage: .inFolder(named: snapshotsFolderName), record: recordingMode)
    }

    func testBasicTexts() throws {
        show(fixture: .basicTexts)

        var image = try takeSnapshot(configuration: .init(privacy: .allowAll))
        try compare(
            image: image,
            referenceImage: .inFolder(named: snapshotsFolderName, imageFileSuffix: "-allowAll-privacy"),
            record: recordingMode
        )

        image = try takeSnapshot(configuration: .init(privacy: .maskAll))
        try compare(
            image: image,
            referenceImage: .inFolder(named: snapshotsFolderName, imageFileSuffix: "-maskAll-privacy"),
            record: recordingMode
        )
    }
}
