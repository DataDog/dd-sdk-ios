/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import TestUtilities
import XCTest

final class DatadogContextTests: XCTestCase {
    // MARK: - Test ddtags

    func testDatadogDDTags() throws {
        // Given
        let service: String = .mockRandom()
        let env: String = .mockRandom()
        let version: String = .mockRandom()
        let sdkVersion: String = .mockRandom()
        let variant: String = .mockRandom()
        let datadogContext: DatadogContext = .mockWith(
            service: service,
            env: env,
            version: version,
            variant: variant,
            sdkVersion: sdkVersion
        )

        // Then
        let ddTagsArray = datadogContext.ddTags.split(separator: ",")

        let ddTags = ddTagsArray.reduce(into: [:]) {
            let item = $1.split(separator: ":")
            $0[String(item[0])] = String(item[1])
        }

        XCTAssertEqual(ddTags["service"] as! String, service)
        XCTAssertEqual(ddTags["env"] as! String, env)
        XCTAssertEqual(ddTags["version"] as! String, version)
        XCTAssertEqual(ddTags["sdk_version"] as! String, sdkVersion)
        XCTAssertEqual(ddTags["variant"] as! String, variant)
    }

    func testDatadogSanitizedDDTags() throws {
        // Given
        let service = "service:with:colons"
        let env = "prod,dev"
        let version = "1,2,3"
        let sdkVersion = "3,2,1"
        let variant = "variant,with,commas:"
        let datadogContext: DatadogContext = .mockWith(
            service: service,
            env: env,
            version: version,
            variant: variant,
            sdkVersion: sdkVersion
        )

        // Then
        let ddTagsArray = datadogContext.ddTags.split(separator: ",")

        let ddTags = ddTagsArray.reduce(into: [:]) {
            let item = $1.split(separator: ":")
            $0[String(item[0])] = String(item[1])
        }

        XCTAssertEqual(ddTags["service"] as! String, "servicewithcolons")
        XCTAssertEqual(ddTags["env"] as! String, "proddev")
        XCTAssertEqual(ddTags["version"] as! String, "123")
        XCTAssertEqual(ddTags["sdk_version"] as! String, "321")
        XCTAssertEqual(ddTags["variant"] as! String, "variantwithcommas")
    }

    func testDatadogDDTagsWithoutVariant() throws {
        // Given
        let service: String = .mockRandom()
        let env: String = .mockRandom()
        let version: String = .mockRandom()
        let sdkVersion: String = .mockRandom()
        let datadogContext: DatadogContext = .mockWith(
            service: service,
            env: env,
            version: version,
            variant: nil,
            sdkVersion: sdkVersion
        )

        // Then
        let ddTagsArray = datadogContext.ddTags.split(separator: ",")

        let ddTags = ddTagsArray.reduce(into: [:]) {
            let item = $1.split(separator: ":")
            $0[String(item[0])] = String(item[1])
        }

        XCTAssertEqual(ddTags["service"] as! String, service)
        XCTAssertEqual(ddTags["env"] as! String, env)
        XCTAssertEqual(ddTags["version"] as! String, version)
        XCTAssertEqual(ddTags["sdk_version"] as! String, sdkVersion)
        XCTAssertNil(ddTags["variant"])
    }
}
