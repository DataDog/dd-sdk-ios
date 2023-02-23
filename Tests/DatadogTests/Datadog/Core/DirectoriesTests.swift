/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
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

    func testWhenCreatingCoreDirectory_thenItsNameIsUniqueForClientTokenAndSite() throws {
        // Given
        let fixtures: [(clientToken: String, site: DatadogSite?, expectedName: String)] = [
            ("abcdef", .us1, "d5f91716d9c17bc76cb9931e1f9ff37724a27d4c05f1eb7081f59ea34d44c777"),
            ("abcdef", .us3, "4a2e7e5b459af9976950e85463db2ba1e71500cdd77ead26b41559bf5a372dfb"),
            ("abcdef", .us5, "38028ebbeab2aa980eab9e5a8ee714f93e8118621472697dabe084e6a9c55cd1"),
            ("abcdef", .eu1, "ff203358d7d236d35dd6acbe6f74b2db17c5855c9a8c43d4f9c2d6869af413e9"),
            ("abcdef", .ap1, "e7f8dbbceb3cb6c93d74a8fc6ba9c6a43c05c00b792b65b183f62edb98709c79"),
            ("abcdef", .us1_fed, "2a69100a36ae68ad3b081daa4c254fcade6b804ec71eda9109b7ec4b8317940b"),
            ("abcdef", nil, "bef57ec7f53a6d40beb640a780a639c83bc29ac8a9816f1fc6c5c6dcd93c4721"),
            ("ghijkl", .us1, "158931c9e9576ef6ed1576721227d29e641e3f0ec2083e4bff280684f6b7ca94"),
            ("ghijkl", .us3, "e098808a9b0e3695f6b876ff677e50aaf98034606369abeabd5df45bbe8bb739"),
            ("ghijkl", .us5, "6212ba431e02e4da2da2f36a5fe9d26b4c33641a63be75c22e81196acfde7d91"),
            ("ghijkl", .eu1, "16fbe70ae92694f96bb36021589ae2ae5f050872548c26fe320cde96eac81957"),
            ("ghijkl", .ap1, "396717396bd53c4019640e9b6f6f1848f10fa95752c497d3a93de88e2600d550"),
            ("ghijkl", .us1_fed, "1585291b515c607624ed20935382bde4438ffac64f190b20a064eb6c1b734c6b"),
            ("ghijkl", nil, "54f6ee81b58accbc57adbceb0f50264897626060071dc9e92f897e7b373deb93"),
        ]

        // When
        let coreDirectories = try fixtures.map { clientToken, site, _ in
            try CoreDirectory(
                in: temporaryDirectory,
                from: .mockWith(site: site, clientToken: clientToken)
            )
        }
        defer { coreDirectories.forEach { $0.delete() } }

        // Then
        zip(fixtures, coreDirectories).forEach { fixture, coreDirectory in
            let directoryName = coreDirectory.coreDirectory.url.lastPathComponent
            XCTAssertEqual(directoryName, fixture.expectedName)
            XCTAssertFalse(
                directoryName.contains(fixture.clientToken),
                "The core directory name must not include client token"
            )
        }
    }

    func testGivenDifferentSDKConfigurations_whenCreatingCoreDirectories_thenEachDirectoryIsUnique() throws {
        // Given
        let sdkConfigurations: [CoreConfiguration] = (0..<50).map { index in
            let randomSite: DatadogSite = .mockRandom()
            let randomClientToken: String = .mockRandom(among: .alphanumerics, length: 31) + "\(index)"

            return .mockWith(
                site: randomSite,
                clientToken: randomClientToken
            )
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
        let featureDirectories = try coreDirectory.getFeatureDirectories(forFeatureNamed: .mockRandom())

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
}
