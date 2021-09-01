/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
@testable import Datadog
@testable import DatadogObjc

extension Datadog.Configuration.LogsEndpoint: Equatable {
    public static func == (_ lhs: Datadog.Configuration.LogsEndpoint, _ rhs: Datadog.Configuration.LogsEndpoint) -> Bool {
        switch (lhs, rhs) {
        case (.us, .us), (.eu, .eu), (.gov, .gov), (.us1, .us1), (.us3, .us3), (.eu1, .eu1), (.us1_fed, .us1_fed): return true
        case let (.custom(lhsURL), .custom(rhsURL)): return lhsURL == rhsURL
        default: return false
        }
    }
}

extension Datadog.Configuration.TracesEndpoint: Equatable {
    public static func == (_ lhs: Datadog.Configuration.TracesEndpoint, _ rhs: Datadog.Configuration.TracesEndpoint) -> Bool {
        switch (lhs, rhs) {
        case (.us, .us), (.eu, .eu), (.gov, .gov), (.us1, .us1), (.us3, .us3), (.eu1, .eu1), (.us1_fed, .us1_fed): return true
        case let (.custom(lhsURL), .custom(rhsURL)): return lhsURL == rhsURL
        default: return false
        }
    }
}

/// This tests verify that objc-compatible `DatadogObjc` wrapper properly interacts with`Datadog` public API (swift).
class DDConfigurationTests: XCTestCase {
    func testDefaultBuilderFowardsInitializationToSwift() throws {
        let objcBuilder = DDConfiguration.builder(clientToken: "abc-123", environment: "tests")
        let objcRUMBuilder = DDConfiguration.builder(rumApplicationID: "rum-app-id", clientToken: "abc-123", environment: "tests")

        let swiftConfiguration = objcBuilder.build().sdkConfiguration
        let swiftConfigurationRUM = objcRUMBuilder.build().sdkConfiguration

        XCTAssertFalse(swiftConfiguration.rumEnabled)
        XCTAssertTrue(swiftConfigurationRUM.rumEnabled)

        XCTAssertNil(swiftConfiguration.rumApplicationID)
        XCTAssertEqual(swiftConfigurationRUM.rumApplicationID, "rum-app-id")

        [swiftConfiguration, swiftConfigurationRUM].forEach { configuration in
            XCTAssertEqual(configuration.clientToken, "abc-123")
            XCTAssertTrue(configuration.loggingEnabled)
            XCTAssertTrue(configuration.tracingEnabled)
            XCTAssertNil(configuration.crashReportingPlugin)
            XCTAssertEqual(configuration.logsEndpoint, .us1)
            XCTAssertEqual(configuration.tracesEndpoint, .us1)
            XCTAssertEqual(configuration.rumEndpoint, .us1)
            XCTAssertEqual(configuration.environment, "tests")
            XCTAssertNil(configuration.serviceName)
            XCTAssertNil(configuration.firstPartyHosts)
            XCTAssertEqual(configuration.rumSessionsSamplingRate, 100.0)
            XCTAssertNil(configuration.rumUIKitViewsPredicate)
            XCTAssertNil(configuration.rumUIKitUserActionsPredicate)
            XCTAssertEqual(configuration.batchSize, .medium)
            XCTAssertEqual(configuration.uploadFrequency, .average)
            XCTAssertNil(configuration.rumViewEventMapper)
            XCTAssertNil(configuration.rumResourceEventMapper)
            XCTAssertNil(configuration.rumActionEventMapper)
            XCTAssertNil(configuration.rumErrorEventMapper)
            XCTAssertEqual(configuration.additionalConfiguration.count, 0)
        }
    }

    func testCustomizedBuilderFowardsInitializationToSwift() throws {
        let objcBuilder = [
            DDConfiguration.builder(clientToken: "abc-123", environment: "tests"),
            DDConfiguration.builder(rumApplicationID: "rum-app-id", clientToken: "abc-123", environment: "tests")
        ].randomElement()!

        objcBuilder.enableLogging(false)
        XCTAssertFalse(objcBuilder.build().sdkConfiguration.loggingEnabled)

        objcBuilder.enableTracing(false)
        XCTAssertFalse(objcBuilder.build().sdkConfiguration.tracingEnabled)

        objcBuilder.enableRUM(false)
        XCTAssertFalse(objcBuilder.build().sdkConfiguration.rumEnabled)

        class CrashReportingPluginMock: NSObject, DDCrashReportingPluginType {
            func readPendingCrashReport(completion: (DDCrashReport?) -> Bool) {}
            func inject(context: Data) {}
        }

        let crashReportingPlugin = CrashReportingPluginMock()
        objcBuilder.enableCrashReporting(using: crashReportingPlugin)
        XCTAssertTrue(objcBuilder.build().sdkConfiguration.crashReportingPlugin === crashReportingPlugin)

        objcBuilder.set(endpoint: .eu1())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .eu1)

