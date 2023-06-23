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

        let swiftConfiguration = objcBuilder.build().sdkConfiguration

        [swiftConfiguration].forEach { configuration in
            XCTAssertEqual(configuration.clientToken, "abc-123")
            XCTAssertTrue(configuration.tracingEnabled)
            XCTAssertEqual(configuration.environment, "tests")
            XCTAssertNil(configuration.serviceName)
            XCTAssertNil(configuration.firstPartyHosts)
            XCTAssertEqual(configuration.batchSize, .medium)
            XCTAssertEqual(configuration.uploadFrequency, .average)
            XCTAssertEqual(configuration.additionalConfiguration.count, 0)
            XCTAssertNil(configuration.encryption)
            XCTAssertNil(configuration.serverDateProvider)
        }
    }

    func testCustomizedBuilderForwardsInitializationToSwift() throws {
        let objcBuilder = DDConfiguration.builder(clientToken: "abc-123", environment: "tests")

        objcBuilder.enableTracing(false)
        XCTAssertFalse(objcBuilder.build().sdkConfiguration.tracingEnabled)

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
            clientToken: "abc-123",
            environment: "tests"
        )
        objcBuilder.set(encryption: encryption)
        let configuration = objcBuilder.build().sdkConfiguration

        // Then
        XCTAssertEqual(try configuration.encryption?.encrypt(data: .mockRandom()), encryption.encData)
        XCTAssertEqual(try configuration.encryption?.decrypt(data: .mockRandom()), encryption.decData)
    }
}
