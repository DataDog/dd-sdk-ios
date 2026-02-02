/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal

class AttributeEncodingTests: XCTestCase {
    private let encoder = JSONEncoder()

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

    func testEncodeAttributeWithInvalidValueSkipsAttributeAndLogsError() throws {
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

        // Then - valid attribute is present, invalid is skipped
        XCTAssertEqual(jsonObject["validAttr"] as? String, "valid")
        XCTAssertNil(jsonObject["invalidAttr"])

        // And error is logged
        let errorLog = try XCTUnwrap(dd.logger.errorLog)
        XCTAssertTrue(
            errorLog.message.contains("Failed to encode attribute 'invalidAttr'")
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

    func testEncodeAttributeErrorMessageIncludesDroppedNotice() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        class NonEncodableObject {}

        struct TestEvent: Encodable {
            enum CodingKeys: String, CodingKey {
                case attr
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                container.encodeAttribute(AnyEncodable(NonEncodableObject()), forKey: .attr, attributeName: CodingKeys.attr.rawValue)
            }
        }

        // When
        _ = try encoder.encode(TestEvent())

        // Then
        let errorLog = try XCTUnwrap(dd.logger.errorLog)
        XCTAssertTrue(
            errorLog.message.contains("This attribute will be dropped from the event")
        )
    }
}
