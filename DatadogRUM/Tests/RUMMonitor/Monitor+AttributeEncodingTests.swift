/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Internal)
import DatadogInternal
@testable import DatadogRUM
@testable import TestUtilities

/// Tests that verify attribute encoding error handling in RUM events.
/// These tests use `AnyEncodable` to wrap non-`Encodable` types, simulating real production scenarios:
/// - **ObjC APIs** (primary production path): Customers use ObjC APIs like `addAttribute(forKey:value:)` which accepts `Any`.
///   SDK automatically wraps values in `AnyEncodable`, losing type safety. Telemetry shows this is the dominant error path.
/// - **Swift APIs with manual wrapping**: Swift API requires `Encodable`, but customers can explicitly wrap non-encodable
///   types using `AnyEncodable(value)` to bypass compile-time checks, e.g. passing closures/blocks, `NSObject`, custom classes.
class Monitor_AttributeEncodingTests: XCTestCase {
    private let featureScope = FeatureScopeMock()
    private var monitor: Monitor! // swiftlint:disable:this implicitly_unwrapped_optional

    private struct AlwaysFailingAttribute: Encodable {
        func encode(to encoder: Encoder) throws {
            throw EncodingError.invalidValue(
                self,
                .init(codingPath: encoder.codingPath, debugDescription: "failure")
            )
        }
    }