        objcBuilder.set(endpoint: .us1())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .us1)

        objcBuilder.set(endpoint: .us3())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .us3)

        objcBuilder.set(endpoint: .us1_fed())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .us1_fed)

        objcBuilder.set(endpoint: .eu())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .eu1)

        objcBuilder.set(endpoint: .us())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .us1)

        objcBuilder.set(endpoint: .gov())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .us1_fed)

        let customLogsEndpoint = URL(string: "https://api.example.com/v1/logs")!
        objcBuilder.set(customLogsEndpoint: customLogsEndpoint)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.customLogsEndpoint, customLogsEndpoint)

        let customTracesEndpoint = URL(string: "https://api.example.com/v1/traces")!
        objcBuilder.set(customTracesEndpoint: customTracesEndpoint)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.customTracesEndpoint, customTracesEndpoint)

        let customRUMEndpoint = URL(string: "https://api.example.com/v1/rum")!
        objcBuilder.set(customRUMEndpoint: customRUMEndpoint)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.customRUMEndpoint, customRUMEndpoint)

        objcBuilder.set(serviceName: "service-name")
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.serviceName, "service-name")

        objcBuilder.trackURLSession(firstPartyHosts: ["example.com"])
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.firstPartyHosts, ["example.com"])

        objcBuilder.trackUIKitRUMActions()
        XCTAssertTrue(objcBuilder.build().sdkConfiguration.rumUIKitUserActionsPredicate is DefaultUIKitRUMUserActionsPredicate)

        objcBuilder.trackUIKitRUMViews()
        XCTAssertTrue(objcBuilder.build().sdkConfiguration.rumUIKitViewsPredicate is DefaultUIKitRUMViewsPredicate)

        class ObjCViewPredicate: DDUIKitRUMViewsPredicate {
            func rumView(for viewController: UIViewController) -> DDRUMView? { nil }
        }
        let viewPredicate = ObjCViewPredicate()
        objcBuilder.trackUIKitRUMViews(using: viewPredicate)
        XCTAssertTrue((objcBuilder.build().sdkConfiguration.rumUIKitViewsPredicate as? UIKitRUMViewsPredicateBridge)?.objcPredicate === viewPredicate)

        class ObjCActionPredicate: DDUIKitRUMUserActionsPredicate {
            func rumAction(targetView: UIView) -> DDRUMAction? { nil }
        }
        let actionPredicate = ObjCActionPredicate()
        objcBuilder.trackUIKitRUMActions(using: actionPredicate)
        XCTAssertTrue((objcBuilder.build().sdkConfiguration.rumUIKitUserActionsPredicate as? UIKitRUMUserActionsPredicateBridge)?.objcPredicate === actionPredicate)

        objcBuilder.set(rumSessionsSamplingRate: 42.5)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.rumSessionsSamplingRate, 42.5)

        objcBuilder.setRUMViewEventMapper { $0 }
        XCTAssertNotNil(objcBuilder.build().sdkConfiguration.rumViewEventMapper)

        objcBuilder.setRUMResourceEventMapper { _ in nil }
        XCTAssertNotNil(objcBuilder.build().sdkConfiguration.rumResourceEventMapper)

        objcBuilder.setRUMActionEventMapper { _ in nil }
        XCTAssertNotNil(objcBuilder.build().sdkConfiguration.rumActionEventMapper)

        objcBuilder.setRUMErrorEventMapper { _ in nil }
        XCTAssertNotNil(objcBuilder.build().sdkConfiguration.rumErrorEventMapper)

        objcBuilder.set(batchSize: .small)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.batchSize, .small)

        objcBuilder.set(batchSize: .large)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.batchSize, .large)

        objcBuilder.set(uploadFrequency: .frequent)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.uploadFrequency, .frequent)

        objcBuilder.set(uploadFrequency: .rare)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.uploadFrequency, .rare)

        objcBuilder.set(additionalConfiguration: ["foo": 42, "bar": "something"])
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.additionalConfiguration["foo"] as? Int, 42)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.additionalConfiguration["bar"] as? String, "something")
    }

    func testScrubbingRUMEvents() {
        let objcBuilder = DDConfiguration.builder(
            rumApplicationID: "rum-app-id",
            clientToken: "abc-123",
            environment: "tests"
        )

        let swiftViewEvent: RUMViewEvent = .mockRandom()
        let swiftResourceEvent: RUMResourceEvent = .mockRandom()
        let swiftActionEvent: RUMActionEvent = .mockRandom()
        let swiftErrorEvent: RUMErrorEvent = .mockRandom()

        objcBuilder.setRUMViewEventMapper { objcViewEvent in
            XCTAssertEqual(objcViewEvent.swiftModel, swiftViewEvent)
            objcViewEvent.view.url = "redacted view.url"
            return objcViewEvent
        }

        objcBuilder.setRUMResourceEventMapper { objcResourceEvent in
            XCTAssertEqual(objcResourceEvent.swiftModel, swiftResourceEvent)
            objcResourceEvent.view.url = "redacted view.url"
            objcResourceEvent.resource.url = "redacted resource.url"
            return objcResourceEvent
        }

        objcBuilder.setRUMActionEventMapper { objcActionEvent in
            XCTAssertEqual(objcActionEvent.swiftModel, swiftActionEvent)
            objcActionEvent.view.url = "redacted view.url"
            objcActionEvent.action.target?.name = "redacted action.target.name"
            return objcActionEvent
        }

        objcBuilder.setRUMErrorEventMapper { objcErrorEvent in
            XCTAssertEqual(objcErrorEvent.swiftModel, swiftErrorEvent)
            objcErrorEvent.view.url = "redacted view.url"
            objcErrorEvent.error.message = "redacted error.message"
            objcErrorEvent.error.resource?.url = "redacted error.resource.url"
            return objcErrorEvent
        }

        let configuration = objcBuilder.build().sdkConfiguration

        let redactedSwiftViewEvent = configuration.rumViewEventMapper?(swiftViewEvent)
        let redactedSwiftResourceEvent = configuration.rumResourceEventMapper?(swiftResourceEvent)
        let redactedSwiftActionEvent = configuration.rumActionEventMapper?(swiftActionEvent)
        let redactedSwiftErrorEvent = configuration.rumErrorEventMapper?(swiftErrorEvent)

        XCTAssertEqual(redactedSwiftViewEvent?.view.url, "redacted view.url")
        XCTAssertEqual(redactedSwiftResourceEvent?.view.url, "redacted view.url")
        XCTAssertEqual(redactedSwiftResourceEvent?.resource.url, "redacted resource.url")
        XCTAssertEqual(redactedSwiftActionEvent?.view.url, "redacted view.url")
        XCTAssertEqual(redactedSwiftActionEvent?.action.target?.name, "redacted action.target.name")
        XCTAssertEqual(redactedSwiftErrorEvent?.view.url, "redacted view.url")
        XCTAssertEqual(redactedSwiftErrorEvent?.error.message, "redacted error.message")
        XCTAssertEqual(redactedSwiftErrorEvent?.error.resource?.url, "redacted error.resource.url")
    }

    func testDroppingRUMEvents() {
        let objcBuilder = DDConfiguration.builder(
            rumApplicationID: "rum-app-id",
            clientToken: "abc-123",
            environment: "tests"
        )

        objcBuilder.setRUMResourceEventMapper { _ in nil }
        objcBuilder.setRUMActionEventMapper { _ in nil }
        objcBuilder.setRUMErrorEventMapper { _ in nil }

        let configuration = objcBuilder.build().sdkConfiguration

        XCTAssertNil(configuration.rumResourceEventMapper?(.mockRandom()))
        XCTAssertNil(configuration.rumActionEventMapper?(.mockRandom()))
        XCTAssertNil(configuration.rumErrorEventMapper?(.mockRandom()))
    }

    func testDeprecatedTrackUIActions() {
        let objcBuilder = DDConfiguration.builder(clientToken: "abc-123", environment: "tests")

        (objcBuilder as DDConfigurationBuilderDeprecatedAPIs).trackUIKitActions()

        XCTAssertTrue(objcBuilder.build().sdkConfiguration.rumUIKitUserActionsPredicate is DefaultUIKitRUMUserActionsPredicate)
    }
}

/// An assistant protocol to shim the deprecated APIs and call them with no compiler warning.
private protocol DDConfigurationBuilderDeprecatedAPIs {
    func trackUIKitActions()
}
extension DDConfigurationBuilder: DDConfigurationBuilderDeprecatedAPIs {}
