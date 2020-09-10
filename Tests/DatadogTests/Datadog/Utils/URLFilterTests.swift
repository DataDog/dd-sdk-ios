/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class URLFilterTests: XCTestCase {
    func testTracedHosts() {
        let included: Set<String> = ["foo.bar", "example", "my.app.org"]
        let excluded: Set<String> = ["exclude.me", "and.me.too"]
        let filter = URLFilter(includedHosts: included, excludedURLs: excluded)

        for host in included {
            let subdomainURL = URL(string: "http://www.\(host)/foo")!
            XCTAssertTrue(filter.allows(subdomainURL))

            let complexURL = URL(string: "http://johnny:p4ssw0rd@\(host):999/script.ext;param=value?query=value#ref")!
            XCTAssertTrue(filter.allows(complexURL))

            let differentScheme = URL(string: "https://\(host)/foo")!
            XCTAssertTrue(filter.allows(differentScheme))
        }

        let nonIncludedHost = URL(string: "https://non.traced.host")!
        XCTAssertFalse(filter.allows(nonIncludedHost))

        let nonEscapedDotURL = URL(string: "https://foo-bar.com")!
        XCTAssertFalse(filter.allows(nonEscapedDotURL))

        let extendedIncludedHost = URL(string: "https://foo.bar.asd")!
        XCTAssertFalse(filter.allows(extendedIncludedHost))

        let fileURL = URL(string: "file://some-file")!
        XCTAssertTrue(fileURL.isFileURL)
        XCTAssertFalse(filter.allows(fileURL))
    }

    func testExclusionOverrulesInclusion() {
        let included: Set<String> = ["example.com"]
        let excluded: Set<String> = ["http://api.example.com"]
        let filter = URLFilter(includedHosts: included, excludedURLs: excluded)

        let includedURL = URL(string: "http://example.com")!
        XCTAssertTrue(filter.allows(includedURL))

        let includedSubdomainURL = URL(string: "http://www.example.com")!
        XCTAssertTrue(filter.allows(includedSubdomainURL))

        let excludedSubdomainURL = URL(string: "http://api.example.com")!
        XCTAssertFalse(filter.allows(excludedSubdomainURL))

        let excludedSubdomainURLwithPath = URL(string: "http://api.example.com/some/path")!
        XCTAssertFalse(filter.allows(excludedSubdomainURLwithPath))
    }

    func testWildcardInclusion() {
        let included: Set<String> = ["."]
        let excluded: Set<String> = ["http://api.example.com"]
        let filter = URLFilter(includedHosts: included, excludedURLs: excluded)

        let includedURL = URL(string: "http://example.com")!
        XCTAssertTrue(filter.allows(includedURL))

        let includedSubdomainURL = URL(string: "http://www.example.com")!
        XCTAssertTrue(filter.allows(includedSubdomainURL))

        let excludedSubdomainURL = URL(string: "http://api.example.com")!
        XCTAssertFalse(filter.allows(excludedSubdomainURL))

        let excludedSubdomainURLwithPath = URL(string: "http://api.example.com/some/path")!
        XCTAssertFalse(filter.allows(excludedSubdomainURLwithPath))
    }
}
