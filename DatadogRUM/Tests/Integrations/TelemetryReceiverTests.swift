/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogRUM

class TelemetryReceiverTests: XCTestCase {
    private var core: PassthroughCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = PassthroughCoreMock(
            context: .mockWith(
                version: .mockRandom(),
                source: .mockAnySource(),
                sdkVersion: .mockRandom()
            )
        )
    }

    override func tearDown() {
        core = nil
        super.tearDown()
    }

    // MARK: - Sending Telemetry events

    func testSendTelemetryDebug() {
        // Given
        core.messageReceiver = TelemetryReceiver.mockWith(
            dateProvider: RelativeDateProvider(
                using: .init(timeIntervalSince1970: 0)
            )
        )

        // When
        core.telemetry.debug("Hello world!", attributes: ["foo": 42])

        // Then
        let event = core.events(ofType: TelemetryDebugEvent.self).first
        XCTAssertEqual(event?.date, 0)
        XCTAssertEqual(event?.version, core.context.sdkVersion)
        XCTAssertEqual(event?.service, "dd-sdk-ios")
        XCTAssertEqual(event?.source.rawValue, core.context.source)
        XCTAssertEqual(event?.telemetry.message, "Hello world!")
        XCTAssertEqual(event?.telemetry.telemetryInfo as? [String: Int], ["foo": 42])
    }

    func testSendTelemetryError() {
        // Given
        core.messageReceiver = TelemetryReceiver.mockWith(
            dateProvider: RelativeDateProvider(
                using: .init(timeIntervalSince1970: 0)
            )
        )

        // When
        core.telemetry.error("Oops", kind: "OutOfMemory", stack: "a\nhay\nneedle\nstack")

        // Then
        let event = core.events(ofType: TelemetryErrorEvent.self).first
        XCTAssertEqual(event?.date, 0)
        XCTAssertEqual(event?.version, core.context.sdkVersion)
        XCTAssertEqual(event?.service, "dd-sdk-ios")
        XCTAssertEqual(event?.source.rawValue, core.context.source)
        XCTAssertEqual(event?.telemetry.message, "Oops")
        XCTAssertEqual(event?.telemetry.error?.kind, "OutOfMemory")
        XCTAssertEqual(event?.telemetry.error?.stack, "a\nhay\nneedle\nstack")
    }

    func testSendTelemetryDebug_withRUMContext() {
        // Given
        core.messageReceiver = TelemetryReceiver.mockAny()
        let applicationId: String = .mockRandom()
        let sessionId: String = .mockRandom()
        let viewId: String = .mockRandom()
        let actionId: String = .mockRandom()

        core.set(
            baggage: RUMCoreContext(
                applicationID: applicationId,
                sessionID: sessionId,
                viewID: viewId,
                userActionID: actionId,
                viewServerTimeOffset: .mockRandom()
            ),
            forKey: "rum"
        )

        // When
        core.telemetry.debug("telemetry debug", attributes: ["foo": 42])

        // Then
        let event = core.events(ofType: TelemetryDebugEvent.self).first
        XCTAssertEqual(event?.telemetry.message, "telemetry debug")
        XCTAssertEqual(event?.application?.id, applicationId)
        XCTAssertEqual(event?.session?.id, sessionId)
        XCTAssertEqual(event?.view?.id, viewId)
        XCTAssertEqual(event?.action?.id, actionId)
        XCTAssertEqual(event?.telemetry.telemetryInfo as? [String: Int], ["foo": 42])
    }

    func testSendTelemetryError_withRUMContext() throws {
        // Given
        core.messageReceiver = TelemetryReceiver.mockAny()
        let applicationId: String = .mockRandom()
        let sessionId: String = .mockRandom()
        let viewId: String = .mockRandom()
        let actionId: String = .mockRandom()

        core.set(
            baggage: RUMCoreContext(
                applicationID: applicationId,
                sessionID: sessionId,
                viewID: viewId,
                userActionID: actionId,
                viewServerTimeOffset: .mockRandom()
            ),
            forKey: "rum"
        )

        // When
        core.telemetry.error("telemetry error")

        // Then
        let event = core.events(ofType: TelemetryErrorEvent.self).first
        XCTAssertEqual(event?.telemetry.message, "telemetry error")
        XCTAssertEqual(event?.application?.id, applicationId)
        XCTAssertEqual(event?.session?.id, sessionId)
        XCTAssertEqual(event?.view?.id, viewId)
        XCTAssertEqual(event?.action?.id, actionId)
    }

    func testSendTelemetry_discardDuplicates() throws {
        // Given
        core.messageReceiver = TelemetryReceiver.mockAny()

        // When
        core.telemetry.debug(id: "0", message: "telemetry debug 0")
        core.telemetry.error(id: "0", message: "telemetry debug 1", kind: nil, stack: nil)
        core.telemetry.debug(id: "0", message: "telemetry debug 2")
        core.telemetry.debug(id: "1", message: "telemetry debug 3")

        for _ in 0...10 {
            // telemetry id is composed of the file, line number, and message
            core.telemetry.debug("telemetry debug 4")
        }

        for index in 5...10 {
            // telemetry id is composed of the file, line number, and message
            core.telemetry.debug("telemetry debug \(index)")
        }

        core.telemetry.debug("telemetry debug 11")

        // Then
        let events = core.events(ofType: TelemetryDebugEvent.self)
        XCTAssertEqual(events.count, 10)
        XCTAssertTrue(core.events(ofType: TelemetryErrorEvent.self).isEmpty)
        XCTAssertEqual(events[0].telemetry.message, "telemetry debug 0")
        XCTAssertEqual(events[1].telemetry.message, "telemetry debug 3")
        XCTAssertEqual(events[2].telemetry.message, "telemetry debug 4")
        XCTAssertEqual(events[3].telemetry.message, "telemetry debug 5")
        XCTAssertEqual(events.last?.telemetry.message, "telemetry debug 11")
    }

    func testSendTelemetry_toSessionLimit() throws {
        // Given
        core.messageReceiver = TelemetryReceiver.mockWith(sampler: .mockKeepAll())

        // When
        // sends 101 telemetry events
        for index in 0..<(TelemetryReceiver.maxEventsPerSessions * 2) {
            // swiftlint:disable opening_brace
            oneOf([
                { self.core.telemetry.debug(id: "\(index)", message: .mockAny()) },
                { self.core.telemetry.error(id: "\(index)", message: .mockAny(), kind: .mockAny(), stack: .mockAny()) },
                { self.core.telemetry.metric(name: .mockAny(), attributes: [:]) }
            ])
            // swiftlint:enable opening_brace
        }

        // Then
        let debugEvents = core.events(ofType: TelemetryDebugEvent.self)
        let errorEvents = core.events(ofType: TelemetryErrorEvent.self)
        XCTAssertEqual(debugEvents.count + errorEvents.count, 100)
    }

    func testSampledTelemetry_rejectAll() throws {
        // Given
        core.messageReceiver = TelemetryReceiver.mockWith(sampler: .mockRejectAll())

        // When
        // sends 10 telemetry events
        for index in 0..<10 {
            // swiftlint:disable opening_brace
            oneOf([
                { self.core.telemetry.debug(id: "debug-\(index)", message: .mockAny()) },
                { self.core.telemetry.error(id: "error-\(index)", message: .mockAny(), kind: .mockAny(), stack: .mockAny()) },
                { self.core.telemetry.configuration(batchSize: .mockAny()) },
                { self.core.telemetry.metric(name: .mockAny(), attributes: [:]) }
            ])
            // swiftlint:enable opening_brace
        }

        // Then
        let events = core.events(ofType: TelemetryDebugEvent.self)
        XCTAssertEqual(events.count, 0)
    }

    func testSampledTelemetry_rejectAllConfiguration() throws {
        // Given
        core.messageReceiver = TelemetryReceiver.mockWith(
            sampler: .mockKeepAll(),
            configurationExtraSampler: .mockRejectAll()
        )

        // When
        for index in 0..<10 {
            core.telemetry.debug(id: "debug-\(index)", message: .mockAny())
            core.telemetry.error(id: "error-\(index)", message: .mockAny(), kind: .mockAny(), stack: .mockAny())
            core.telemetry.metric(name: .mockAny(), attributes: [:])
            core.telemetry.configuration(batchSize: .mockAny())
        }

        // Then
        XCTAssertEqual(core.events(ofType: TelemetryDebugEvent.self).count, 20, "It should keep 10 debug events and 10 metrics")
        XCTAssertEqual(core.events(ofType: TelemetryErrorEvent.self).count, 10, "It should keep 10 error events")
        XCTAssertTrue(core.events(ofType: TelemetryConfigurationEvent.self).isEmpty, "It should reject all configuration events")
    }

    func testSampledTelemetry_rejectAllMetrics() throws {
        // Given
        core.messageReceiver = TelemetryReceiver.mockWith(
            sampler: .mockKeepAll(),
            metricsExtraSampler: .mockRejectAll()
        )

        // When
        for index in 0..<10 {
            core.telemetry.debug(id: "debug-\(index)", message: .mockAny())
            core.telemetry.error(id: "error-\(index)", message: .mockAny(), kind: .mockAny(), stack: .mockAny())
            core.telemetry.metric(name: .mockAny(), attributes: [:])
            core.telemetry.configuration(batchSize: .mockAny())
        }

        // Then
        XCTAssertEqual(core.events(ofType: TelemetryDebugEvent.self).count, 10, "It should keep 10 debug events but no metrics")
        XCTAssertEqual(core.events(ofType: TelemetryErrorEvent.self).count, 10, "It should keep 10 error events")
        XCTAssertEqual(core.events(ofType: TelemetryConfigurationEvent.self).count, 1, "It should keep 1 configuration event")
    }

    func testSendTelemetry_resetAfterSessionExpire() throws {
        // Given
        core.messageReceiver = TelemetryReceiver.mockAny()
        let applicationId: String = .mockRandom()

        core.set(baggage: [
            RUMContextAttributes.IDs.applicationID: applicationId,
            RUMContextAttributes.IDs.sessionID: String.mockRandom()
        ], forKey: "rum")

        // When
        core.telemetry.debug(id: "0", message: "telemetry debug")

        core.set(baggage: [
            RUMContextAttributes.IDs.applicationID: applicationId,
            RUMContextAttributes.IDs.sessionID: String.mockRandom()
        ], forKey: "rum")

        core.telemetry.debug(id: "0", message: "telemetry debug")

        // Then
        let events = core.events(ofType: TelemetryDebugEvent.self)
        XCTAssertEqual(events.count, 2)
    }

    // MARK: - Configuration Telemetry Events

    func testSendTelemetryConfiguration() {
        // Given
        core.messageReceiver = TelemetryReceiver.mockWith(
            dateProvider: RelativeDateProvider(
                using: .init(timeIntervalSince1970: 0)
            )
        )

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
        let trackInteractions: Bool? = .mockRandom()
        let trackLongTask: Bool? = .mockRandom()
        let trackNativeLongTasks: Bool? = .mockRandom()
        let trackNativeViews: Bool? = .mockRandom()
        let trackNetworkRequests: Bool? = .mockRandom()
        let trackViewsManually: Bool? = .mockRandom()
        let useFirstPartyHosts: Bool? = .mockRandom()
        let useLocalEncryption: Bool? = .mockRandom()
        let useProxy: Bool? = .mockRandom()
        let useTracing: Bool? = .mockRandom()

        // When
        core.telemetry.configuration(
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
            trackInteractions: trackInteractions,
            trackLongTask: trackLongTask,
            trackNativeLongTasks: trackNativeLongTasks,
            trackNativeViews: trackNativeViews,
            trackNetworkRequests: trackNetworkRequests,
            trackViewsManually: trackViewsManually,
            useFirstPartyHosts: useFirstPartyHosts,
            useLocalEncryption: useLocalEncryption,
            useProxy: useProxy,
            useTracing: useTracing
        )

        // Then
        let event = core.events(ofType: TelemetryConfigurationEvent.self).first
        XCTAssertEqual(event?.date, 0)
        XCTAssertEqual(event?.version, core.context.sdkVersion)
        XCTAssertEqual(event?.service, "dd-sdk-ios")
        XCTAssertEqual(event?.source.rawValue, core.context.source)
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
        XCTAssertEqual(event?.telemetry.configuration.trackInteractions, trackInteractions)
        XCTAssertEqual(event?.telemetry.configuration.trackLongTask, trackLongTask)
        XCTAssertEqual(event?.telemetry.configuration.trackNativeLongTasks, trackNativeLongTasks)
        XCTAssertEqual(event?.telemetry.configuration.trackNativeViews, trackNativeViews)
        XCTAssertEqual(event?.telemetry.configuration.trackNetworkRequests, trackNetworkRequests)
        XCTAssertEqual(event?.telemetry.configuration.trackViewsManually, trackViewsManually)
        XCTAssertEqual(event?.telemetry.configuration.useFirstPartyHosts, useFirstPartyHosts)
        XCTAssertEqual(event?.telemetry.configuration.useLocalEncryption, useLocalEncryption)
        XCTAssertEqual(event?.telemetry.configuration.useProxy, useProxy)
        XCTAssertEqual(event?.telemetry.configuration.useTracing, useTracing)
    }

    // MARK: - Metrics Telemetry Events

    func testSendTelemetryMetric() {
        // Given
        core.messageReceiver = TelemetryReceiver.mockWith(
            dateProvider: RelativeDateProvider(
                using: .init(timeIntervalSince1970: 0)
            )
        )

        // When
        let randomName: String = .mockRandom()
        let randomAttributes = mockRandomAttributes()
        core.telemetry.metric(name: randomName, attributes: randomAttributes)

        // Then
        let event = core.events(ofType: TelemetryDebugEvent.self).first
        XCTAssertEqual(event?.date, 0)
        XCTAssertEqual(event?.version, core.context.sdkVersion)
        XCTAssertEqual(event?.service, "dd-sdk-ios")
        XCTAssertEqual(event?.source.rawValue, core.context.source)
        XCTAssertEqual(event?.telemetry.message, "[Mobile Metric] \(randomName)")
        DDAssertReflectionEqual(event?.telemetry.telemetryInfo, randomAttributes)
    }

    func testSendTelemetryMetricWithRUMContext() {
        // Given
        core.messageReceiver = TelemetryReceiver.mockWith(
            dateProvider: RelativeDateProvider(
                using: .init(timeIntervalSince1970: 0)
            )
        )

        let applicationId: String = .mockRandom()
        let sessionId: String = .mockRandom()
        let viewId: String = .mockRandom()
        let actionId: String = .mockRandom()

        core.set(
            baggage: RUMCoreContext(
                applicationID: applicationId,
                sessionID: sessionId,
                viewID: viewId,
                userActionID: actionId,
                viewServerTimeOffset: .mockRandom()
            ),
            forKey: "rum"
        )

        // When
        core.telemetry.metric(name: .mockRandom(), attributes: mockRandomAttributes())

        // Then
        let event = core.events(ofType: TelemetryDebugEvent.self).first
        XCTAssertEqual(event?.application?.id, applicationId)
        XCTAssertEqual(event?.session?.id, sessionId)
        XCTAssertEqual(event?.view?.id, viewId)
        XCTAssertEqual(event?.action?.id, actionId)
    }

    func testMethodCallTelemetryPropagetsAllData() throws {
        // Given
        core.messageReceiver = TelemetryReceiver.mockWith(
            dateProvider: RelativeDateProvider(
                using: .init(timeIntervalSince1970: 0)
            )
        )

        let operationName = String.mockRandom()
        let callerClass = String.mockRandom()
        let isSuccessful = Bool.random()
        let trace = core.telemetry.startMethodCalled(
            operationName: operationName,
            callerClass: callerClass,
            samplingRate: 100
        )
        core.telemetry.stopMethodCalled(trace, isSuccessful: isSuccessful)

        let event = core.events(ofType: TelemetryDebugEvent.self).first
        XCTAssertEqual(event?.telemetry.message, "[Mobile Metric] Method Called")
        XCTAssertEqual(try XCTUnwrap(event?.telemetry.telemetryInfo[BasicMetric.typeKey] as? String), MethodCalledMetric.typeValue)
        XCTAssertEqual(try XCTUnwrap(event?.telemetry.telemetryInfo[MethodCalledMetric.operationName] as? String), operationName)
        XCTAssertEqual(try XCTUnwrap(event?.telemetry.telemetryInfo[MethodCalledMetric.callerClass] as? String), callerClass)
        XCTAssertEqual(try XCTUnwrap(event?.telemetry.telemetryInfo[MethodCalledMetric.isSuccessful] as? Bool), isSuccessful)
        XCTAssertGreaterThan(try XCTUnwrap(event?.telemetry.telemetryInfo[MethodCalledMetric.executionTime] as? Int64), 0)
        let device = try XCTUnwrap(event?.telemetry.telemetryInfo[MethodCalledMetric.Device.key] as? [String: String])
        XCTAssertTrue(device[MethodCalledMetric.Device.model]?.isEmpty == false)
        XCTAssertTrue(device[MethodCalledMetric.Device.brand]?.isEmpty == false)
        XCTAssertTrue(device[MethodCalledMetric.Device.architecture]?.isEmpty == false)
        let os = try XCTUnwrap(event?.telemetry.telemetryInfo[MethodCalledMetric.OS.key] as? [String: String])
        XCTAssertTrue(os[MethodCalledMetric.OS.version]?.isEmpty == false)
        XCTAssertTrue(os[MethodCalledMetric.OS.build]?.isEmpty == false)
        XCTAssertTrue(os[MethodCalledMetric.OS.name]?.isEmpty == false)
    }

    func testMethodCallTelemetryDroppedWhenSampledOut() {
        // Given
        core.messageReceiver = TelemetryReceiver.mockWith(
            dateProvider: RelativeDateProvider(
                using: .init(timeIntervalSince1970: 0)
            )
        )

        let trace = core.telemetry.startMethodCalled(
            operationName: .mockAny(),
            callerClass: .mockAny(),
            samplingRate: 0
        )
        core.telemetry.stopMethodCalled(trace, isSuccessful: true)

        let event = core.events(ofType: TelemetryDebugEvent.self).first
        XCTAssertNil(event)
    }
}
