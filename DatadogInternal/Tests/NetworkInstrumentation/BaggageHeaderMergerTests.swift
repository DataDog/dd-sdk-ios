/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

class BaggageHeaderMergerTests: XCTestCase {
    // MARK: - Basic Functionality Tests

    func testMerge_whenPreviousHeaderIsEmpty_returnsNewHeader() {
        // Given
        let previousHeader = ""
        let newHeader = "session.id=123,user.id=456"

        // When
        let result = BaggageHeaderMerger.merge(previousHeader: previousHeader, with: newHeader)

        // Then
        XCTAssertEqual(
            Set(result.components(separatedBy: ",")),
            Set(newHeader.components(separatedBy: ","))
        )
    }

    func testMerge_whenNewHeaderIsEmpty_returnsPreviousHeader() {
        // Given
        let previousHeader = "session.id=123,user.id=456"
        let newHeader = ""

        // When
        let result = BaggageHeaderMerger.merge(previousHeader: previousHeader, with: newHeader)

        // Then
        XCTAssertEqual(
            Set(result.components(separatedBy: ",")),
            Set(previousHeader.components(separatedBy: ","))
        )
    }

    func testMerge_whenBothHeadersAreEmpty_returnsEmpty() {
        // Given
        let previousHeader = ""
        let newHeader = ""

        // When
        let result = BaggageHeaderMerger.merge(previousHeader: previousHeader, with: newHeader)

        // Then
        XCTAssertEqual(result, "")
    }

    func testMerge_whenHeadersAreIdentical_returnsSameHeader() {
        // Given
        let previousHeader = "session.id=123,user.id=456"
        let newHeader = "session.id=123,user.id=456"

        // When
        let result = BaggageHeaderMerger.merge(previousHeader: previousHeader, with: newHeader)

        // Then
        XCTAssertEqual(
            Set(result.components(separatedBy: ",")),
            Set(previousHeader.components(separatedBy: ","))
        )
    }

    // MARK: - Key Merging Tests

    func testMerge_whenNoKeyOverlap_mergesAllKeys() {
        // Given
        let previousHeader = "key1=value1,key2=value2"
        let newHeader = "key3=value3,key4=value4"

        // When
        let result = BaggageHeaderMerger.merge(previousHeader: previousHeader, with: newHeader)

        // Then
        let resultKeys = extractKeys(from: result)
        XCTAssertEqual(resultKeys.count, 4)
        XCTAssertTrue(resultKeys.contains("key1"))
        XCTAssertTrue(resultKeys.contains("key2"))
        XCTAssertTrue(resultKeys.contains("key3"))
        XCTAssertTrue(resultKeys.contains("key4"))
    }

    func testMerge_ddKeysOverrideAndNoDuplicates() {
        // Given
        let previousHeader = "session.id=1,user.id=2,account.id=3"
        let newHeader = "session.id=10,user.id=20,account.id=30"

        // When
        let result = BaggageHeaderMerger.merge(previousHeader: previousHeader, with: newHeader)

        // Then
        // Verify override for SDK-managed keys
        let resultDict = extractKeyValuePairs(from: result)
        XCTAssertEqual(resultDict["session.id"], "10")
        XCTAssertEqual(resultDict["user.id"], "20")
        XCTAssertEqual(resultDict["account.id"], "30")

        // Verify no duplicates
        let parts = result.split(separator: ",")
        let keys = parts.compactMap { part -> String? in
            guard let idx = part.firstIndex(of: "=") else {
                return nil
            }
            return String(part[..<idx]).trimmingCharacters(in: .whitespaces)
        }
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertEqual(keys.filter { $0 == "session.id" }.count, 1)
        XCTAssertEqual(keys.filter { $0 == "user.id" }.count, 1)
        XCTAssertEqual(keys.filter { $0 == "account.id" }.count, 1)
    }

