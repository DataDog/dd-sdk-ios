/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
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

    override func setUp() {
        monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: SystemDateProvider(),
            onSessionUpdate: { _ in }
        )
    }

    override func tearDown() {
        monitor = nil
    }

    // MARK: - Custom attributes (context.*)

    func testWhenCustomAttributeFailsToEncode_itIsDroppedAndEventIsSent() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        monitor.addAttribute(forKey: "valid", value: "test")
        monitor.addAttribute(forKey: "invalid", value: AnyEncodable(NSObject()))
        monitor.notifySDKInit()

        // Then
        let viewEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        let jsonData = try JSONEncoder().encode(viewEvent)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: jsonData) as? [String: Any], "Expected encoded RUM view event JSON to be a dictionary")
        let context = json["context"] as? [String: Any]

        XCTAssertEqual(context?["valid"] as? String, "test", "Valid attribute should be present in the event")
        XCTAssertNil(context?["invalid"], "Non-encodable attribute should be dropped")

        XCTAssertEqual(
            dd.logger.errorLogs.filter { $0.message.contains("Failed to encode attribute 'invalid'") }.count,
            1,
            "One error should be logged for the dropped attribute"
        )
    }

    func testWhenOnlyMalformedCustomAttributesAdded_itSendsEventWithoutCustomAttributes() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        monitor.addAttribute(forKey: "invalid1", value: AnyEncodable(NSObject()))
        let closure: (NSArray) -> Void = { _ in }
        monitor.addAttribute(forKey: "invalid2", value: AnyEncodable(closure))
        monitor.notifySDKInit()

        // Then - event is sent even though all custom attributes are malformed
        let viewEvents = featureScope.eventsWritten(ofType: RUMViewEvent.self)
        XCTAssertEqual(viewEvents.count, 1)

        let viewEvent = try XCTUnwrap(viewEvents.first)
        let jsonData = try JSONEncoder().encode(viewEvent)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: jsonData) as? [String: Any], "Expected encoded RUM view event JSON to be a dictionary")

        XCTAssertNil((json["context"] as? [String: Any])?["invalid1"])
        XCTAssertNil((json["context"] as? [String: Any])?["invalid2"])

        XCTAssertEqual(
            dd.logger.errorLogs.filter { $0.message.contains("Failed to encode attribute") }.count,
            2
        )
    }

    // MARK: - User info extra attributes (usr.*)

    func testWhenUserInfoExtraAttributeFailsToEncode_itIsDroppedAndEventIsSent() throws {
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
        let jsonData = try JSONEncoder().encode(viewEvent)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: jsonData) as? [String: Any], "Expected encoded RUM view event JSON to be a dictionary")
        let usr = json["usr"] as? [String: Any]

        XCTAssertEqual(usr?["valid_info"] as? String, "test", "Valid user info attribute should be present")
        XCTAssertNil(usr?["invalid_info"], "Non-encodable user info attribute should be dropped")

        XCTAssertEqual(
            dd.logger.errorLogs.filter { $0.message.contains("Failed to encode") && $0.message.contains("invalid_info") }.count,
            1
        )
    }

    // MARK: - Account info extra attributes (account.*)

    func testWhenAccountInfoExtraAttributeFailsToEncode_itIsDroppedAndEventIsSent() throws {
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
        let jsonData = try JSONEncoder().encode(viewEvent)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: jsonData) as? [String: Any], "Expected encoded RUM view event JSON to be a dictionary")
        let account = json["account"] as? [String: Any]

        XCTAssertEqual(account?["valid_plan"] as? String, "enterprise", "Valid account info attribute should be present")
        XCTAssertNil(account?["invalid_plan"], "Non-encodable account info attribute should be dropped")

        XCTAssertEqual(
            dd.logger.errorLogs.filter { $0.message.contains("Failed to encode") && $0.message.contains("invalid_plan") }.count,
            1
        )
    }

    // MARK: - Feature flag values (feature_flags.*)

    func testWhenFeatureFlagValueFailsToEncode_itIsDroppedAndEventIsSent() throws {
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
        let jsonData = try JSONEncoder().encode(viewWithFlags)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: jsonData) as? [String: Any], "Expected encoded RUM view event JSON to be a dictionary")
        let featureFlags = json["feature_flags"] as? [String: Any]

        XCTAssertEqual(featureFlags?["valid_flag"] as? String, "enabled", "Valid feature flag should be present")
        XCTAssertNil(featureFlags?["invalid_flag"], "Non-encodable feature flag should be dropped")

        XCTAssertEqual(
            dd.logger.errorLogs.filter { $0.message.contains("Failed to encode") && $0.message.contains("invalid_flag") }.count,
            1
        )
    }
}
