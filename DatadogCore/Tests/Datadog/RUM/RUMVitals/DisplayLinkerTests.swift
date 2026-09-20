/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS) && !os(macOS)

import XCTest
import QuartzCore
import TestUtilities
import DatadogInternal
@testable import DatadogRUM
@testable import DatadogCore

final class DisplayLinkerTests: XCTestCase {
    @MainActor
    func testGivenActiveDisplayLinker_whenOwnerIsReleased_itReleasesNativeTargetAndReader() {
        let center = NotificationCenter()
        defer { center.post(name: DDApplication.willResignActiveNotification, object: nil) }
        weak var observedLinker: DisplayLinker?
        weak var observedReader: ViewHitchesMock?

        autoreleasepool {
            let linker = DisplayLinker(notificationCenter: center)
            let reader = ViewHitchesMock()
            linker.register(reader)
            observedLinker = linker
            observedReader = reader
            XCTAssertTrue(linker.isActive)
            XCTAssertNotNil(observedLinker)
            XCTAssertNotNil(observedReader)
        }

        let released = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in observedLinker == nil && observedReader == nil },
            object: nil
        )
        _ = XCTWaiter.wait(for: [released], timeout: 2)
        XCTAssertNil(observedLinker, "Dropping the active owner must release its native display target")
        XCTAssertNil(observedReader, "An unowned display target must not retain its readers")
    }

    @MainActor
    func testGivenInactiveDisplayLinker_whenOwnerIsReleased_itReleasesNativeTargetAndReader() {
        let center = NotificationCenter()
        defer { center.post(name: DDApplication.willResignActiveNotification, object: nil) }
        weak var observedLinker: DisplayLinker?
        weak var observedReader: ViewHitchesMock?

        autoreleasepool {
            let linker = DisplayLinker(notificationCenter: center)
            let reader = ViewHitchesMock()
            linker.register(reader)
            observedLinker = linker
            observedReader = reader
            XCTAssertTrue(linker.isActive)
            XCTAssertNotNil(observedLinker)
            XCTAssertNotNil(observedReader)
            center.post(name: DDApplication.willResignActiveNotification, object: nil)
            XCTAssertFalse(linker.isActive)
        }

        let released = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in observedLinker == nil && observedReader == nil },
            object: nil
        )
        _ = XCTWaiter.wait(for: [released], timeout: 2)
        XCTAssertNil(observedLinker)
        XCTAssertNil(observedReader)
    }

    @MainActor
    func testGivenRUMFeature_whenConfigurationDeliveryFinishesAndCoreIsTornDown_itReleasesNativeDisplayTarget() {
        let centers = NotificationCenterProvider.makeTestProvider()
        defer {
            centers.applicationCenter.post(name: DDApplication.willResignActiveNotification, object: nil)
            XCTAssertNoThrow(try temporaryCoreDirectory.delete())
        }
        weak var observedTarget: AnyObject?
        weak var observedFeature: RUMFeature?
        weak var observedCore: DatadogCoreProxy?
        weak var observedMonitor: Monitor?
        weak var observedApplicationScope: RUMApplicationScope?
        weak var observedLinker: DisplayLinker?
        weak var observedFirstFrameReader: FirstFrameReader?
        weak var observedSDKCore: DatadogCore?
        weak var observedMessageBus: MessageBus?
        let configurationDelivered = expectation(description: "Pending configuration was delivered before teardown")

        autoreleasepool {
            let context = DatadogContext.mockAny()
            let sdkCore = DatadogCore(
                directory: temporaryCoreDirectory,
                dateProvider: SystemDateProvider(),
                initialConsent: context.trackingConsent,
                performance: .mockAny(),
                httpClient: HTTPClientMock(),
                encryption: nil,
                contextProvider: DatadogContextProvider(context: context),
                applicationVersion: context.version,
                maxBatchesPerUpload: .mockRandom(min: 1, max: 100),
                backgroundTasksEnabled: .mockAny()
            )
            let core = DatadogCoreProxy(core: sdkCore)
            observedSDKCore = sdkCore
            observedMessageBus = sdkCore.bus
            sdkCore.bus.connect(
                FeatureMessageReceiverMock { message in
                    guard case .telemetry(.configuration) = message else {
                        return
                    }
                    configurationDelivered.fulfill()
                },
                forKey: "display-link-lifetime-configuration"
            )
            defer { XCTAssertNoThrow(try core.flushAndTearDown()) }
            observedCore = core
            var configuration = RUM.Configuration(applicationID: "00000000-0000-0000-0000-000000000211")
            configuration.notificationCenterProvider = centers
            configuration.longTaskThreshold = nil
            configuration.appHangThreshold = nil
            configuration.trackWatchdogTerminations = false
            configuration.vitalsUpdateFrequency = nil
            configuration.collectAccessibility = false
            configuration.telemetrySampleRate = 0
            configuration.frameInfoProviderFactory = { target, selector in
                observedTarget = target as AnyObject
                return CADisplayLink(target: target, selector: selector)
            }
            RUM.enable(with: configuration, in: core)
            observedFeature = core.feature(named: RUMFeature.name, type: RUMFeature.self)
            observedMonitor = observedFeature?.monitor
            observedApplicationScope = observedMonitor?.applicationScope
            observedLinker = observedApplicationScope?.dependencies.renderLoopObserver as? DisplayLinker
            observedFirstFrameReader = observedApplicationScope?.dependencies.firstFrameReader as? FirstFrameReader
            XCTAssertNotNil(observedMonitor)
            XCTAssertNotNil(observedApplicationScope)
            XCTAssertNotNil(observedLinker)
            XCTAssertNotNil(observedFirstFrameReader)
            XCTAssertNotNil(observedSDKCore)
            XCTAssertNotNil(observedMessageBus)
            XCTAssertNotNil(observedCore)
            XCTAssertNotNil(observedFeature)
            XCTAssertNotNil(observedTarget)
            // The message bus owns its receivers until its scheduled configuration task finishes.
            // Witness that existing owner before measuring the final-owner teardown boundary.
            XCTAssertEqual(XCTWaiter.wait(for: [configurationDelivered], timeout: 7), .completed)
        }

        let released = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in observedTarget == nil && observedFeature == nil && observedCore == nil },
            object: nil
        )
        _ = XCTWaiter.wait(for: [released], timeout: 2)
        XCTAssertNil(observedCore)
        XCTAssertNil(observedSDKCore, "The actual SDK core must release after teardown")
        XCTAssertNil(observedMessageBus, "The message bus must release after its pending configuration is delivered")
        XCTAssertNil(observedFeature)
        XCTAssertNil(observedMonitor, "Monitor must release after feature/core teardown")
        XCTAssertNil(observedApplicationScope, "Application scope must release after feature/core teardown")
        XCTAssertNil(observedLinker, "DisplayLinker must release after feature/core teardown")
        XCTAssertNil(observedFirstFrameReader, "First-frame reader must release after feature/core teardown")
        XCTAssertNil(observedTarget, "Core teardown must release the RUM native display target without an app-state notification")
    }

    @MainActor
    func testGivenReleasedDisplayLinker_whenProviderDeliversFrame_itDoesNotRetainOrNotifyReader() {
        let center = NotificationCenter()
        defer { center.post(name: DDApplication.willResignActiveNotification, object: nil) }
        var provider: FrameInfoProviderMock?
        weak var observedLinker: DisplayLinker?
        let reader = ViewHitchesMock()

        autoreleasepool {
            let linker = DisplayLinker(notificationCenter: center) { target, selector in
                let frameProvider = FrameInfoProviderMock(target: target, selector: selector)
                provider = frameProvider
                return frameProvider
            }
            linker.register(reader)
            observedLinker = linker
            XCTAssertNotNil(observedLinker)
            XCTAssertNotNil(provider)
            provider?.triggerCallback(interval: 1)
            XCTAssertTrue(reader.isActive)
        }

        XCTAssertNil(observedLinker)
        XCTAssertFalse(reader.isActive)
        provider?.triggerCallback(interval: 2)
        XCTAssertFalse(reader.isActive, "A callback after owner release must not revive a stopped reader")
    }

    private let mockNotificationCenter = NotificationCenter()

    func testWhenMainThreadOverheadGoesUp_itMeasuresLowerRefreshRate() throws {
        let displayLinker = DisplayLinker(notificationCenter: mockNotificationCenter)
        let reader = VitalRefreshRateReader()
        displayLinker.register(reader)
        let targetSamplesCount = 30

        /// Runs given work on the main thread until `condition` is met, then calls `completion`.
        func run(mainThreadWork: @escaping () -> Void, until condition: @escaping () -> Bool, completion: @escaping () -> Void) {
            if !condition() {
                mainThreadWork()
                DispatchQueue.main.async { // schedule to next runloop
                    run(mainThreadWork: mainThreadWork, until: condition, completion: completion)
                }
            } else {
                completion()
            }
        }

        /// Records `targetSamplesCount` samples into `measure` by running given work on the main thread.
        func record(_ measure: VitalPublisher, mainThreadWork: @escaping () -> Void) {
            let completion = expectation(description: "Complete measurement")
            reader.register(measure)

            run(
                mainThreadWork: mainThreadWork,
                until: { measure.currentValue.sampleCount >= targetSamplesCount },
                completion: {
                    reader.unregister(measure)
                    completion.fulfill()
                }
            )

            let result = XCTWaiter().wait(for: [completion], timeout: 10)

            switch result {
            case .completed:
                break // all good
            case .timedOut:
                XCTFail("VitalRefreshRateReader exceededed timeout with \(measure.currentValue.sampleCount)/\(targetSamplesCount) recorded samples")
            default:
                XCTFail("XCTWaiter unexpected failure: \(result)")
            }
        }

        // Given
        let lowOverhead = { /* no-op */ } // no overhead in succeeding runloop runs
        let lowOverheadMeasure = VitalPublisher(initialValue: VitalInfo())

        var highOverheadRunCount = 0
        let highOverhead = { highOverheadRunCount += 1; Thread.sleep(forTimeInterval: 0.02) } // 0.02 overhead in succeeding runloop runs
        let highOverheadMeasure = VitalPublisher(initialValue: VitalInfo())

        // When
        record(lowOverheadMeasure, mainThreadWork: lowOverhead)
        record(highOverheadMeasure, mainThreadWork: highOverhead)

        // Then
        let expectedHighFPS = try XCTUnwrap(lowOverheadMeasure.currentValue.meanValue)
        let expectedLowFPS = try XCTUnwrap(highOverheadMeasure.currentValue.meanValue)
        XCTAssertGreaterThan(expectedHighFPS, expectedLowFPS, "It must measure higher FPS for lower main thread overhead (high overhead run count: \(highOverheadRunCount))")
    }

    func testAppStateHandlingForRefreshRateReader() {
        let displayLinker = DisplayLinker(notificationCenter: mockNotificationCenter)
        let reader = VitalRefreshRateReader()
        displayLinker.register(reader)
        let registrar = VitalPublisher(initialValue: VitalInfo())

        mockNotificationCenter.post(name: DDApplication.didBecomeActiveNotification, object: nil)
        mockNotificationCenter.post(name: DDApplication.willResignActiveNotification, object: nil)
        reader.register(registrar)

        XCTAssertFalse(reader.isActive)
        XCTAssertEqual(registrar.currentValue.sampleCount, 0)

        mockNotificationCenter.post(name: DDApplication.didBecomeActiveNotification, object: nil)

        wait(during: 0.1) {
            XCTAssertTrue(reader.isActive)
            XCTAssertGreaterThan(registrar.currentValue.sampleCount, 0)
        }
    }

    func testAppStateHandlingForViewHitchesReader() {
        let displayLinker = DisplayLinker(notificationCenter: mockNotificationCenter)
        let reader = ViewHitchesReader()
        displayLinker.register(reader)

        mockNotificationCenter.post(name: DDApplication.didBecomeActiveNotification, object: nil)
        wait(during: 0.1) {
            XCTAssertTrue(displayLinker.isActive)
            XCTAssertTrue(reader.isActive)
        }

        mockNotificationCenter.post(name: DDApplication.willResignActiveNotification, object: nil)
        wait(during: 0.1) {
            XCTAssertFalse(displayLinker.isActive)
            XCTAssertFalse(reader.isActive)
        }

        mockNotificationCenter.post(name: DDApplication.didBecomeActiveNotification, object: nil)
        wait(during: 0.1) {
            XCTAssertTrue(displayLinker.isActive)
            XCTAssertTrue(reader.isActive)
        }
    }

    func testAppStateHandlingWithSeveralReaders() {
        let displayLinker = DisplayLinker(notificationCenter: mockNotificationCenter)
        let refreshRateReader = VitalRefreshRateReader()
        let viewHitchesReader = ViewHitchesReader()

        displayLinker.register(refreshRateReader)
        displayLinker.register(viewHitchesReader)

        wait(during: 0.1) {
            XCTAssertTrue(refreshRateReader.isActive)
            XCTAssertTrue(viewHitchesReader.isActive)
        }

        mockNotificationCenter.post(name: DDApplication.willResignActiveNotification, object: nil)

        wait(during: 0.1) {
            XCTAssertFalse(refreshRateReader.isActive)
            XCTAssertFalse(viewHitchesReader.isActive)
        }

        mockNotificationCenter.post(name: DDApplication.didBecomeActiveNotification, object: nil)

        wait(during: 0.1) {
            XCTAssertTrue(refreshRateReader.isActive)
            XCTAssertTrue(viewHitchesReader.isActive)
        }
    }

    func testDisplayLinkerRegistrationWithSeveralReaders() {
        let displayLinker = DisplayLinker(notificationCenter: mockNotificationCenter)
        let refreshRateReader = VitalRefreshRateReader()
        let viewHitchesReader = ViewHitchesReader()
        let mockReader = ViewHitchesMock()

        XCTAssertTrue(displayLinker.isActive)
        XCTAssertFalse(refreshRateReader.isActive)
        XCTAssertFalse(viewHitchesReader.isActive)
        XCTAssertFalse(mockReader.isActive)

        displayLinker.register(refreshRateReader)
        displayLinker.register(viewHitchesReader)
        displayLinker.register(mockReader)

        wait(during: 0.1) {
            XCTAssertTrue(refreshRateReader.isActive)
            XCTAssertTrue(viewHitchesReader.isActive)
            XCTAssertTrue(mockReader.isActive)
        }

        displayLinker.unregister(refreshRateReader)
        displayLinker.unregister(viewHitchesReader)
        displayLinker.unregister(mockReader)

        wait(during: 0.1) {
            XCTAssertFalse(refreshRateReader.isActive)
            XCTAssertFalse(viewHitchesReader.isActive)
            XCTAssertFalse(mockReader.isActive)
        }
    }
}

#endif