    func testMerge_whenKeysOverlap_newValuesOverridePreviousValues() {
        // Given
        let previousHeader = "session.id=123,user.id=456"
        let newHeader = "session.id=789,account.id=101"

        // When
        let result = BaggageHeaderMerger.merge(previousHeader: previousHeader, with: newHeader)

        // Then
        let resultDict = extractKeyValuePairs(from: result)
        XCTAssertEqual(resultDict["session.id"], "789") // New value should override
        XCTAssertEqual(resultDict["user.id"], "456") // Previous value should be preserved
        XCTAssertEqual(resultDict["account.id"], "101") // New value should be added
    }

    // MARK: - Deterministic Formatting

    func testFormat_isDeterministic_sortedByKey() {
        // Given
        let previousHeader = "b=2,a=1,c=3"
        let newHeader = "d=4"

        // When
        let result = BaggageHeaderMerger.merge(previousHeader: previousHeader, with: newHeader)

        // Then
        // Expect lexicographic order of keys
        XCTAssertEqual(result, "a=1,b=2,c=3,d=4")
    }

    // MARK: - Complex Scenario Test (from user requirements)

    func testMerge_complexScenarioWithSemicolonsAndWhitespace() {
        // Given
        let previousHeader = " toto=1,car= Dacia Sandero ,session.id = 2,testProp=1; testProp2=4;prop3 "
        let newHeader = "session.id=11,account.id=21, user.id = 3 "

        // When
        let result = BaggageHeaderMerger.merge(previousHeader: previousHeader, with: newHeader)

        // Then
        let resultDict = extractKeyValuePairs(from: result)

        // Verify that new values override previous ones
        XCTAssertEqual(resultDict["session.id"], "11") // New value should override

        // Verify that previous values are preserved when not overridden
        XCTAssertEqual(resultDict["toto"], "1")
        XCTAssertEqual(resultDict["car"], "Dacia Sandero")
        XCTAssertEqual(resultDict["testProp"], "1; testProp2=4;prop3") // Everything after first = is value

        // Verify that new values are added
        XCTAssertEqual(resultDict["account.id"], "21")
        XCTAssertEqual(resultDict["user.id"], "3")

        // Verify all expected keys are present
        XCTAssertEqual(resultDict.keys.count, 6)
    }

    // MARK: - Whitespace Handling Tests

    func testMerge_handlesWhitespaceInKeys() {
        // Given
        let previousHeader = " key1 = value1 , key2= value2"
        let newHeader = "key3 =value3, key4 = value4 "

        // When
        let result = BaggageHeaderMerger.merge(previousHeader: previousHeader, with: newHeader)

        // Then
        let resultDict = extractKeyValuePairs(from: result)
        XCTAssertEqual(resultDict["key1"], "value1")
        XCTAssertEqual(resultDict["key2"], "value2")
        XCTAssertEqual(resultDict["key3"], "value3")
        XCTAssertEqual(resultDict["key4"], "value4")
    }

    func testMerge_handlesWhitespaceInValues() {
        // Given
        let previousHeader = "key1= value with spaces "
        let newHeader = "key2 =  another value  "

        // When
        let result = BaggageHeaderMerger.merge(previousHeader: previousHeader, with: newHeader)

        // Then
        let resultDict = extractKeyValuePairs(from: result)
        XCTAssertEqual(resultDict["key1"], "value with spaces")
        XCTAssertEqual(resultDict["key2"], "another value")
    }

    // MARK: - Edge Cases

    func testMerge_handlesEmptyKeys() {
        // Given
        let previousHeader = "=value1,key2=value2"
        let newHeader = "key3=value3,=value4"

        // When
        let result = BaggageHeaderMerger.merge(previousHeader: previousHeader, with: newHeader)

        // Then
        let resultDict = extractKeyValuePairs(from: result)
        // Empty keys should be ignored
        XCTAssertEqual(resultDict.keys.count, 2)
        XCTAssertEqual(resultDict["key2"], "value2")
        XCTAssertEqual(resultDict["key3"], "value3")
    }

