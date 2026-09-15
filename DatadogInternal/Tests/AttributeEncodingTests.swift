/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@_spi(Internal)
@testable import DatadogInternal

class AttributeEncodingTests: XCTestCase {
    private let encoder = JSONEncoder()

    private struct AlwaysFailingAttribute: Encodable {
        func encode(to encoder: Encoder) throws {
            throw EncodingError.invalidValue(
                self,
                .init(codingPath: encoder.codingPath, debugDescription: "failure")
            )
        }
    }

    // MARK: - AttributeEncodingContext Tests

    func testAttributeEncodingContextErrorMessagePrefixes() {
        XCTAssertEqual(AttributeEncodingContext.custom.errorMessagePrefix, "")
        XCTAssertEqual(AttributeEncodingContext.userInfo.errorMessagePrefix, "user info ")
        XCTAssertEqual(AttributeEncodingContext.accountInfo.errorMessagePrefix, "account ")
        XCTAssertEqual(AttributeEncodingContext.internal.errorMessagePrefix, "internal ")
    }

    // MARK: - encodeAttribute Tests

    func testEncodeAttributeWithValidValueEncodesSuccessfully() throws {
        // Given
        struct TestEvent: Encodable {
            enum CodingKeys: String, CodingKey {
                case stringAttr
                case intAttr
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                container.encodeAttribute(AnyEncodable("test"), forKey: .stringAttr, attributeName: CodingKeys.stringAttr.rawValue)
                container.encodeAttribute(AnyEncodable(42), forKey: .intAttr, attributeName: CodingKeys.intAttr.rawValue)
            }
        }

        // When
        let encodedData = try encoder.encode(TestEvent())
        let jsonObject = try JSONSerialization.jsonObject(with: encodedData) as! [String: Any]

        // Then
        XCTAssertEqual(jsonObject["stringAttr"] as? String, "test")
        XCTAssertEqual(jsonObject["intAttr"] as? Int, 42)
    }

    func testEncodeAttributeWithInvalidValueEncodesNullAndLogsError() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        class NonEncodableObject {}

        struct TestEvent: Encodable {
            let nonEncodableValue: Any

            enum CodingKeys: String, CodingKey {
                case validAttr
                case invalidAttr
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                container.encodeAttribute(AnyEncodable("valid"), forKey: .validAttr, attributeName: CodingKeys.validAttr.rawValue)
                container.encodeAttribute(AnyEncodable(nonEncodableValue), forKey: .invalidAttr, attributeName: CodingKeys.invalidAttr.rawValue)
            }
        }

        // When
        let encodedData = try encoder.encode(TestEvent(nonEncodableValue: NonEncodableObject()))
        let jsonObject = try JSONSerialization.jsonObject(with: encodedData) as! [String: Any]

        // Then - valid attribute is present, invalid is null
        XCTAssertEqual(jsonObject["validAttr"] as? String, "valid")
        XCTAssertTrue(jsonObject["invalidAttr"] is NSNull)