    override func setUp() {
        monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: SystemDateProvider()
        )
    }

    override func tearDown() {
        monitor = nil
    }

    // MARK: - Custom attributes (context.*)

    func testWhenCustomAttributeFailsToEncode_itIsNullAndEventIsSent() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        monitor.addAttribute(forKey: "valid", value: "test")
        monitor.addAttribute(forKey: "invalid", value: AnyEncodable(NSObject()))
        monitor.notifySDKInit()

        // Then
        let viewEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        let jsonData = try encodeForStorage(viewEvent)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: jsonData) as? [String: Any], "Expected encoded RUM view event JSON to be a dictionary")
        let context = json["context"] as? [String: Any]

        XCTAssertEqual(context?["valid"] as? String, "test", "Valid attribute should be present in the event")
        XCTAssertTrue(context?["invalid"] is NSNull, "Non-encodable attribute should be null")

        XCTAssertEqual(
            dd.logger.errorLogs.filter { $0.message.contains("Failed to encode attribute 'invalid'") }.count,
            1,
            "One error should be logged for the null attribute"
        )
    }

    func testWhenCustomAttributeThrowsAfterPartialEncoding_itIsNullAndEventIsSent() throws {
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

        let poison = ThrowingAfterPartialEncode()
        monitor.addAttribute(forKey: "before", value: "before")
        monitor.addAttribute(forKey: "poison", value: poison)
        monitor.addAttribute(forKey: "after", value: "after")
        monitor.notifySDKInit()

        let viewEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        let jsonData = try encodeForStorage(viewEvent)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        let context = try XCTUnwrap(json["context"] as? [String: Any])

        XCTAssertEqual(context["before"] as? String, "before")
        XCTAssertTrue(context["poison"] is NSNull)
        XCTAssertEqual(context["after"] as? String, "after")
        XCTAssertEqual(poison.encodeCount, 2)
        XCTAssertTrue(try XCTUnwrap(dd.logger.errorLog).message.contains("attribute 'poison'"))
    }

    // MARK: - User info extra attributes (usr.*)

    func testWhenUserInfoExtraAttributeFailsToEncode_itIsNullAndEventIsSent() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        featureScope.contextMock = .mockWith(userInfo: UserInfo(
            id: "user-id",
            extraInfo: [
                "valid_info": "test",
                "invalid_info": AnyEncodable(NSObject())
            ]
        ))

        // When
        monitor.notifySDKInit()

        // Then
        let viewEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        let jsonData = try encodeForStorage(viewEvent)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: jsonData) as? [String: Any], "Expected encoded RUM view event JSON to be a dictionary")
        let usr = json["usr"] as? [String: Any]

        XCTAssertEqual(usr?["valid_info"] as? String, "test", "Valid user info attribute should be present")
        XCTAssertTrue(usr?["invalid_info"] is NSNull, "Non-encodable user info attribute should be null")

        XCTAssertEqual(
            dd.logger.errorLogs.filter { $0.message.contains("Failed to encode") && $0.message.contains("invalid_info") }.count,
            1
        )
    }

    // MARK: - Account info extra attributes (account.*)

    func testWhenAccountInfoExtraAttributeFailsToEncode_itIsNullAndEventIsSent() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        featureScope.contextMock = .mockWith(accountInfo: AccountInfo(
            id: "acc-id",
            extraInfo: [
                "valid_plan": "enterprise",
                "invalid_plan": AnyEncodable(NSObject())
            ]
        ))

        // When
        monitor.notifySDKInit()

        // Then
        let viewEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        let jsonData = try encodeForStorage(viewEvent)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: jsonData) as? [String: Any], "Expected encoded RUM view event JSON to be a dictionary")
        let account = json["account"] as? [String: Any]

        XCTAssertEqual(account?["valid_plan"] as? String, "enterprise", "Valid account info attribute should be present")
        XCTAssertTrue(account?["invalid_plan"] is NSNull, "Non-encodable account info attribute should be null")

        XCTAssertEqual(
            dd.logger.errorLogs.filter { $0.message.contains("Failed to encode") && $0.message.contains("invalid_plan") }.count,
            1
        )
    }

    func testWhenRecoveryAccountAndUserAttributesCollide_itPreservesStaticProperties() throws {
        featureScope.contextMock = .mockWith(
            userInfo: UserInfo(
                id: "user-id",
                extraInfo: ["id": AlwaysFailingAttribute()]
            ),
            accountInfo: AccountInfo(
                id: "account-id",
                extraInfo: ["id": AlwaysFailingAttribute()]
            )
        )

        monitor.notifySDKInit()

        let viewEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        let jsonData = try encodeForStorage(viewEvent)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        let user = try XCTUnwrap(json["usr"] as? [String: Any])
        let account = try XCTUnwrap(json["account"] as? [String: Any])

        XCTAssertEqual(user["id"] as? String, "user-id")
        XCTAssertEqual(account["id"] as? String, "account-id")
    }

    // MARK: - Feature flag values (feature_flags.*)

    func testWhenFeatureFlagValueFailsToEncode_itIsNullAndEventIsSent() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        monitor.notifySDKInit()
        monitor.startView(key: "TestView")
        monitor.addFeatureFlagEvaluation(name: "valid_flag", value: "enabled")
        monitor.addFeatureFlagEvaluation(name: "invalid_flag", value: AnyEncodable(NSObject()))

        // Then
        let viewEvents = featureScope.eventsWritten(ofType: RUMViewEvent.self)
        let viewWithFlags = try XCTUnwrap(viewEvents.last(where: { $0.view.name == "TestView" }))
        let jsonData = try encodeForStorage(viewWithFlags)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: jsonData) as? [String: Any], "Expected encoded RUM view event JSON to be a dictionary")
        let featureFlags = json["feature_flags"] as? [String: Any]

        XCTAssertEqual(featureFlags?["valid_flag"] as? String, "enabled", "Valid feature flag should be present")
        XCTAssertTrue(featureFlags?["invalid_flag"] is NSNull, "Non-encodable feature flag should be null")

        XCTAssertEqual(
            dd.logger.errorLogs.filter { $0.message.contains("Failed to encode") && $0.message.contains("invalid_flag") }.count,
            1
        )
    }

    // MARK: - RUM data store

    func testRUMDataStoreRecoversMalformedAttributes() throws {
        let value = RUMEventAttributes(
            contextInfo: [
                "valid": "preserved",
                "invalid": AlwaysFailingAttribute(),
            ]
        )

        featureScope.rumDataStore.setValue(value, forKey: .watchdogRUMViewEvent)

        let storedValue = try XCTUnwrap(
            featureScope.dataStoreMock.value(forKey: RUMDataStore.Key.watchdogRUMViewEvent.rawValue)
        )
        let data = try XCTUnwrap(storedValue.data())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["valid"] as? String, "preserved")
        XCTAssertTrue(json["invalid"] is NSNull)
    }

    private func encodeForStorage<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder.dd.default().dd.encodeWithAttributeRecovery(value)
    }
}