    func testMerge_handlesEmptyValues() {
        // Given
        let previousHeader = "key1=,key2=value2"
        let newHeader = "key3=value3,key4="

        // When
        let result = BaggageHeaderMerger.merge(previousHeader: previousHeader, with: newHeader)

        // Then
        let resultDict = extractKeyValuePairs(from: result)
        XCTAssertEqual(resultDict["key1"], "")
        XCTAssertEqual(resultDict["key2"], "value2")
        XCTAssertEqual(resultDict["key3"], "value3")
        XCTAssertEqual(resultDict["key4"], "")
    }

    func testMerge_handlesMultipleEquals() {
        // Given
        let previousHeader = "key1=value=with=equals"
        let newHeader = "key2=another=value=with=equals"

        // When
        let result = BaggageHeaderMerger.merge(previousHeader: previousHeader, with: newHeader)

        // Then
        let resultDict = extractKeyValuePairs(from: result)
        XCTAssertEqual(resultDict["key1"], "value=with=equals")
        XCTAssertEqual(resultDict["key2"], "another=value=with=equals")
    }

    func testMerge_handlesInvalidFields() {
        // Given
        let previousHeader = "key1=value1,invalidfield,key2=value2"
        let newHeader = "key3=value3,anotherinvalidfield,key4=value4"

        // When
        let result = BaggageHeaderMerger.merge(previousHeader: previousHeader, with: newHeader)

        // Then
        let resultDict = extractKeyValuePairs(from: result)
        // Invalid fields (without =) should be ignored
        XCTAssertEqual(resultDict.keys.count, 4)
        XCTAssertEqual(resultDict["key1"], "value1")
        XCTAssertEqual(resultDict["key2"], "value2")
        XCTAssertEqual(resultDict["key3"], "value3")
        XCTAssertEqual(resultDict["key4"], "value4")
    }

    func testMerge_handlesWhitespaceOnlyKeys() {
        // Given
        let previousHeader = "   =value1,key2=value2"
        let newHeader = "key3=value3,\t\t=value4"

        // When
        let result = BaggageHeaderMerger.merge(previousHeader: previousHeader, with: newHeader)

        // Then
        let resultDict = extractKeyValuePairs(from: result)
        // Whitespace-only keys should be ignored after trimming
        XCTAssertEqual(resultDict.keys.count, 2)
        XCTAssertEqual(resultDict["key2"], "value2")
        XCTAssertEqual(resultDict["key3"], "value3")
        XCTAssertNil(resultDict[""])
        XCTAssertNil(resultDict["   "])
        XCTAssertNil(resultDict["\t\t"])
    }

    func testMerge_handlesEmptyAndWhitespaceKeysComprehensively() {
        // Given
        let previousHeader = "=value1, =value2,\t=value3,key1=validvalue1"
        let newHeader = "key2=validvalue2,   =value4"

        // When
        let result = BaggageHeaderMerger.merge(previousHeader: previousHeader, with: newHeader)

        // Then
        let resultDict = extractKeyValuePairs(from: result)
        // Only valid keys should remain
        XCTAssertEqual(resultDict.keys.count, 2)
        XCTAssertEqual(resultDict["key1"], "validvalue1")
        XCTAssertEqual(resultDict["key2"], "validvalue2")

        // Verify empty and whitespace keys are not present
        XCTAssertNil(resultDict[""])
        XCTAssertNil(resultDict[" "])
        XCTAssertNil(resultDict["\t"])
    }

    // MARK: - Helper Methods

    private func extractKeys(from header: String) -> Set<String> {
        return Set(extractKeyValuePairs(from: header).keys)
    }

    private func extractKeyValuePairs(from header: String) -> [String: String] {
        var dict: [String: String] = [:]
        let fields = header.split(separator: ",")

        for field in fields {
            let fieldString = String(field)
            if let equalIndex = fieldString.firstIndex(of: "=") {
                let key = fieldString[..<equalIndex].trimmingCharacters(in: .whitespaces)
                let value = fieldString[fieldString.index(after: equalIndex)...].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    dict[key] = value
                }
            }
        }

        return dict
    }
}