        // And error is logged
        let errorLog = try XCTUnwrap(dd.logger.errorLog)
        XCTAssertTrue(
            errorLog.message.contains("Failed to encode attribute 'invalidAttr'")
        )
        XCTAssertTrue(
            errorLog.message.contains("This attribute will be encoded as null")
        )
    }

    func testEncodeAttributeWithCustomContextUsesNoPrefix() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        class NonEncodableObject {}

        struct TestEvent: Encodable {
            enum CodingKeys: String, CodingKey {
                case customAttr
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                container.encodeAttribute(
                    AnyEncodable(NonEncodableObject()),
                    forKey: .customAttr,
                    attributeName: CodingKeys.customAttr.rawValue,
                    context: .custom
                )
            }
        }

        // When
        _ = try encoder.encode(TestEvent())

        // Then
        let errorMessage = try XCTUnwrap(dd.logger.errorLog).message
        XCTAssertTrue(errorMessage.contains("Failed to encode attribute 'customAttr'"))
    }

    func testEncodeAttributeWithUserInfoContextUsesCorrectPrefix() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        struct UserInfoStruct: Encodable {
            enum CodingKeys: String, CodingKey {
                case customField = "usr.customField"
            }

            let value: Any

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                container.encodeAttribute(
                    AnyEncodable(value),
                    forKey: .customField,
                    attributeName: "customField",  // Customer-facing name without prefix
                    context: .userInfo
                )
            }
        }

        class NonEncodableObject {}
        let testStruct = UserInfoStruct(value: NonEncodableObject())

        // When
        _ = try encoder.encode(testStruct)

        // Then
        let errorLog = try XCTUnwrap(dd.logger.errorLog)
        XCTAssertTrue(
            errorLog.message.contains("Failed to encode user info attribute 'customField'")
        )
    }

    func testEncodeAttributeWithAccountInfoContextUsesCorrectPrefix() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        struct AccountInfoStruct: Encodable {
            enum CodingKeys: String, CodingKey {
                case accountField = "account.accountField"
            }

            let value: Any

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                container.encodeAttribute(
                    AnyEncodable(value),
                    forKey: .accountField,
                    attributeName: "accountField",  // Customer-facing name without prefix
                    context: .accountInfo
                )
            }
        }

        class NonEncodableObject {}
        let testStruct = AccountInfoStruct(value: NonEncodableObject())

        // When
        _ = try encoder.encode(testStruct)

        // Then
        let errorLog = try XCTUnwrap(dd.logger.errorLog)
        XCTAssertTrue(
            errorLog.message.contains("Failed to encode account attribute 'accountField'")
        )
    }

    func testEncodeAttributeWithInternalContextUsesCorrectPrefix() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        struct InternalStruct: Encodable {
            enum CodingKeys: String, CodingKey {
                case internalField
            }

            let value: Any

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                container.encodeAttribute(
                    AnyEncodable(value),
                    forKey: .internalField,
                    attributeName: CodingKeys.internalField.rawValue,
                    context: .internal
                )
            }
        }

        class NonEncodableObject {}
        let testStruct = InternalStruct(value: NonEncodableObject())

        // When
        _ = try encoder.encode(testStruct)

        // Then
        let errorLog = try XCTUnwrap(dd.logger.errorLog)
        XCTAssertTrue(
            errorLog.message.contains("Failed to encode internal attribute 'internalField'")
        )
    }

    func testEncodeAttributeThrowingAfterPartialEncodeDoesNotAffectSubsequentAttributes() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        struct ThrowingAfterPartialEncode: Encodable {
            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(["partial value"])
                throw EncodingError.invalidValue(
                    0,
                    .init(codingPath: encoder.codingPath, debugDescription: "thrown after encoding a value")
                )
            }
        }

        struct TestEvent: Encodable {
            enum CodingKeys: String, CodingKey {
                case before
                case poison
                case after
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                container.encodeAttribute(AnyEncodable("before"), forKey: .before, attributeName: CodingKeys.before.rawValue)
                container.encodeAttribute(ThrowingAfterPartialEncode(), forKey: .poison, attributeName: CodingKeys.poison.rawValue)
                container.encodeAttribute(AnyEncodable("after"), forKey: .after, attributeName: CodingKeys.after.rawValue)
            }
        }

        // When
        let encodedData = try encoder.encode(TestEvent())
        let jsonObject = try JSONSerialization.jsonObject(with: encodedData) as! [String: Any]

        // Then
        XCTAssertEqual(jsonObject["before"] as? String, "before")
        XCTAssertTrue(jsonObject["poison"] is NSNull)
        XCTAssertEqual(jsonObject["after"] as? String, "after")

        let errorLog = try XCTUnwrap(dd.logger.errorLog)
        XCTAssertTrue(
            errorLog.message.contains("Failed to encode attribute 'poison'")
        )
    }

    func testEncodeAttributeWithCustomScalarEncodesSuccessfully() throws {
        struct CustomScalar: Encodable {
            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode("custom")
            }
        }

        struct TestEvent: Encodable {
            enum CodingKeys: String, CodingKey {
                case attribute
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                container.encodeAttribute(
                    CustomScalar(),
                    forKey: .attribute,
                    attributeName: CodingKeys.attribute.rawValue
                )
            }
        }

        let encodedData = try encoder.encode(TestEvent())
        let jsonObject = try JSONSerialization.jsonObject(with: encodedData) as! [String: Any]

        XCTAssertEqual(jsonObject["attribute"] as? String, "custom")
    }

    // MARK: - Context attribute recovery

    func testAccountInfoRecoveryPreservesStaticPropertiesWhenExtraInfoKeysCollide() throws {
        let accountInfo = AccountInfo(
            id: "account-id",
            name: "account-name",
            extraInfo: [
                "id": AlwaysFailingAttribute(),
                "name": AlwaysFailingAttribute(),
            ]
        )

        let data = try encoder.dd.encodeWithAttributeRecovery(accountInfo)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["id"] as? String, "account-id")
        XCTAssertEqual(json["name"] as? String, "account-name")
    }

    func testUserInfoRecoveryPreservesStaticPropertiesWhenExtraInfoKeysCollide() throws {
        let userInfo = UserInfo(
            anonymousId: "anonymous-id",
            id: "user-id",
            name: "user-name",
            email: "user@example.com",
            extraInfo: [
                "anonymousId": AlwaysFailingAttribute(),
                "id": AlwaysFailingAttribute(),
                "name": AlwaysFailingAttribute(),
                "email": AlwaysFailingAttribute(),
            ]
        )

        let data = try encoder.dd.encodeWithAttributeRecovery(userInfo)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["anonymousId"] as? String, "anonymous-id")
        XCTAssertEqual(json["id"] as? String, "user-id")
        XCTAssertEqual(json["name"] as? String, "user-name")
        XCTAssertEqual(json["email"] as? String, "user@example.com")
    }

    // MARK: - Attribute recovery

    func testAttributeRecoveryIsDisabledByDefault() throws {
        struct TestEvent: Encodable {
            enum CodingKeys: String, CodingKey {
                case shouldRecover
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(encoder.shouldRecoverAttributeFailures, forKey: .shouldRecover)
            }
        }

        let data = try JSONEncoder().encode(TestEvent())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["shouldRecover"] as? Bool, false)
    }

    func testDirectEncodingDoesNotRecoverAttributeFailure() {
        struct TestEvent: Encodable {
            enum CodingKeys: String, CodingKey {
                case invalid
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeAttribute(
                    AlwaysFailingAttribute(),
                    forKey: .invalid,
                    attributeName: CodingKeys.invalid.rawValue,
                    context: .custom,
                    shouldRecover: encoder.shouldRecoverAttributeFailures
                )
            }
        }

        XCTAssertThrowsError(try JSONEncoder().encode(TestEvent()))
    }

    func testEncodeWithAttributeRecoveryDoesNotRetrySuccessfulEvent() throws {
        final class CountingValue: Encodable {
            private(set) var encodeCount = 0
            private(set) var userInfoCounts: [Int] = []

            func encode(to encoder: Encoder) throws {
                encodeCount += 1
                userInfoCounts.append(encoder.userInfo.count)
                var container = encoder.singleValueContainer()
                try container.encode("value")
            }
        }

        struct TestEvent: Encodable {
            let value: CountingValue

            enum CodingKeys: String, CodingKey {
                case value
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeAttribute(
                    value,
                    forKey: .value,
                    attributeName: CodingKeys.value.rawValue,
                    context: .custom,
                    shouldRecover: encoder.shouldRecoverAttributeFailures
                )
            }
        }

        let value = CountingValue()
        let encodedData = try JSONEncoder().dd.encodeWithAttributeRecovery(TestEvent(value: value))
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])

        XCTAssertEqual(value.encodeCount, 1)
        XCTAssertEqual(value.userInfoCounts, [0])
        XCTAssertEqual(jsonObject["value"] as? String, "value")
    }

    func testEncodeWithAttributeRecoveryPreservesEncoderStrategies() throws {
        struct TestEvent: Encodable {
            enum CodingKeys: String, CodingKey {
                case date
                case data
                case url
                case decimal
                case dictionary
                case infinity
                case invalid
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                let shouldRecover = encoder.shouldRecoverAttributeFailures
                try container.encodeAttribute(
                    Date(timeIntervalSince1970: 0),
                    forKey: .date,
                    attributeName: CodingKeys.date.rawValue,
                    context: .custom,
                    shouldRecover: shouldRecover
                )
                try container.encodeAttribute(
                    Data([1, 2, 3]),
                    forKey: .data,
                    attributeName: CodingKeys.data.rawValue,
                    context: .custom,
                    shouldRecover: shouldRecover
                )
                try container.encodeAttribute(
                    URL(string: "https://example.com/path?q=1")!,
                    forKey: .url,
                    attributeName: CodingKeys.url.rawValue,
                    context: .custom,
                    shouldRecover: shouldRecover
                )
                try container.encodeAttribute(
                    Decimal(string: "123.45")!,
                    forKey: .decimal,
                    attributeName: CodingKeys.decimal.rawValue,
                    context: .custom,
                    shouldRecover: shouldRecover
                )
                try container.encodeAttribute(
                    ["camelCaseKey": 1],
                    forKey: .dictionary,
                    attributeName: CodingKeys.dictionary.rawValue,
                    context: .custom,
                    shouldRecover: shouldRecover
                )
                try container.encodeAttribute(
                    Double.infinity,
                    forKey: .infinity,
                    attributeName: CodingKeys.infinity.rawValue,
                    context: .custom,
                    shouldRecover: shouldRecover
                )
                try container.encodeAttribute(
                    AlwaysFailingAttribute(),
                    forKey: .invalid,
                    attributeName: CodingKeys.invalid.rawValue,
                    context: .custom,
                    shouldRecover: shouldRecover
                )
            }
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .custom { _, encoder in
            var container = encoder.singleValueContainer()
            try container.encode("custom-data")
        }
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "positive-infinity",
            negativeInfinity: "negative-infinity",
            nan: "nan"
        )

        let encodedData = try encoder.dd.encodeWithAttributeRecovery(TestEvent())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])

        XCTAssertEqual(json["date"] as? String, "1970-01-01T00:00:00Z")
        XCTAssertEqual(json["data"] as? String, "custom-data")
        XCTAssertEqual(json["url"] as? String, "https://example.com/path?q=1")
        XCTAssertEqual((json["decimal"] as? NSNumber)?.doubleValue, 123.45)
        let dictionary = try XCTUnwrap(json["dictionary"] as? [String: Any])
        XCTAssertEqual(dictionary["camelCaseKey"] as? Int, 1)
        XCTAssertNil(dictionary["camel_case_key"])
        XCTAssertEqual(json["infinity"] as? String, "positive-infinity")
        XCTAssertTrue(json["invalid"] is NSNull)
    }

    func testEncodeWithAttributeRecoveryRetriesOnceAndContainsAllFailures() throws {
        final class CountingValue: Encodable {
            private(set) var encodeCount = 0
            private(set) var userInfoCounts: [Int] = []
            private(set) var recoveryStates: [Bool] = []

            func encode(to encoder: Encoder) throws {
                encodeCount += 1
                userInfoCounts.append(encoder.userInfo.count)
                recoveryStates.append(encoder.shouldRecoverAttributeFailures)
                var container = encoder.singleValueContainer()
                try container.encode("call-\(encodeCount)")
            }
        }

        final class ThrowingValue: Encodable {
            private(set) var encodeCount = 0

            func encode(to encoder: Encoder) throws {
                encodeCount += 1
                var container = encoder.singleValueContainer()
                try container.encode("partial")
                throw EncodingError.invalidValue(
                    encodeCount,
                    .init(codingPath: encoder.codingPath, debugDescription: "failure")
                )
            }
        }

        struct TestEvent: Encodable {
            let before: CountingValue
            let firstFailure: ThrowingValue
            let secondFailure: ThrowingValue
            let after: CountingValue

            enum CodingKeys: String, CodingKey {
                case before
                case firstFailure
                case secondFailure
                case after
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                let shouldRecover = encoder.shouldRecoverAttributeFailures
                try container.encodeAttribute(before, forKey: .before, attributeName: "before", context: .custom, shouldRecover: shouldRecover)
                try container.encodeAttribute(firstFailure, forKey: .firstFailure, attributeName: "firstFailure", context: .custom, shouldRecover: shouldRecover)
                try container.encodeAttribute(secondFailure, forKey: .secondFailure, attributeName: "secondFailure", context: .custom, shouldRecover: shouldRecover)
                try container.encodeAttribute(after, forKey: .after, attributeName: "after", context: .custom, shouldRecover: shouldRecover)
            }
        }

        let before = CountingValue()
        let firstFailure = ThrowingValue()
        let secondFailure = ThrowingValue()
        let after = CountingValue()
        let event = TestEvent(
            before: before,
            firstFailure: firstFailure,
            secondFailure: secondFailure,
            after: after
        )

        let encodedData = try JSONEncoder().dd.encodeWithAttributeRecovery(event)
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])

        XCTAssertEqual(before.encodeCount, 2)
        XCTAssertEqual(before.userInfoCounts, [0, 1])
        XCTAssertEqual(before.recoveryStates, [false, true])
        XCTAssertEqual(firstFailure.encodeCount, 2)
        XCTAssertEqual(secondFailure.encodeCount, 1)
        XCTAssertEqual(after.encodeCount, 1)
        XCTAssertEqual(jsonObject["before"] as? String, "call-2")
        XCTAssertTrue(jsonObject["firstFailure"] is NSNull)
        XCTAssertTrue(jsonObject["secondFailure"] is NSNull)
        XCTAssertEqual(jsonObject["after"] as? String, "call-1")
    }

    func testEncodeWithAttributeRecoveryContainsAStatefulValueThatThrowsOnlyOnRetry() throws {
        final class SucceedsOnceThenThrows: Encodable {
            private(set) var encodeCount = 0

            func encode(to encoder: Encoder) throws {
                encodeCount += 1
                var container = encoder.singleValueContainer()
                try container.encode("partial")
                if encodeCount > 1 {
                    throw EncodingError.invalidValue(
                        encodeCount,
                        .init(codingPath: encoder.codingPath, debugDescription: "failure on retry")
                    )
                }
            }
        }

        struct AlwaysThrows: Encodable {
            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode("partial")
                throw EncodingError.invalidValue(
                    0,
                    .init(codingPath: encoder.codingPath, debugDescription: "trigger recovery")
                )
            }
        }

        struct TestEvent: Encodable {
            let stateful: SucceedsOnceThenThrows

            enum CodingKeys: String, CodingKey {
                case stateful
                case trigger
                case after
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                let shouldRecover = encoder.shouldRecoverAttributeFailures
                try container.encodeAttribute(stateful, forKey: .stateful, attributeName: "stateful", context: .custom, shouldRecover: shouldRecover)
                try container.encodeAttribute(AlwaysThrows(), forKey: .trigger, attributeName: "trigger", context: .custom, shouldRecover: shouldRecover)
                try container.encodeAttribute("after", forKey: .after, attributeName: "after", context: .custom, shouldRecover: shouldRecover)
            }
        }

        let stateful = SucceedsOnceThenThrows()
        let encodedData = try JSONEncoder().dd.encodeWithAttributeRecovery(TestEvent(stateful: stateful))
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])

        XCTAssertEqual(stateful.encodeCount, 2)
        XCTAssertTrue(jsonObject["stateful"] is NSNull)
        XCTAssertTrue(jsonObject["trigger"] is NSNull)
        XCTAssertEqual(jsonObject["after"] as? String, "after")
    }

    func testEncodeWithAttributeRecoveryPreservesPrecisionAndEncoderContext() throws {
        final class ContextAwareValue: Encodable {
            private(set) var encodeCount = 0

            enum CodingKeys: String, CodingKey {
                case decimal
                case codingPath
                case userInfo
            }

            func encode(to encoder: Encoder) throws {
                encodeCount += 1
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(Decimal(string: "12345678901234567890.123456789")!, forKey: .decimal)
                try container.encode(encoder.codingPath.map(\.stringValue).joined(separator: "."), forKey: .codingPath)
                let key = CodingUserInfoKey(rawValue: "attribute-recovery-test")!
                try container.encode(encoder.userInfo[key] as? String, forKey: .userInfo)
            }
        }

        struct AlwaysThrows: Encodable {
            func encode(to encoder: Encoder) throws {
                throw EncodingError.invalidValue(
                    0,
                    .init(codingPath: encoder.codingPath, debugDescription: "trigger recovery")
                )
            }
        }

        struct TestEvent: Encodable {
            let value: ContextAwareValue

            enum CodingKeys: String, CodingKey {
                case value
                case trigger
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                let shouldRecover = encoder.shouldRecoverAttributeFailures
                try container.encodeAttribute(value, forKey: .value, attributeName: "value", context: .custom, shouldRecover: shouldRecover)
                try container.encodeAttribute(AlwaysThrows(), forKey: .trigger, attributeName: "trigger", context: .custom, shouldRecover: shouldRecover)
            }
        }

        let value = ContextAwareValue()
        let encoder = JSONEncoder()
        encoder.userInfo[CodingUserInfoKey(rawValue: "attribute-recovery-test")!] = "preserved"
        let encodedData = try encoder.dd.encodeWithAttributeRecovery(TestEvent(value: value))
        let jsonString = try XCTUnwrap(String(data: encodedData, encoding: .utf8))
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedData) as? [String: Any])
        let encodedValue = try XCTUnwrap(jsonObject["value"] as? [String: Any])

        XCTAssertEqual(value.encodeCount, 2)
        XCTAssertTrue(jsonString.contains("12345678901234567890.123456789"))
        XCTAssertEqual(encodedValue["codingPath"] as? String, "value")
        XCTAssertEqual(encodedValue["userInfo"] as? String, "preserved")
        XCTAssertTrue(jsonObject["trigger"] is NSNull)
    }
}
