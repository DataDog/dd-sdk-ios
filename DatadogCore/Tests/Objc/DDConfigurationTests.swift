/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import XCTest
import TestUtilities
import DatadogRUM
@_spi(objc)
@testable import DatadogCore

/// These tests verify that Objc APIs properly interact with`Datadog` public API (swift).
class DDConfigurationTests: XCTestCase {
    func testDefaultBuilderForwardsInitializationToSwift() throws {
        let objcConfig = objc_Configuration(clientToken: "abc-123", env: "tests")
        XCTAssertEqual(objcConfig.sdkConfiguration.clientToken, "abc-123")
        XCTAssertEqual(objcConfig.sdkConfiguration.site, .us1)
        XCTAssertEqual(objcConfig.sdkConfiguration.env, "tests")
        XCTAssertNil(objcConfig.sdkConfiguration.service)
        XCTAssertEqual(objcConfig.sdkConfiguration.batchSize, .medium)
        XCTAssertEqual(objcConfig.sdkConfiguration.uploadFrequency, .average)
        XCTAssertEqual(objcConfig.sdkConfiguration.additionalConfiguration.count, 0)
        XCTAssertNil(objcConfig.sdkConfiguration.encryption)
        XCTAssertNotNil(objcConfig.sdkConfiguration.serverDateProvider)
        XCTAssertFalse(objcConfig.sdkConfiguration.backgroundTasksEnabled)
    }

    func testCustomizedBuilderForwardsInitializationToSwift() throws {
        let objcConfig = objc_Configuration(clientToken: "abc-123", env: "tests")

        objcConfig.site = .eu1()
        XCTAssertEqual(objcConfig.sdkConfiguration.site, .eu1)

        objcConfig.site = .ap1()
        XCTAssertEqual(objcConfig.sdkConfiguration.site, .ap1)

        objcConfig.site = .us1()
        XCTAssertEqual(objcConfig.sdkConfiguration.site, .us1)

        objcConfig.site = .us3()
        XCTAssertEqual(objcConfig.sdkConfiguration.site, .us3)

        objcConfig.site = .us5()
        XCTAssertEqual(objcConfig.sdkConfiguration.site, .us5)

        objcConfig.site = .us1_fed()
        XCTAssertEqual(objcConfig.sdkConfiguration.site, .us1_fed)

        objcConfig.service = "service-name"
        XCTAssertEqual(objcConfig.sdkConfiguration.service, "service-name")

        objcConfig.batchSize = .small
        XCTAssertEqual(objcConfig.sdkConfiguration.batchSize, .small)

        objcConfig.batchSize = .large
        XCTAssertEqual(objcConfig.sdkConfiguration.batchSize, .large)

        objcConfig.uploadFrequency = .frequent
        XCTAssertEqual(objcConfig.sdkConfiguration.uploadFrequency, .frequent)

        objcConfig.uploadFrequency = .rare
        XCTAssertEqual(objcConfig.sdkConfiguration.uploadFrequency, .rare)

        objcConfig.batchProcessingLevel = .low
        XCTAssertEqual(objcConfig.sdkConfiguration.batchProcessingLevel, .low)

        objcConfig.batchProcessingLevel = .high
        XCTAssertEqual(objcConfig.sdkConfiguration.batchProcessingLevel, .high)

        objcConfig.proxyConfiguration = [kCFNetworkProxiesHTTPEnable: true, kCFNetworkProxiesHTTPPort: 123, kCFNetworkProxiesHTTPProxy: "www.example.com", kCFProxyUsernameKey: "proxyuser", kCFProxyPasswordKey: "proxypass" ]
        objcConfig.additionalConfiguration = ["additional": "config"]

        XCTAssertEqual(objcConfig.sdkConfiguration.proxyConfiguration?[kCFNetworkProxiesHTTPEnable] as? Bool, true)
        XCTAssertEqual(objcConfig.sdkConfiguration.proxyConfiguration?[kCFNetworkProxiesHTTPPort] as? Int, 123)
        XCTAssertEqual(objcConfig.sdkConfiguration.proxyConfiguration?[kCFNetworkProxiesHTTPProxy] as? String, "www.example.com")
        XCTAssertEqual(objcConfig.sdkConfiguration.proxyConfiguration?[kCFProxyUsernameKey] as? String, "proxyuser")
        XCTAssertEqual(objcConfig.sdkConfiguration.proxyConfiguration?[kCFProxyPasswordKey] as? String, "proxypass")
        XCTAssertEqual(objcConfig.sdkConfiguration._internal.additionalConfiguration["additional"] as? String, "config")

        class ObjCDataEncryption: objc_DataEncryption {
            func encrypt(data: Data) throws -> Data { data }
            func decrypt(data: Data) throws -> Data { data }
        }
        let dataEncryption = ObjCDataEncryption()
        objcConfig.setEncryption(dataEncryption)
        XCTAssertTrue((objcConfig.sdkConfiguration.encryption as? DDDataEncryptionBridge)?.objcEncryption === dataEncryption)

        class ObjcServerDateProvider: objc_ServerDateProvider {
            func synchronize(update: @escaping (TimeInterval) -> Void) { }
        }
        let serverDateProvider = ObjcServerDateProvider()
        objcConfig.setServerDateProvider(serverDateProvider)
        XCTAssertTrue((objcConfig.sdkConfiguration.serverDateProvider as? DDServerDateProviderBridge)?.objcProvider === serverDateProvider)

        let fakeBackgroundTasksEnabled: Bool = .mockRandom()
        objcConfig.backgroundTasksEnabled = fakeBackgroundTasksEnabled
        XCTAssertEqual(objcConfig.sdkConfiguration.backgroundTasksEnabled, fakeBackgroundTasksEnabled)
    }

    func testDataEncryption() throws {
        // Given
        class ObjCDataEncryption: objc_DataEncryption {
            let encData: Data = .mockRandom()
            let decData: Data = .mockRandom()
            func encrypt(data: Data) throws -> Data { encData }
            func decrypt(data: Data) throws -> Data { decData }
        }

        let encryption = ObjCDataEncryption()

        // When
        let objcConfig = objc_Configuration(
            clientToken: "abc-123",
            env: "tests"
        )
        objcConfig.setEncryption(encryption)
        let configuration = objcConfig.sdkConfiguration

        // Then
        XCTAssertEqual(try configuration.encryption?.encrypt(data: .mockRandom()), encryption.encData)
        XCTAssertEqual(try configuration.encryption?.decrypt(data: .mockRandom()), encryption.decData)
    }
}
