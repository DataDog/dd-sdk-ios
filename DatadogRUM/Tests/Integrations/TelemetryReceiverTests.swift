/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

/// Utility to access the convenience methods defined in `Telemetry` protocol extension while sending telemetry to tested receiver.
private struct TelemetryMock: Telemetry {
    let receiver: TelemetryReceiver

    init(with receiver: TelemetryReceiver) {
        self.receiver = receiver
    }

    func send(telemetry: TelemetryMessage) {
        let result = receiver.receive(message: .telemetry(telemetry), from: NOPDatadogCore())
        XCTAssertTrue(result, "It must accept every message")
    }
}

class TelemetryReceiverTests: XCTestCase {
    private let featureScope = FeatureScopeMock()

    // MARK: - Sending Telemetry events

    func testSendTelemetryDebug() {
        featureScope.contextMock = .mockWith(
            version: "app-version",
            source: "flutter",
            sdkVersion: "sdk-version"
        )

        // Given
        let receiver = TelemetryReceiver.mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(
                using: .init(timeIntervalSince1970: 0)
            )
        )

        // When
        TelemetryMock(with: receiver).debug("Hello world!", attributes: ["foo": 42])

        // Then
        let event = featureScope.eventsWritten(ofType: TelemetryDebugEvent.self).first
        XCTAssertEqual(event?.date, 0)
        XCTAssertEqual(event?.version, "sdk-version")
        XCTAssertEqual(event?.service, "dd-sdk-ios")
        XCTAssertEqual(event?.source, .flutter)
        XCTAssertEqual(event?.telemetry.message, "Hello world!")
        XCTAssertEqual(event?.telemetry.telemetryInfo as? [String: Int], ["foo": 42])
    }

    func testSendTelemetryError() {
        featureScope.contextMock = .mockWith(
            version: "app-version",
            source: "ios",
            sdkVersion: "sdk-version"
        )

        // Given
        let receiver = TelemetryReceiver.mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(
                using: .init(timeIntervalSince1970: 0)
            )
        )

        // When
        TelemetryMock(with: receiver).error("Oops", kind: "OutOfMemory", stack: "a\nhay\nneedle\nstack")

        // Then
        let event = featureScope.eventsWritten(ofType: TelemetryErrorEvent.self).first
        XCTAssertEqual(event?.date, 0)
        XCTAssertEqual(event?.version, "sdk-version")
        XCTAssertEqual(event?.service, "dd-sdk-ios")
        XCTAssertEqual(event?.source, .ios)
        XCTAssertEqual(event?.telemetry.message, "Oops")
        XCTAssertEqual(event?.telemetry.error?.kind, "OutOfMemory")
        XCTAssertEqual(event?.telemetry.error?.stack, "a\nhay\nneedle\nstack")
    }

    func testSendTelemetryDebug_withRUMContext() {
        // Given
        let rumContext: RUMCoreContext = .mockRandom()
        featureScope.contextMock.baggages = [RUMFeature.name: FeatureBaggage(rumContext)]
        let receiver = TelemetryReceiver.mockWith(featureScope: featureScope)

        // When
        TelemetryMock(with: receiver).debug("telemetry debug", attributes: ["foo": 42])

        // Then
        let event = featureScope.eventsWritten(ofType: TelemetryDebugEvent.self).first
        XCTAssertEqual(event?.telemetry.message, "telemetry debug")
        XCTAssertEqual(event?.application?.id, rumContext.applicationID)
        XCTAssertEqual(event?.session?.id, rumContext.sessionID)
        XCTAssertEqual(event?.view?.id, rumContext.viewID)
        XCTAssertEqual(event?.action?.id, rumContext.userActionID)
        XCTAssertEqual(event?.telemetry.telemetryInfo as? [String: Int], ["foo": 42])
    }

    func testSendTelemetryError_withRUMContext() throws {
        // Given
        let rumContext: RUMCoreContext = .mockRandom()
        featureScope.contextMock.baggages = [RUMFeature.name: FeatureBaggage(rumContext)]
        let receiver = TelemetryReceiver.mockWith(featureScope: featureScope)

        // When
        TelemetryMock(with: receiver).error("telemetry error")

        // Then
        let event = featureScope.eventsWritten(ofType: TelemetryErrorEvent.self).first
        XCTAssertEqual(event?.telemetry.message, "telemetry error")
        XCTAssertEqual(event?.application?.id, rumContext.applicationID)
        XCTAssertEqual(event?.session?.id, rumContext.sessionID)
        XCTAssertEqual(event?.view?.id, rumContext.viewID)
        XCTAssertEqual(event?.action?.id, rumContext.userActionID)
    }

    func testSendTelemetry_discardDuplicates() throws {
        // Given
        let receiver = TelemetryReceiver.mockWith(featureScope: featureScope)
        let telemetry = TelemetryMock(with: receiver)

        // When
        telemetry.debug(id: "0", message: "telemetry debug 0")
        telemetry.error(id: "0", message: "telemetry debug 1", kind: "error.kind", stack: "error.stack")
        telemetry.debug(id: "0", message: "telemetry debug 2")
        telemetry.debug(id: "1", message: "telemetry debug 3")

        for _ in 0...10 {
            // telemetry id is composed of the file, line number, and message
            telemetry.debug("telemetry debug 4")
        }

        for index in 5...10 {
            // telemetry id is composed of the file, line number, and message
            telemetry.debug("telemetry debug \(index)")
        }

        telemetry.debug("telemetry debug 11")

        // Then
        let events = featureScope.eventsWritten(ofType: TelemetryDebugEvent.self)
        XCTAssertEqual(events.count, 10)
        XCTAssertTrue(featureScope.eventsWritten(ofType: TelemetryErrorEvent.self).isEmpty)
        XCTAssertEqual(events[0].telemetry.message, "telemetry debug 0")
        XCTAssertEqual(events[1].telemetry.message, "telemetry debug 3")
        XCTAssertEqual(events[2].telemetry.message, "telemetry debug 4")
        XCTAssertEqual(events[3].telemetry.message, "telemetry debug 5")
        XCTAssertEqual(events.last?.telemetry.message, "telemetry debug 11")
    }

    func testSendTelemetry_toSessionLimit() throws {
        // Given
        let receiver = TelemetryReceiver.mockWith(featureScope: featureScope, sampler: .mockKeepAll())
        let telemetry = TelemetryMock(with: receiver)

        // When
        // sends 101 telemetry events
        for index in 0..<(TelemetryReceiver.maxEventsPerSessions * 2) {
            // swiftlint:disable opening_brace
            oneOf([
                { telemetry.debug(id: "\(index)", message: .mockAny()) },
                { telemetry.error(id: "\(index)", message: .mockAny(), kind: .mockAny(), stack: .mockAny()) },
                { telemetry.metric(name: .mockAny(), attributes: [:]) }
            ])
            // swiftlint:enable opening_brace
        }

        // Then
        let debugEvents = featureScope.eventsWritten(ofType: TelemetryDebugEvent.self)
        let errorEvents = featureScope.eventsWritten(ofType: TelemetryErrorEvent.self)
        XCTAssertEqual(debugEvents.count + errorEvents.count, 100)
    }

    func testSampledTelemetry_rejectAll() throws {
        // Given
        let receiver = TelemetryReceiver.mockWith(featureScope: featureScope, sampler: .mockRejectAll())
        let telemetry = TelemetryMock(with: receiver)

        // When
        // sends 10 telemetry events
        for index in 0..<10 {
            // swiftlint:disable opening_brace
            oneOf([
                { telemetry.debug(id: "debug-\(index)", message: .mockAny()) },
                { telemetry.error(id: "error-\(index)", message: .mockAny(), kind: .mockAny(), stack: .mockAny()) },
                { telemetry.configuration(batchSize: .mockAny()) },
                { telemetry.metric(name: .mockAny(), attributes: [:]) }
            ])
            // swiftlint:enable opening_brace
        }

        // Then
        let events = featureScope.eventsWritten(ofType: TelemetryDebugEvent.self)
        XCTAssertEqual(events.count, 0)
    }

    func testSampledTelemetry_rejectAllConfiguration() throws {
        // Given
        let receiver = TelemetryReceiver.mockWith(
            featureScope: featureScope,
            sampler: .mockKeepAll(),
            configurationExtraSampler: .mockRejectAll()
        )
        let telemetry = TelemetryMock(with: receiver)

        // When
        for index in 0..<10 {
            telemetry.debug(id: "debug-\(index)", message: .mockAny())
            telemetry.error(id: "error-\(index)", message: .mockAny(), kind: .mockAny(), stack: .mockAny())
            telemetry.metric(name: .mockAny(), attributes: [:])
            telemetry.configuration(batchSize: .mockAny())
        }

        // Then
        XCTAssertEqual(featureScope.eventsWritten(ofType: TelemetryDebugEvent.self).count, 20, "It should keep 10 debug events and 10 metrics")
        XCTAssertEqual(featureScope.eventsWritten(ofType: TelemetryErrorEvent.self).count, 10, "It should keep 10 error events")
        XCTAssertTrue(featureScope.eventsWritten(ofType: TelemetryConfigurationEvent.self).isEmpty, "It should reject all configuration events")
    }

    func testSampledTelemetry_rejectAllMetrics() throws {
        // Given
        let receiver = TelemetryReceiver.mockWith(
            featureScope: featureScope,
            sampler: .mockKeepAll(),
            metricsExtraSampler: .mockRejectAll()
        )
        let telemetry = TelemetryMock(with: receiver)

        // When
        for index in 0..<10 {
            telemetry.debug(id: "debug-\(index)", message: .mockAny())
            telemetry.error(id: "error-\(index)", message: .mockAny(), kind: .mockAny(), stack: .mockAny())
            telemetry.metric(name: .mockAny(), attributes: [:])
            telemetry.configuration(batchSize: .mockAny())
        }

        // Then
        XCTAssertEqual(featureScope.eventsWritten(ofType: TelemetryDebugEvent.self).count, 10, "It should keep 10 debug events but no metrics")
        XCTAssertEqual(featureScope.eventsWritten(ofType: TelemetryErrorEvent.self).count, 10, "It should keep 10 error events")
        XCTAssertEqual(featureScope.eventsWritten(ofType: TelemetryConfigurationEvent.self).count, 1, "It should keep 1 configuration event")
    }

    func testSendTelemetry_resetAfterSessionExpire() throws {
        // Given
        let receiver = TelemetryReceiver.mockWith(featureScope: featureScope)
        let telemetry = TelemetryMock(with: receiver)
        let applicationId: String = .mockRandom()

        featureScope.contextMock.baggages[RUMFeature.name] = FeatureBaggage([
            RUMContextAttributes.IDs.applicationID: applicationId,
            RUMContextAttributes.IDs.sessionID: String.mockRandom()
        ])
        telemetry.debug(id: "0", message: "telemetry debug")

        // When
        featureScope.contextMock.baggages[RUMFeature.name] = FeatureBaggage([
            RUMContextAttributes.IDs.applicationID: applicationId,
            RUMContextAttributes.IDs.sessionID: String.mockRandom()
        ])
        telemetry.debug(id: "0", message: "telemetry debug")

        // Then
        let events = featureScope.eventsWritten(ofType: TelemetryDebugEvent.self)
        XCTAssertEqual(events.count, 2, "It should record two telemetries of the same ID as they belong to different session ID")
    }

    // MARK: - Configuration Telemetry Events

    func testSendTelemetryConfiguration() {
        featureScope.contextMock = .mockWith(
            version: "app-version",
            source: "unity",
            sdkVersion: "sdk-version"
        )

        // Given
        let receiver = TelemetryReceiver.mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(using: .init(timeIntervalSince1970: 0))
        )
        let telemetry = TelemetryMock(with: receiver)

        let backgroundTasksEnabled: Bool? = .mockRandom()
        let batchProcessingLevel: Int64? = .mockRandom()
        let batchSize: Int64? = .mockRandom()
        let batchUploadFrequency: Int64? = .mockRandom()
        let dartVersion: String? = .mockRandom()
        let mobileVitalsUpdatePeriod: Int64? = .mockRandom()
        let sessionSampleRate: Int64? = .mockRandom()
        let telemetrySampleRate: Int64? = .mockRandom()
        let traceSampleRate: Int64? = .mockRandom()
        let trackBackgroundEvents: Bool? = .mockRandom()
        let trackCrossPlatformLongTasks: Bool? = .mockRandom()
        let trackErrors: Bool? = .mockRandom()
        let trackFlutterPerformance: Bool? = .mockRandom()
        let trackFrustrations: Bool? = .mockRandom()
        let trackUserInteractions: Bool? = .mockRandom()
        let trackLongTask: Bool? = .mockRandom()
        let trackNativeLongTasks: Bool? = .mockRandom()
        let trackNativeViews: Bool? = .mockRandom()
        let trackNetworkRequests: Bool? = .mockRandom()
        let trackViewsManually: Bool? = .mockRandom()
        let unityVersion: String? = .mockRandom()
        let useFirstPartyHosts: Bool? = .mockRandom()
        let useLocalEncryption: Bool? = .mockRandom()
        let useProxy: Bool? = .mockRandom()
        let useTracing: Bool? = .mockRandom()

        // When
        telemetry.configuration(
            backgroundTasksEnabled: backgroundTasksEnabled,
            batchProcessingLevel: batchProcessingLevel,
            batchSize: batchSize,
            batchUploadFrequency: batchUploadFrequency,
            dartVersion: dartVersion,
            mobileVitalsUpdatePeriod: mobileVitalsUpdatePeriod,
            sessionSampleRate: sessionSampleRate,
            telemetrySampleRate: telemetrySampleRate,
            traceSampleRate: traceSampleRate,
            trackBackgroundEvents: trackBackgroundEvents,
            trackCrossPlatformLongTasks: trackCrossPlatformLongTasks,
            trackErrors: trackErrors,
            trackFlutterPerformance: trackFlutterPerformance,
            trackFrustrations: trackFrustrations,
            trackLongTask: trackLongTask,
            trackNativeLongTasks: trackNativeLongTasks,
            trackNativeViews: trackNativeViews,
            trackNetworkRequests: trackNetworkRequests,
            trackUserInteractions: trackUserInteractions,
            trackViewsManually: trackViewsManually,
            unityVersion: unityVersion,
            useFirstPartyHosts: useFirstPartyHosts,
            useLocalEncryption: useLocalEncryption,
            useProxy: useProxy,
            useTracing: useTracing
        )

        // Then
        let event = featureScope.eventsWritten(ofType: TelemetryConfigurationEvent.self).first
        XCTAssertEqual(event?.date, 0)
        XCTAssertEqual(event?.version, "sdk-version")
        XCTAssertEqual(event?.service, "dd-sdk-ios")
        XCTAssertEqual(event?.source, .unity)
        XCTAssertEqual(event?.telemetry.configuration.backgroundTasksEnabled, backgroundTasksEnabled)
        XCTAssertEqual(event?.telemetry.configuration.batchProcessingLevel, batchProcessingLevel)
        XCTAssertEqual(event?.telemetry.configuration.batchSize, batchSize)
        XCTAssertEqual(event?.telemetry.configuration.batchUploadFrequency, batchUploadFrequency)
        XCTAssertEqual(event?.telemetry.configuration.dartVersion, dartVersion)
        XCTAssertEqual(event?.telemetry.configuration.mobileVitalsUpdatePeriod, mobileVitalsUpdatePeriod)
        XCTAssertEqual(event?.telemetry.configuration.sessionSampleRate, sessionSampleRate)
        XCTAssertEqual(event?.telemetry.configuration.telemetrySampleRate, telemetrySampleRate)
        XCTAssertEqual(event?.telemetry.configuration.traceSampleRate, traceSampleRate)
        XCTAssertEqual(event?.telemetry.configuration.trackBackgroundEvents, trackBackgroundEvents)
        XCTAssertEqual(event?.telemetry.configuration.trackCrossPlatformLongTasks, trackCrossPlatformLongTasks)
        XCTAssertEqual(event?.telemetry.configuration.trackErrors, trackErrors)
        XCTAssertEqual(event?.telemetry.configuration.trackFlutterPerformance, trackFlutterPerformance)
        XCTAssertEqual(event?.telemetry.configuration.trackFrustrations, trackFrustrations)
        XCTAssertEqual(event?.telemetry.configuration.trackInteractions, trackUserInteractions)
        XCTAssertEqual(event?.telemetry.configuration.trackUserInteractions, trackUserInteractions)
        XCTAssertEqual(event?.telemetry.configuration.trackLongTask, trackLongTask)
        XCTAssertEqual(event?.telemetry.configuration.trackNativeLongTasks, trackNativeLongTasks)
        XCTAssertEqual(event?.telemetry.configuration.trackNativeViews, trackNativeViews)
        XCTAssertEqual(event?.telemetry.configuration.trackNetworkRequests, trackNetworkRequests)
        XCTAssertEqual(event?.telemetry.configuration.trackViewsManually, trackViewsManually)
        XCTAssertEqual(event?.telemetry.configuration.unityVersion, unityVersion)
        XCTAssertEqual(event?.telemetry.configuration.useFirstPartyHosts, useFirstPartyHosts)
        XCTAssertEqual(event?.telemetry.configuration.useLocalEncryption, useLocalEncryption)
        XCTAssertEqual(event?.telemetry.configuration.useProxy, useProxy)
        XCTAssertEqual(event?.telemetry.configuration.useTracing, useTracing)
    }

    // MARK: - Metrics Telemetry Events

    func testSendTelemetryMetric() throws {
        let deviceMock: DeviceInfo = .mockRandom()
        featureScope.contextMock = .mockWith(
            version: "app-version",
            source: "react-native",
            sdkVersion: "sdk-version",
            device: deviceMock
        )

        // Given
        let receiver = TelemetryReceiver.mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(using: .init(timeIntervalSince1970: 0))
        )

        // When
        let randomName: String = .mockRandom()
        let randomAttributes = mockRandomAttributes()
        TelemetryMock(with: receiver).metric(name: randomName, attributes: randomAttributes)

        // Then
        let event = featureScope.eventsWritten(ofType: TelemetryDebugEvent.self).first
        XCTAssertEqual(event?.date, 0)
        XCTAssertEqual(event?.version, "sdk-version")
        XCTAssertEqual(event?.service, "dd-sdk-ios")
        XCTAssertEqual(event?.source, .reactNative)
        XCTAssertEqual(event?.telemetry.message, "[Mobile Metric] \(randomName)")
        randomAttributes.forEach { key, value in
            DDAssertReflectionEqual(event?.telemetry.telemetryInfo[key], value)
        }
        let device = try XCTUnwrap(event?.telemetry.device)
        XCTAssertEqual(device.model, deviceMock.model)
        XCTAssertEqual(device.brand, deviceMock.brand)
        XCTAssertEqual(device.architecture, deviceMock.architecture)
        let os = try XCTUnwrap(event?.telemetry.os)
        XCTAssertEqual(os.version, deviceMock.osVersion)
        XCTAssertEqual(os.name, deviceMock.osName)
        XCTAssertEqual(os.build, deviceMock.osBuildNumber)
    }

    func testSendTelemetryMetricWithRUMContext() throws {
        // Given
        let rumContext: RUMCoreContext = .mockRandom()
        let deviceMock: DeviceInfo = .mockRandom()
        featureScope.contextMock = .mockWith(device: deviceMock)
        featureScope.contextMock.baggages = [RUMFeature.name: FeatureBaggage(rumContext)]
        let receiver = TelemetryReceiver.mockWith(featureScope: featureScope)

        // When
        TelemetryMock(with: receiver).metric(name: .mockRandom(), attributes: mockRandomAttributes())

        // Then
        let event = featureScope.eventsWritten(ofType: TelemetryDebugEvent.self).first
        XCTAssertEqual(event?.application?.id, rumContext.applicationID)
        XCTAssertEqual(event?.session?.id, rumContext.sessionID)
        XCTAssertEqual(event?.view?.id, rumContext.viewID)
        XCTAssertEqual(event?.action?.id, rumContext.userActionID)
        let device = try XCTUnwrap(event?.telemetry.device)
        XCTAssertEqual(device.model, deviceMock.model)
        XCTAssertEqual(device.brand, deviceMock.brand)
        XCTAssertEqual(device.architecture, deviceMock.architecture)
        let os = try XCTUnwrap(event?.telemetry.os)
        XCTAssertEqual(os.version, deviceMock.osVersion)
        XCTAssertEqual(os.name, deviceMock.osName)
        XCTAssertEqual(os.build, deviceMock.osBuildNumber)
    }

    func testMethodCallTelemetryPropagetsAllData() throws {
        // Given
        let deviceMock: DeviceInfo = .mockRandom()
        featureScope.contextMock = .mockWith(device: deviceMock)
        let receiver = TelemetryReceiver.mockWith(featureScope: featureScope)
        let telemetry = TelemetryMock(with: receiver)

        // When
        let operationName = String.mockRandom()
        let callerClass = String.mockRandom()
        let isSuccessful = Bool.random()
        let trace = telemetry.startMethodCalled(
            operationName: operationName,
            callerClass: callerClass,
            samplingRate: 100
        )
        telemetry.stopMethodCalled(trace, isSuccessful: isSuccessful)

        // Then
        let event = featureScope.eventsWritten(ofType: TelemetryDebugEvent.self).first
        XCTAssertEqual(event?.telemetry.message, "[Mobile Metric] Method Called")
        XCTAssertEqual(try XCTUnwrap(event?.telemetry.telemetryInfo[SDKMetricFields.typeKey] as? String), MethodCalledMetric.typeValue)
        XCTAssertEqual(try XCTUnwrap(event?.telemetry.telemetryInfo[MethodCalledMetric.operationName] as? String), operationName)
        XCTAssertEqual(try XCTUnwrap(event?.telemetry.telemetryInfo[MethodCalledMetric.callerClass] as? String), callerClass)
        XCTAssertEqual(try XCTUnwrap(event?.telemetry.telemetryInfo[MethodCalledMetric.isSuccessful] as? Bool), isSuccessful)
        XCTAssertGreaterThan(try XCTUnwrap(event?.telemetry.telemetryInfo[MethodCalledMetric.executionTime] as? Int64), 0)
        let device = try XCTUnwrap(event?.telemetry.device)
        XCTAssertEqual(device.model, deviceMock.model)
        XCTAssertEqual(device.brand, deviceMock.brand)
        XCTAssertEqual(device.architecture, deviceMock.architecture)
        let os = try XCTUnwrap(event?.telemetry.os)
        XCTAssertEqual(os.version, deviceMock.osVersion)
        XCTAssertEqual(os.name, deviceMock.osName)
        XCTAssertEqual(os.build, deviceMock.osBuildNumber)
    }

    func testMethodCallTelemetryDroppedWhenSampledOut() {
        // Given
        let receiver = TelemetryReceiver.mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(using: .init(timeIntervalSince1970: 0))
        )
        let telemetry = TelemetryMock(with: receiver)

        // When
        let trace = telemetry.startMethodCalled(
            operationName: .mockAny(),
            callerClass: .mockAny(),
            samplingRate: 0
        )
        telemetry.stopMethodCalled(trace, isSuccessful: true)

        // Then
        let event = featureScope.eventsWritten(ofType: TelemetryDebugEvent.self).first
        XCTAssertNil(event)
    }
}
