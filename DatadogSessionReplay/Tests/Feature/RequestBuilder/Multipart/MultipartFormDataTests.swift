/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

class MultipartFormDataTests: XCTestCase {
    func testBuildingFormData() throws {
        let boundary = UUID(uuidString: "12345678-0000-0000-0000-000000000000")!

        // Given
        var multipart = MultipartFormData(boundary: boundary)

        // When
        multipart.addFormField(name: "field1", value: "value of field1")
        multipart.addFormField(name: "field2", value: "value of field2")
        multipart.addFormField(name: "field3", value: "value of field3")
        multipart.addFormData(
            name: "data1",
            filename: "filename1",
            data: "abcd".data(using: .utf8)!,
            mimeType: "abc/def"
        )
        multipart.addFormData(
            name: "data2",
            filename: "filename2",
            data: "efgh".data(using: .utf8)!,
            mimeType: "foo/bar"
        )

        // Then
        let actualDataString = try XCTUnwrap(String(data: multipart.build(), encoding: .utf8))
        let expectedDataString = """
        --12345678-0000-0000-0000-000000000000
        Content-Disposition: form-data; name="field1"

        value of field1
        --12345678-0000-0000-0000-000000000000
        Content-Disposition: form-data; name="field2"

        value of field2
        --12345678-0000-0000-0000-000000000000
        Content-Disposition: form-data; name="field3"

        value of field3
        --12345678-0000-0000-0000-000000000000
        Content-Disposition: form-data; name="data1"; filename="filename1"
        Content-Type: abc/def

        abcd
        --12345678-0000-0000-0000-000000000000
        Content-Disposition: form-data; name="data2"; filename="filename2"
        Content-Type: foo/bar

        efgh
        --12345678-0000-0000-0000-000000000000--
        """.replacingOccurrences(of: "\n", with: "\r\n")

        XCTAssertEqual(expectedDataString, actualDataString)
    }
}
