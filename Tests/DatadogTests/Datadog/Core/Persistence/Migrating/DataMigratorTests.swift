/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DataMigratorTests: XCTestCase {
    func testMultiDataMigrator() {
        // Given
        struct Migrator: DataMigrator {
            let expectation: XCTestExpectation
            func migrate() {
                expectation.fulfill()
            }
        }

        let expectation = XCTestExpectation(description: "Invoke migration")
        expectation.expectedFulfillmentCount = 10

        let migrators = (0..<expectation.expectedFulfillmentCount).map { _ in
            Migrator(expectation: expectation)
        }

        // When
        let multiMigrator: DataMigrator = MultiDataMigrator(migrators: migrators)
        multiMigrator.migrate()

        // Then
        wait(for: [expectation], timeout: 0)
    }

    func testDataMigrationFactory_initialMigration() throws {
        // Given
        let deprecated = try Directory(withSubdirectoryPath: UUID().uuidString)
        defer { deprecated.delete() }
        let unauthorized = try Directory(withSubdirectoryPath: UUID().uuidString)
        defer { unauthorized.delete() }
        let authorized = try Directory(withSubdirectoryPath: UUID().uuidString)
        defer { authorized.delete() }

        _ = try deprecated.createFile(named: "deprecated")
        _ = try unauthorized.createFile(named: "unauthorized")
        XCTAssertEqual(try deprecated.files().count, 1)
        XCTAssertEqual(try unauthorized.files().count, 1)

        let directories = FeatureDirectories(deprecated: [deprecated], unauthorized: unauthorized, authorized: authorized)
        let factory = DataMigratorFactory(directories: directories)

        // When
        let migrator = factory.resolveInitialMigrator()
        migrator.migrate()

        // Then
        XCTAssertEqual(try deprecated.files().count, 0)
        XCTAssertEqual(try unauthorized.files().count, 0)
    }

    func testDataMigrationFactory_ConsentPendingToGrantedMigration() throws {
        // Given
        let unauthorized = try Directory(withSubdirectoryPath: UUID().uuidString)
        defer { unauthorized.delete() }
        let authorized = try Directory(withSubdirectoryPath: UUID().uuidString)
        defer { authorized.delete() }

        _ = try unauthorized.createFile(named: "unauthorized")
        XCTAssertEqual(try unauthorized.files().count, 1)
        XCTAssertEqual(try authorized.files().count, 0)

        let directories = FeatureDirectories(deprecated: [], unauthorized: unauthorized, authorized: authorized)
        let factory = DataMigratorFactory(directories: directories)

        // When
        let migrator = factory.resolveMigratorForConsentChange(from: .pending, to: .granted)
        migrator?.migrate()

        // Then
        XCTAssertEqual(try unauthorized.files().count, 0)
        XCTAssertEqual(try authorized.files().count, 1)
    }

    func testDataMigrationFactory_ConsentPendingToNotGrantedMigration() throws {
        // Given
        let unauthorized = try Directory(withSubdirectoryPath: UUID().uuidString)
        defer { unauthorized.delete() }
        let authorized = try Directory(withSubdirectoryPath: UUID().uuidString)
        defer { authorized.delete() }

        _ = try unauthorized.createFile(named: "unauthorized")
        XCTAssertEqual(try unauthorized.files().count, 1)
        XCTAssertEqual(try authorized.files().count, 0)

        let directories = FeatureDirectories(deprecated: [], unauthorized: unauthorized, authorized: authorized)
        let factory = DataMigratorFactory(directories: directories)

        // When
        let migrator = factory.resolveMigratorForConsentChange(from: .pending, to: .notGranted)
        migrator?.migrate()

        // Then
        XCTAssertEqual(try unauthorized.files().count, 0)
        XCTAssertEqual(try authorized.files().count, 0)
    }
}
