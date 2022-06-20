/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DirectoriesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override func tearDown() {
        temporaryDirectory.delete()
        super.tearDown()
    }

    func testGivenDifferentSDKConfigurations_whenCreatingCoreDirectories_thenEachDirectoryIsUnique() throws {
        // Given
        let sdkConfigurations: [CoreConfiguration] = (0..<50).map { index in
            let randomClientToken: String = .mockRandom(among: .alphanumerics, length: 31) + "\(index)"

            return .mockWith(clientToken: randomClientToken)
        }

        // When
        let coreDirectories = try sdkConfigurations.map { sdkConfiguration in
            try CoreDirectory(in: temporaryDirectory, from: sdkConfiguration)
        }
        defer { coreDirectories.forEach { $0.delete() } }

        // Then
        let uniqueCoreDirectoryURLs = Set(coreDirectories.map({ $0.coreDirectory.url }))
        XCTAssertEqual(
            sdkConfigurations.count,
            uniqueCoreDirectoryURLs.count,
            "It must create unique core directory URL for each SDK configuration"
        )
    }

    func testGivenCoreDirectory_whenCreatingFeatureDirectories_thenTheirPathsAreRelative() throws {
        // Given
        let coreDirectory = temporaryCoreDirectory.create()
        defer { coreDirectory.delete() }

        // When
        let randomAuthorizedPath: String = .mockRandom(among: .alphanumerics)
        let randomUnauthorizedPath: String = .mockRandom(among: .alphanumerics)

        let randomFeatureConfiguration = FeatureStorageConfiguration(
            directories: .init(
                authorized: randomAuthorizedPath,
                unauthorized: randomUnauthorizedPath,
                deprecated: []
            ),
            featureName: .mockRandom()
        )
        let featureDirectories = try coreDirectory.getFeatureDirectories(configuration: randomFeatureConfiguration)

        // Then
        XCTAssertTrue(
            featureDirectories.authorized.url.path.contains(coreDirectory.coreDirectory.url.path),
            "Feature's authorized directory must be relative to core directory"
        )
        XCTAssertTrue(
            featureDirectories.unauthorized.url.path.contains(coreDirectory.coreDirectory.url.path),
            "Feature's unauthorized directory must be relative to core directory"
        )
    }

    func testGivenCoreDirectory_whenCreatingFeatureDirectories_thenItObtainsOnlyDeprecatedPathsThatExist() throws {
        // Given
        let coreDirectory = temporaryCoreDirectory.create()
        defer { coreDirectory.delete() }

        let randomExisingDeprecatedPaths: [String] = (0..<5).map { _ in .mockRandom(among: .alphanumerics) }
        let randomNotExistingDeprecatedPaths: [String] = (0..<5).map { _ in .mockRandom(among: .alphanumerics) }

        try randomExisingDeprecatedPaths.forEach { _ = try coreDirectory.osDirectory.createSubdirectory(path: $0) }

        // When
        let randomFeatureConfiguration = FeatureStorageConfiguration(
            directories: .init(
                authorized: .mockRandom(among: .alphanumerics),
                unauthorized: .mockRandom(among: .alphanumerics),
                deprecated: (randomExisingDeprecatedPaths + randomNotExistingDeprecatedPaths).shuffled()
            ),
            featureName: .mockRandom()
        )
        let featureDirectories = try coreDirectory.getFeatureDirectories(configuration: randomFeatureConfiguration)

        // Then
        XCTAssertEqual(
            featureDirectories.deprecated.count,
            randomExisingDeprecatedPaths.count,
            "It must obtain directory for each deprecated path that exists"
        )
        featureDirectories.deprecated.forEach { deprecatedDirectory in
            XCTAssertTrue(
                deprecatedDirectory.url.path.contains(coreDirectory.osDirectory.url.path),
                "Feature's deprecated directory must be relative to OS directory"
            )
            XCTAssertFalse(
                deprecatedDirectory.url.path.contains(coreDirectory.coreDirectory.url.path),
                "Feature's deprecated directory must NOT be relative to core directory"
            )
        }
    }
}
