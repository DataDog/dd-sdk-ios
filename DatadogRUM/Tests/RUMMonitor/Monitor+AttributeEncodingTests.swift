/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
@testable import TestUtilities

/// Tests that verify attribute encoding behavior for non-encodable types in RUM events.
/// These tests use `AnyEncodable` to wrap non-`Encodable` types, simulating real production scenarios:
/// - **ObjC APIs** (primary production path): Customers use ObjC APIs like `addAttribute(forKey:value:)` which accepts `Any`.
///   SDK automatically wraps values in `AnyEncodable`, losing type safety. Telemetry shows this is the dominant error path.
/// - **Swift APIs with manual wrapping**: Swift API requires `Encodable`, but customers can explicitly wrap non-encodable
///   types using `AnyEncodable(value)` to bypass compile-time checks, e.g. passing closures/blocks, `NSObject`, custom classes.
class Monitor_AttributeEncodingTests: XCTestCase {
    private let featureScope = FeatureScopeMock()
    private var monitor: Monitor! // swiftlint:disable:this implicitly_unwrapped_optional

    // A non-encodable NSObject subclass with a fixed, predictable description
    private class DescribableObject: NSObject {
        override var description: String { "DescribableObject()" }
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

    func testWhenCustomAttributeIsNonEncodable_itIsEncodedAsStringAndEventIsSent() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        monitor.addAttribute(forKey: "valid", value: "test")
        monitor.addAttribute(forKey: "non-encodable", value: AnyEncodable(DescribableObject()))
        monitor.notifySDKInit()

        // Then
        let viewEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        let jsonData = try JSONEncoder().encode(viewEvent)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        let context = json["context"] as? [String: Any]

        XCTAssertEqual(context?["valid"] as? String, "test")
        XCTAssertEqual(context?["non-encodable"] as? String, "DescribableObject()", "Non-encodable attribute should be encoded as its string description")
        XCTAssertTrue(dd.logger.debugLogs.contains { $0.message.contains("It will be encoded as its string description: 'DescribableObject()'") })
    }

    func testWhenAllCustomAttributesAreNonEncodable_itSendsEventWithAttributesAsStrings() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        monitor.addAttribute(forKey: "attr1", value: AnyEncodable(DescribableObject()))
        let closure: (NSArray) -> Void = { _ in }
        monitor.addAttribute(forKey: "attr2", value: AnyEncodable(closure))
        monitor.notifySDKInit()

        // Then - event is sent with both attributes encoded as strings
        let viewEvents = featureScope.eventsWritten(ofType: RUMViewEvent.self)
        XCTAssertEqual(viewEvents.count, 1)

        let viewEvent = try XCTUnwrap(viewEvents.first)
        let jsonData = try JSONEncoder().encode(viewEvent)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        let context = json["context"] as? [String: Any]

        XCTAssertEqual(context?["attr1"] as? String, "DescribableObject()")
        let attr2 = try XCTUnwrap(context?["attr2"] as? String)
        XCTAssertTrue(attr2.contains("(Function)"))
        XCTAssertEqual(dd.logger.debugLogs.filter { $0.message.contains("It will be encoded as its string description") }.count, 2)
    }

    // MARK: - User info extra attributes (usr.*)

    func testWhenUserInfoExtraAttributeIsNonEncodable_itIsEncodedAsStringAndEventIsSent() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        featureScope.contextMock = .mockWith(userInfo: UserInfo(
            id: "user-id",
            extraInfo: [
                "valid_info": "test",
                "non_encodable_info": AnyEncodable(DescribableObject())
            ]
        ))

        // When
        monitor.notifySDKInit()

        // Then
        let viewEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        let jsonData = try JSONEncoder().encode(viewEvent)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        let usr = json["usr"] as? [String: Any]

        XCTAssertEqual(usr?["valid_info"] as? String, "test")
        XCTAssertEqual(usr?["non_encodable_info"] as? String, "DescribableObject()")
        XCTAssertTrue(dd.logger.debugLogs.contains { $0.message.contains("It will be encoded as its string description: 'DescribableObject()'") })
    }

    // MARK: - Account info extra attributes (account.*)

    func testWhenAccountInfoExtraAttributeIsNonEncodable_itIsEncodedAsStringAndEventIsSent() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        featureScope.contextMock = .mockWith(accountInfo: AccountInfo(
            id: "acc-id",
            extraInfo: [
                "valid_plan": "enterprise",
                "non_encodable_plan": AnyEncodable(DescribableObject())
            ]
        ))

        // When
        monitor.notifySDKInit()

        // Then
        let viewEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        let jsonData = try JSONEncoder().encode(viewEvent)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        let account = json["account"] as? [String: Any]

        XCTAssertEqual(account?["valid_plan"] as? String, "enterprise")
        XCTAssertEqual(account?["non_encodable_plan"] as? String, "DescribableObject()")
        XCTAssertTrue(dd.logger.debugLogs.contains { $0.message.contains("It will be encoded as its string description: 'DescribableObject()'") })
    }

    // MARK: - Feature flag values (feature_flags.*)

    func testWhenFeatureFlagValueIsNonEncodable_itIsEncodedAsStringAndEventIsSent() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        monitor.notifySDKInit()
        monitor.startView(key: "TestView")
        monitor.addFeatureFlagEvaluation(name: "valid_flag", value: "enabled")
        monitor.addFeatureFlagEvaluation(name: "non_encodable_flag", value: AnyEncodable(DescribableObject()))

        // Then
        let viewEvents = featureScope.eventsWritten(ofType: RUMViewEvent.self)
        let viewWithFlags = try XCTUnwrap(viewEvents.last(where: { $0.view.name == "TestView" }))
        let jsonData = try JSONEncoder().encode(viewWithFlags)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        let featureFlags = json["feature_flags"] as? [String: Any]

        XCTAssertEqual(featureFlags?["valid_flag"] as? String, "enabled")
        XCTAssertEqual(featureFlags?["non_encodable_flag"] as? String, "DescribableObject()")
        XCTAssertTrue(dd.logger.debugLogs.contains { $0.message.contains("It will be encoded as its string description: 'DescribableObject()'") })
    }
}
