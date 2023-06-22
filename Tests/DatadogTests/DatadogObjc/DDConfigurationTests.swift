/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import XCTest
import TestUtilities
import DatadogRUM

@testable import Datadog
@testable import DatadogObjc

/// This tests verify that objc-compatible `DatadogObjc` wrapper properly interacts with`Datadog` public API (swift).
class DDConfigurationTests: XCTestCase {
    func testDefaultBuilderForwardsInitializationToSwift() throws {
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
            XCTAssertTrue(configuration.tracingEnabled)
            XCTAssertEqual(configuration.environment, "tests")
            XCTAssertNil(configuration.serviceName)
            XCTAssertNil(configuration.firstPartyHosts)
            XCTAssertEqual(configuration.rumSessionsSamplingRate, 100.0)
            XCTAssertNil(configuration.rumUIKitViewsPredicate)
            XCTAssertNil(configuration.rumUIKitUserActionsPredicate)
            XCTAssertEqual(configuration.mobileVitalsFrequency, .average)
            XCTAssertEqual(configuration.batchSize, .medium)
            XCTAssertEqual(configuration.uploadFrequency, .average)
            XCTAssertNil(configuration.rumViewEventMapper)
            XCTAssertNil(configuration.rumResourceEventMapper)
            XCTAssertNil(configuration.rumActionEventMapper)
            XCTAssertNil(configuration.rumErrorEventMapper)
            XCTAssertFalse(configuration.rumBackgroundEventTrackingEnabled)
            XCTAssertTrue(configuration.rumFrustrationSignalsTrackingEnabled)
            XCTAssertEqual(configuration.additionalConfiguration.count, 0)
            XCTAssertNil(configuration.encryption)
            XCTAssertNil(configuration.serverDateProvider)
        }
    }

    func testCustomizedBuilderForwardsInitializationToSwift() throws {
        let objcBuilder = [
            DDConfiguration.builder(clientToken: "abc-123", environment: "tests"),
            DDConfiguration.builder(rumApplicationID: "rum-app-id", clientToken: "abc-123", environment: "tests")
        ].randomElement()!

        objcBuilder.enableTracing(false)
        XCTAssertFalse(objcBuilder.build().sdkConfiguration.tracingEnabled)

        objcBuilder.enableRUM(false)
        XCTAssertFalse(objcBuilder.build().sdkConfiguration.rumEnabled)

        objcBuilder.set(endpoint: .eu1())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .eu1)

        objcBuilder.set(endpoint: .ap1())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .ap1)

        objcBuilder.set(endpoint: .us1())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .us1)

        objcBuilder.set(endpoint: .us3())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .us3)

        objcBuilder.set(endpoint: .us5())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .us5)

        objcBuilder.set(endpoint: .us1_fed())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .us1_fed)

        objcBuilder.set(endpoint: .eu())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .eu1)

        objcBuilder.set(endpoint: .us())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .us1)

        objcBuilder.set(endpoint: .gov())
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.datadogEndpoint, .us1_fed)

        let customRUMEndpoint = URL(string: "https://api.example.com/v1/rum")!
        objcBuilder.set(customRUMEndpoint: customRUMEndpoint)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.customRUMEndpoint, customRUMEndpoint)

        objcBuilder.set(serviceName: "service-name")
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.serviceName, "service-name")

        objcBuilder.trackURLSession(firstPartyHosts: ["example.com"])
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.firstPartyHosts, .init(["example.com": [.datadog]]))

        objcBuilder.trackURLSession(firstPartyHostsWithHeaderTypes: ["example2.com": [.tracecontext]])
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.firstPartyHosts, .init([
            "example2.com": [.tracecontext],
            "example.com": [.datadog]
        ]))

        objcBuilder.set(tracingSamplingRate: 75)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.tracingSamplingRate, 75)

        objcBuilder.trackUIKitRUMActions()
        XCTAssertTrue(objcBuilder.build().sdkConfiguration.rumUIKitUserActionsPredicate is DefaultUIKitRUMUserActionsPredicate)

        objcBuilder.trackRUMLongTasks(threshold: 999.0)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.rumLongTaskDurationThreshold, 999.0)

        objcBuilder.trackUIKitRUMViews()
        XCTAssertTrue(objcBuilder.build().sdkConfiguration.rumUIKitViewsPredicate is DefaultUIKitRUMViewsPredicate)

        class ObjCViewPredicate: DDUIKitRUMViewsPredicate {
            func rumView(for viewController: UIViewController) -> DDRUMView? { nil }
        }
        let viewPredicate = ObjCViewPredicate()
        objcBuilder.trackUIKitRUMViews(using: viewPredicate)
        XCTAssertTrue((objcBuilder.build().sdkConfiguration.rumUIKitViewsPredicate as? UIKitRUMViewsPredicateBridge)?.objcPredicate === viewPredicate)

        class ObjCActionPredicate: DDUIKitRUMUserActionsPredicate & DDUITouchRUMUserActionsPredicate & DDUIPressRUMUserActionsPredicate {
            func rumAction(targetView: UIView) -> DDRUMAction? { nil }
            func rumAction(press type: UIPress.PressType, targetView: UIView) -> DDRUMAction? { nil }
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

        objcBuilder.setRUMLongTaskEventMapper { _ in nil }
        XCTAssertNotNil(objcBuilder.build().sdkConfiguration.rumLongTaskEventMapper)

        objcBuilder.trackBackgroundEvents()
        XCTAssertTrue(objcBuilder.build().sdkConfiguration.rumBackgroundEventTrackingEnabled)

        objcBuilder.trackFrustrations(false)
        XCTAssertFalse(objcBuilder.build().sdkConfiguration.rumFrustrationSignalsTrackingEnabled)

        objcBuilder.set(batchSize: .small)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.batchSize, .small)

        objcBuilder.set(mobileVitalsFrequency: .frequent)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.mobileVitalsFrequency, .frequent)

        objcBuilder.set(batchSize: .large)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.batchSize, .large)

        objcBuilder.set(uploadFrequency: .frequent)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.uploadFrequency, .frequent)

        objcBuilder.set(uploadFrequency: .rare)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.uploadFrequency, .rare)

        objcBuilder.set(additionalConfiguration: ["foo": 42, "bar": "something"])
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.additionalConfiguration["foo"] as? Int, 42)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.additionalConfiguration["bar"] as? String, "something")

        objcBuilder.set(proxyConfiguration: [kCFNetworkProxiesHTTPEnable: true, kCFNetworkProxiesHTTPPort: 123, kCFNetworkProxiesHTTPProxy: "www.example.com", kCFProxyUsernameKey: "proxyuser", kCFProxyPasswordKey: "proxypass" ])
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.proxyConfiguration?[kCFNetworkProxiesHTTPEnable] as? Bool, true)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.proxyConfiguration?[kCFNetworkProxiesHTTPPort] as? Int, 123)
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.proxyConfiguration?[kCFNetworkProxiesHTTPProxy] as? String, "www.example.com")
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.proxyConfiguration?[kCFProxyUsernameKey] as? String, "proxyuser")
        XCTAssertEqual(objcBuilder.build().sdkConfiguration.proxyConfiguration?[kCFProxyPasswordKey] as? String, "proxypass")

        class ObjCDataEncryption: DDDataEncryption {
            func encrypt(data: Data) throws -> Data { data }
            func decrypt(data: Data) throws -> Data { data }
        }
        let dataEncryption = ObjCDataEncryption()
        objcBuilder.set(encryption: dataEncryption)
        XCTAssertTrue((objcBuilder.build().sdkConfiguration.encryption as? DDDataEncryptionBridge)?.objcEncryption === dataEncryption)

        class ObjcServerDateProvider: DDServerDateProvider {
            func synchronize(update: @escaping (TimeInterval) -> Void) { }
        }
        let serverDateProvider = ObjcServerDateProvider()
        objcBuilder.set(serverDateProvider: serverDateProvider)
        XCTAssertTrue((objcBuilder.build().sdkConfiguration.serverDateProvider as? DDServerDateProviderBridge)?.objcProvider === serverDateProvider)
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
        let swiftLongTaskEvent: RUMLongTaskEvent = .mockRandom()

        objcBuilder.setRUMViewEventMapper { objcViewEvent in
            DDAssertReflectionEqual(objcViewEvent.swiftModel, swiftViewEvent)
            objcViewEvent.view.url = "redacted view.url"
            return objcViewEvent
        }

        objcBuilder.setRUMResourceEventMapper { objcResourceEvent in
            DDAssertReflectionEqual(objcResourceEvent.swiftModel, swiftResourceEvent)
            objcResourceEvent.view.url = "redacted view.url"
            objcResourceEvent.resource.url = "redacted resource.url"
            return objcResourceEvent
        }

        objcBuilder.setRUMActionEventMapper { objcActionEvent in
            DDAssertReflectionEqual(objcActionEvent.swiftModel, swiftActionEvent)
            objcActionEvent.view.url = "redacted view.url"
            objcActionEvent.action.target?.name = "redacted action.target.name"
            return objcActionEvent
        }

        objcBuilder.setRUMErrorEventMapper { objcErrorEvent in
            DDAssertReflectionEqual(objcErrorEvent.swiftModel, swiftErrorEvent)
            objcErrorEvent.view.url = "redacted view.url"
            objcErrorEvent.error.message = "redacted error.message"
            objcErrorEvent.error.resource?.url = "redacted error.resource.url"
            return objcErrorEvent
        }

        objcBuilder.setRUMLongTaskEventMapper { objcLongTaskEvent in
            DDAssertReflectionEqual(objcLongTaskEvent.swiftModel, swiftLongTaskEvent)
            objcLongTaskEvent.view.url = "redacted view.url"
            return objcLongTaskEvent
        }

        let configuration = objcBuilder.build().sdkConfiguration

        let redactedSwiftViewEvent = configuration.rumViewEventMapper?(swiftViewEvent)
        let redactedSwiftResourceEvent = configuration.rumResourceEventMapper?(swiftResourceEvent)
        let redactedSwiftActionEvent = configuration.rumActionEventMapper?(swiftActionEvent)
        let redactedSwiftErrorEvent = configuration.rumErrorEventMapper?(swiftErrorEvent)
        let redactedSwiftLongTaskEvent = configuration.rumLongTaskEventMapper?(swiftLongTaskEvent)

        XCTAssertEqual(redactedSwiftViewEvent?.view.url, "redacted view.url")
        XCTAssertEqual(redactedSwiftResourceEvent?.view.url, "redacted view.url")
        XCTAssertEqual(redactedSwiftResourceEvent?.resource.url, "redacted resource.url")
        XCTAssertEqual(redactedSwiftActionEvent?.view.url, "redacted view.url")
        XCTAssertEqual(redactedSwiftActionEvent?.action.target?.name, "redacted action.target.name")
        XCTAssertEqual(redactedSwiftErrorEvent?.view.url, "redacted view.url")
        XCTAssertEqual(redactedSwiftErrorEvent?.error.message, "redacted error.message")
        XCTAssertEqual(redactedSwiftErrorEvent?.error.resource?.url, "redacted error.resource.url")
        XCTAssertEqual(redactedSwiftLongTaskEvent?.view.url, "redacted view.url")
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
        objcBuilder.setRUMLongTaskEventMapper { _ in nil }

        let configuration = objcBuilder.build().sdkConfiguration

        XCTAssertNil(configuration.rumResourceEventMapper?(.mockRandom()))
        XCTAssertNil(configuration.rumActionEventMapper?(.mockRandom()))
        XCTAssertNil(configuration.rumErrorEventMapper?(.mockRandom()))
        XCTAssertNil(configuration.rumLongTaskEventMapper?(.mockRandom()))
    }

    func testDataEncryption() throws {
        // Given
        class ObjCDataEncryption: DDDataEncryption {
            let encData: Data = .mockRandom()
            let decData: Data = .mockRandom()
            func encrypt(data: Data) throws -> Data { encData }
            func decrypt(data: Data) throws -> Data { decData }
        }

        let encryption = ObjCDataEncryption()

        // When
        let objcBuilder = DDConfiguration.builder(
            rumApplicationID: "rum-app-id",
            clientToken: "abc-123",
            environment: "tests"
        )
        objcBuilder.set(encryption: encryption)
        let configuration = objcBuilder.build().sdkConfiguration

        // Then
        XCTAssertEqual(try configuration.encryption?.encrypt(data: .mockRandom()), encryption.encData)
        XCTAssertEqual(try configuration.encryption?.decrypt(data: .mockRandom()), encryption.decData)
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
