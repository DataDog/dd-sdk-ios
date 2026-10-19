/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@_spi(Internal)
import DatadogInternal
@testable import DatadogLogs

final class LogEventEncodingTests: XCTestCase {
    private struct AlwaysFailingAttribute: Encodable {
        func encode(to encoder: Encoder) throws {
            throw EncodingError.invalidValue(
                self,
                .init(codingPath: encoder.codingPath, debugDescription: "failure")
            )
        }
    }

    func testAttributeEncodingDoesNotRetrySuccessfulEvent() throws {
        final class CountingValue: Encodable {
            private(set) var encodeCount = 0

            func encode(to encoder: Encoder) throws {
                encodeCount += 1
                var container = encoder.singleValueContainer()
                try container.encode("value")
            }
        }

        let value = CountingValue()
        let event = LogEvent.mockWith(
            userInfo: .empty,
            accountInfo: AccountInfo(id: "account", name: nil, extraInfo: [:]),
            networkConnectionInfo: .mockWith(),
            mobileCarrierInfo: nil,
            attributes: .mockWith(userAttributes: ["value": value], internalAttributes: nil)
        )

        let data = try JSONEncoder.dd.default().dd.encodeWithAttributeRecovery(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(value.encodeCount, 1)
        XCTAssertEqual(json["value"] as? String, "value")
    }

    func testAttributeEncodingReplacesAValueThatThrowsAfterWritingWithNull() throws {
        final class CountingValue: Encodable {
            private(set) var encodeCount = 0

            func encode(to encoder: Encoder) throws {
                encodeCount += 1
                var container = encoder.singleValueContainer()
                try container.encode("call-\(encodeCount)")
            }
        }

        final class ThrowingAfterPartialEncode: Encodable {
            private(set) var encodeCount = 0

            func encode(to encoder: Encoder) throws {
                encodeCount += 1
                var container = encoder.singleValueContainer()
                try container.encode(["partial value"])
                throw EncodingError.invalidValue(
                    0,
                    .init(codingPath: encoder.codingPath, debugDescription: "thrown after encoding a value")
                )
            }
        }

        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let countingValue = CountingValue()
        let poison = ThrowingAfterPartialEncode()
        let event = LogEvent.mockWith(
            userInfo: UserInfo(extraInfo: ["counted": countingValue]),
            accountInfo: AccountInfo(id: "account", name: nil, extraInfo: [:]),
            networkConnectionInfo: .mockWith(),
            mobileCarrierInfo: nil,
            attributes: .mockWith(
                userAttributes: [
                    "before": "before",
                    "poison": poison,
                    "after": "after",
                ],
                internalAttributes: nil
            )
        )

        let encoder: JSONEncoder = .dd.default()
        let data = try encoder.dd.encodeWithAttributeRecovery(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["before"] as? String, "before")
        XCTAssertTrue(json["poison"] is NSNull)
        XCTAssertEqual(json["after"] as? String, "after")
        XCTAssertEqual(countingValue.encodeCount, 2)
        XCTAssertEqual(json["usr.counted"] as? String, "call-2")
        XCTAssertEqual(poison.encodeCount, 2)
        XCTAssertTrue(try XCTUnwrap(dd.logger.errorLog).message.contains("attribute 'poison'"))
    }

    func testAttributeRecoveryPreservesStaticFieldsWhenAttributeKeysCollide() throws {
        let event = LogEvent.mockWith(
            userInfo: UserInfo(
                anonymousId: "anonymous-id",
                id: "user-id",
                name: "user-name",
                email: "user@example.com",
                extraInfo: [
                    "anonymous_id": AlwaysFailingAttribute(),
                    "id": AlwaysFailingAttribute(),
                    "name": AlwaysFailingAttribute(),
                    "email": AlwaysFailingAttribute(),
                ]
            ),
            accountInfo: AccountInfo(
                id: "account-id",
                name: "account-name",
                extraInfo: [
                    "id": AlwaysFailingAttribute(),
                    "name": AlwaysFailingAttribute(),
                ]
            ),
            networkConnectionInfo: .mockWith(),
            mobileCarrierInfo: nil,
            attributes: .mockWith(
                userAttributes: ["date": AlwaysFailingAttribute()],
                internalAttributes: ["service": AlwaysFailingAttribute()]
            )
        )

        let data = try JSONEncoder.dd.default().dd.encodeWithAttributeRecovery(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["usr.anonymous_id"] as? String, "anonymous-id")
        XCTAssertEqual(json["usr.id"] as? String, "user-id")
        XCTAssertEqual(json["usr.name"] as? String, "user-name")
        XCTAssertEqual(json["usr.email"] as? String, "user@example.com")
        XCTAssertEqual(json["account.id"] as? String, "account-id")
        XCTAssertEqual(json["account.name"] as? String, "account-name")
        XCTAssertFalse(json["date"] is NSNull)
        XCTAssertEqual(json["service"] as? String, event.serviceName)
    }

    func testAttributeEncodingPreservesPrecisionAndCodingPath() throws {
        final class ContextAwareValue: Encodable {
            enum CodingKeys: String, CodingKey {
                case decimal
                case codingPath
            }

            private(set) var encodeCount = 0

            func encode(to encoder: Encoder) throws {
                encodeCount += 1
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(
                    Decimal(string: "12345678901234567890.123456789")!,
                    forKey: .decimal
                )
                try container.encode(
                    encoder.codingPath.map(\.stringValue).joined(separator: "."),
                    forKey: .codingPath
                )
            }
        }

        struct ThrowingValue: Encodable {
            func encode(to encoder: Encoder) throws {
                throw EncodingError.invalidValue(
                    0,
                    .init(codingPath: encoder.codingPath, debugDescription: "failure")
                )
            }
        }

        let value = ContextAwareValue()
        let event = LogEvent.mockWith(
            userInfo: UserInfo(extraInfo: ["structured": value]),
            accountInfo: AccountInfo(id: "account", name: nil, extraInfo: [:]),
            networkConnectionInfo: .mockWith(),
            mobileCarrierInfo: nil,
            attributes: .mockWith(userAttributes: ["poison": ThrowingValue()], internalAttributes: nil)
        )

        let encoder: JSONEncoder = .dd.default()
        let data = try encoder.dd.encodeWithAttributeRecovery(event)
        let jsonString = try XCTUnwrap(String(data: data, encoding: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let structured = try XCTUnwrap(json["usr.structured"] as? [String: Any])

        XCTAssertEqual(value.encodeCount, 2)
        XCTAssertTrue(jsonString.contains("12345678901234567890.123456789"))
        XCTAssertEqual(structured["codingPath"] as? String, "usr.structured")
        XCTAssertTrue(json["poison"] is NSNull)
    }
}
