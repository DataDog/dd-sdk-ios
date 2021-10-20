/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DataOrchestratorTests: XCTestCase {
    private let queue = DispatchQueue(label: "dd-tests-data-orchestrator")

    override func setUp() {
        super.setUp()
        temporaryFeatureDirectories.create()
    }

    override func tearDown() {
        temporaryFeatureDirectories.delete()
        super.tearDown()
    }

    func testGivenFilesStoredInOrchestratedDirectories_whenDeletingAllData_itRemovesAllFiles() throws {
        let directory1 = temporaryFeatureDirectories.authorized
        let directory2 = temporaryFeatureDirectories.unauthorized
        let performance = StoragePerformanceMock.readAllFiles
        let dateProvider = SystemDateProvider()

        let filesOrchestrator1 = FilesOrchestrator(directory: directory1, performance: performance, dateProvider: dateProvider)
        let filesOrchestrator2 = FilesOrchestrator(directory: directory2, performance: performance, dateProvider: dateProvider)
        let dataOrchestrator = DataOrchestrator(
            queue: queue,
            authorizedFilesOrchestrator: filesOrchestrator1,
            unauthorizedFilesOrchestrator: filesOrchestrator2
        )

        // Given
        let numberOfFiles: Int = .mockRandom(min: 10, max: 50)
        try (0..<numberOfFiles).forEach { index in
            let directory = Bool.random() ? directory1 : directory2
            _ = try directory.createFile(named: "file-\(index)")
        }

        XCTAssertEqual(try directory1.files().count + directory2.files().count, numberOfFiles)

        // When
        dataOrchestrator.deleteAllData()
        queue.sync {} // wait for async operation completion

        // Then
        XCTAssertEqual(try directory1.files().count + directory2.files().count, 0, "It should remove all files")
    }
}
