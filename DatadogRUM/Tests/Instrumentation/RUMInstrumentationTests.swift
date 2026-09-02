/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import XCTest
import TestUtilities
@testable import DatadogInternal
@testable import DatadogRUM

@MainActor
class RUMInstrumentationTests: XCTestCase {
    private var config = RUM.Configuration(applicationID: .mockAny())

    #if os(macOS)
    private func makePredicates(
        rumViewsPredicate: DDKitRUMViewsPredicate? = nil,
        rumActionsPredicate: DDKitRUMActionsPredicate? = nil,
        swiftUIRUMViewsPredicate: SwiftUIRUMViewsPredicate? = nil
    ) -> RUMInstrumentation.Predicates {
        return .init(
            rumViewsPredicate: rumViewsPredicate,
            rumActionsPredicate: rumActionsPredicate,
            swiftUIRUMViewsPredicate: swiftUIRUMViewsPredicate
        )
    }
    #else
    private func makePredicates(
        rumViewsPredicate: DDKitRUMViewsPredicate? = nil,
        rumActionsPredicate: DDKitRUMActionsPredicate? = nil,
        swiftUIRUMViewsPredicate: SwiftUIRUMViewsPredicate? = nil,
        swiftUIRUMActionsPredicate: SwiftUIRUMActionsPredicate? = nil
    ) -> RUMInstrumentation.Predicates {
        return .init(
            rumViewsPredicate: rumViewsPredicate,
            rumActionsPredicate: rumActionsPredicate,
            swiftUIRUMViewsPredicate: swiftUIRUMViewsPredicate,
            swiftUIRUMActionsPredicate: swiftUIRUMActionsPredicate
        )
    }
    #endif

    #if !os(macOS)
    func testWhenOnlyUIKitViewsPredicateIsConfigured_itInstrumentsUIViewController() throws {
        // When
        let instrumentation = RUMInstrumentation(
            featureScope: NOPFeatureScope(),
            predicates: makePredicates(rumViewsPredicate: UIKitRUMViewsPredicateMock()),
            longTaskThreshold: nil,
            appHangThreshold: .mockAny(),
            mainQueue: .main,
            dateProvider: SystemDateProvider(),
            backtraceReporter: BacktraceReporterMock(),
            fatalErrorContext: FatalErrorContextNotifierMock(),
            processID: .mockAny(),
            notificationCenter: .default,
            bundleType: .iOSApp,
            watchdogTermination: .mockRandom(),
            memoryWarningMonitor: .mockRandom(),
            uuidGenerator: RUMUUIDGeneratorMock(),
            heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock()
        )

        // Then
        withExtendedLifetime(instrumentation) {
            DDAssertActiveSwizzlings([
                "viewDidAppear:",
                "viewDidDisappear:",
            ])
            XCTAssertNil(instrumentation.longTasks)
        }
    }

    // Note: It's not possible to build a macOS equivalent for this test, since we
    // do not swizzle. Instead, we add a local event monitor and a notification observer.
    // Apple does not provide APIs to obtain the list of event monitors nor observers.
    func testWhenOnlyUIKitActionsPredicateIsConfigured_itInstrumentsUIApplication() throws {
        // When
        let instrumentation = RUMInstrumentation(
            featureScope: NOPFeatureScope(),
            predicates: makePredicates(rumActionsPredicate: UIKitRUMActionsPredicateMock()),
            longTaskThreshold: nil,
            appHangThreshold: .mockAny(),
            mainQueue: .main,
            dateProvider: SystemDateProvider(),
            backtraceReporter: BacktraceReporterMock(),
            fatalErrorContext: FatalErrorContextNotifierMock(),
            processID: .mockAny(),
            notificationCenter: .default,
            bundleType: .iOSApp,
            watchdogTermination: .mockRandom(),
            memoryWarningMonitor: .mockRandom(),
            uuidGenerator: RUMUUIDGeneratorMock(),
            heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock()
        )

        // Then
        withExtendedLifetime(instrumentation) {
            #if os(tvOS)
            DDAssertActiveSwizzlings(["sendEvent:"])
            #else
            DDAssertActiveSwizzlings(["sendEvent:", "setDelegate:", "delegate"])
            #endif
            XCTAssertNil(instrumentation.longTasks)
        }
    }

    func testWhenOnlySwiftUIViewsPredicateIsConfigured_itInstrumentsUIViewController() throws {
        // When
        let instrumentation = RUMInstrumentation(
            featureScope: NOPFeatureScope(),
            predicates: makePredicates(swiftUIRUMViewsPredicate: SwiftUIRUMViewsPredicateMock()),
            longTaskThreshold: nil,
            appHangThreshold: .mockAny(),
            mainQueue: .main,
            dateProvider: SystemDateProvider(),
            backtraceReporter: BacktraceReporterMock(),
            fatalErrorContext: FatalErrorContextNotifierMock(),
            processID: .mockAny(),
            notificationCenter: .default,
            bundleType: .iOSApp,
            watchdogTermination: .mockRandom(),
            memoryWarningMonitor: .mockRandom(),
            uuidGenerator: RUMUUIDGeneratorMock(),
            heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock()
        )

        // Then
        withExtendedLifetime(instrumentation) {
            DDAssertActiveSwizzlings([
                "viewDidAppear:",
                "viewDidDisappear:",
            ])
            XCTAssertNil(instrumentation.longTasks)
        }
    }

    func testWhenOnlySwiftUIActionsPredicateIsConfigured_itInstrumentsUIApplication() throws {
        // When
        let instrumentation = RUMInstrumentation(
            featureScope: NOPFeatureScope(),
            predicates: makePredicates(swiftUIRUMActionsPredicate: SwiftUIRUMActionsPredicateMock()),
            longTaskThreshold: nil,
            appHangThreshold: .mockAny(),
            mainQueue: .main,
            dateProvider: SystemDateProvider(),
            backtraceReporter: BacktraceReporterMock(),
            fatalErrorContext: FatalErrorContextNotifierMock(),
            processID: .mockAny(),
            notificationCenter: .default,
            bundleType: .iOSApp,
            watchdogTermination: .mockRandom(),
            memoryWarningMonitor: .mockRandom(),
            uuidGenerator: RUMUUIDGeneratorMock(),
            heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock()
        )

        // Then
        withExtendedLifetime(instrumentation) {
            DDAssertActiveSwizzlings(["sendEvent:"])
            XCTAssertNil(instrumentation.longTasks)
        }
    }
    #else
    // TODO: RUM-16718 macOS testing for views predicate if possible
    #endif

    #if !os(tvOS) && !os(macOS)
    func testWhenScrollAndSwipeActionsTrackingIsDisabled_itDoesNotInstrumentUIScrollView() throws {
        // When
        let instrumentation = RUMInstrumentation(
            featureScope: NOPFeatureScope(),
            predicates: makePredicates(rumActionsPredicate: UIKitRUMActionsPredicateMock()),
            trackScrollAndSwipeActions: false,
            longTaskThreshold: nil,
            appHangThreshold: .mockAny(),
            mainQueue: .main,
            dateProvider: SystemDateProvider(),
            backtraceReporter: BacktraceReporterMock(),
            fatalErrorContext: FatalErrorContextNotifierMock(),
            processID: .mockAny(),
            notificationCenter: .default,
            bundleType: .iOSApp,
            watchdogTermination: .mockRandom(),
            memoryWarningMonitor: .mockRandom(),
            uuidGenerator: RUMUUIDGeneratorMock(),
            heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock()
        )

        // Then
        withExtendedLifetime(instrumentation) {
            DDAssertActiveSwizzlings(["sendEvent:"])
            XCTAssertNil(instrumentation.scrollViewSwizzler)
            XCTAssertNil(instrumentation.scrollHandler)
        }
    }
    #endif

    func testWhenOnlyLongTasksThresholdIsConfigured_itInstrumentsRunLoop() throws {
        // When
        let instrumentation = RUMInstrumentation(
            featureScope: NOPFeatureScope(),
            predicates: makePredicates(),
            longTaskThreshold: 0.5,
            appHangThreshold: .mockAny(),
            mainQueue: .main,
            dateProvider: SystemDateProvider(),
            backtraceReporter: BacktraceReporterMock(),
            fatalErrorContext: FatalErrorContextNotifierMock(),
            processID: .mockAny(),
            notificationCenter: .default,
            bundleType: .iOSApp,
            watchdogTermination: .mockRandom(),
            memoryWarningMonitor: .mockRandom(),
            uuidGenerator: RUMUUIDGeneratorMock(),
            heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock()
        )

        // Then
        try withExtendedLifetime(instrumentation) {
            DDAssertActiveSwizzlings([])
            let beginRunLoopObserver = try XCTUnwrap(instrumentation.longTasks?.observer_begin)
            let endRunLoopObserver = try XCTUnwrap(instrumentation.longTasks?.observer_end)
            XCTAssertTrue(CFRunLoopContainsObserver(RunLoop.main.getCFRunLoop(), beginRunLoopObserver, .commonModes))
            XCTAssertTrue(CFRunLoopContainsObserver(RunLoop.main.getCFRunLoop(), endRunLoopObserver, .commonModes))
        }
    }

    func testWhenLongTasksThresholdIsLessOrEqualZero_itDoesNotInstrumentsRunLoop() {
        // When
        let instrumentation = RUMInstrumentation(
            featureScope: NOPFeatureScope(),
            predicates: makePredicates(),
            longTaskThreshold: .mockRandom(min: -100, max: 0),
            appHangThreshold: .mockAny(),
            mainQueue: .main,
            dateProvider: SystemDateProvider(),
            backtraceReporter: BacktraceReporterMock(),
            fatalErrorContext: FatalErrorContextNotifierMock(),
            processID: .mockAny(),
            notificationCenter: .default,
            bundleType: .iOSApp,
            watchdogTermination: .mockRandom(),
            memoryWarningMonitor: .mockRandom(),
            uuidGenerator: RUMUUIDGeneratorMock(),
            heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock()
        )

        // Then
        withExtendedLifetime(instrumentation) {
            XCTAssertNil(instrumentation.longTasks)
        }
    }

    func testWhenAppHangThresholdIsConfigured_itInstrumentsAppHangs() {
        // When
        let instrumentation = RUMInstrumentation(
            featureScope: NOPFeatureScope(),
            predicates: makePredicates(),
            longTaskThreshold: .mockRandom(min: -100, max: 0),
            appHangThreshold: 2,
            mainQueue: .main,
            dateProvider: SystemDateProvider(),
            backtraceReporter: BacktraceReporterMock(),
            fatalErrorContext: FatalErrorContextNotifierMock(),
            processID: .mockAny(),
            notificationCenter: .default,
            bundleType: .iOSApp,
            watchdogTermination: .mockRandom(),
            memoryWarningMonitor: .mockRandom(),
            uuidGenerator: RUMUUIDGeneratorMock(),
            heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock()
        )

        // Then
        withExtendedLifetime(instrumentation) {
            XCTAssertNotNil(instrumentation.appHangs)
        }
    }

    func testWhenAppHangThresholdIsNotConfigured_itDoesNotInstrumentsAppHangs() {
        // When
        let instrumentation = RUMInstrumentation(
            featureScope: NOPFeatureScope(),
            predicates: makePredicates(),
            longTaskThreshold: .mockRandom(min: -100, max: 0),
            appHangThreshold: nil,
            mainQueue: .main,
            dateProvider: SystemDateProvider(),
            backtraceReporter: BacktraceReporterMock(),
            fatalErrorContext: FatalErrorContextNotifierMock(),
            processID: .mockAny(),
            notificationCenter: .default,
            bundleType: .iOSApp,
            watchdogTermination: .mockRandom(),
            memoryWarningMonitor: .mockRandom(),
            uuidGenerator: RUMUUIDGeneratorMock(),
            heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock()
        )

        // Then
        withExtendedLifetime(instrumentation) {
            XCTAssertNil(instrumentation.appHangs)
        }
    }

    func testAppHangsAreDisabled_oniOSWidgets() {
        // When
        let instrumentation = RUMInstrumentation(
            featureScope: NOPFeatureScope(),
            predicates: makePredicates(),
            longTaskThreshold: 0.1,
            appHangThreshold: 0.1,
            mainQueue: .main,
            dateProvider: SystemDateProvider(),
            backtraceReporter: BacktraceReporterMock(),
            fatalErrorContext: FatalErrorContextNotifierMock(),
            processID: .mockAny(),
            notificationCenter: .default,
            bundleType: .iOSAppExtension,
            watchdogTermination: .mockRandom(),
            memoryWarningMonitor: .mockRandom(),
            uuidGenerator: RUMUUIDGeneratorMock(),
            heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock()
        )

        // Then
        withExtendedLifetime(instrumentation) {
            XCTAssertNil(instrumentation.appHangs)
        }
    }

    #if !os(macOS)
    func testGivenAllInstrumentationsConfigured_whenSubscribed_itSetsSubsciberInRespectiveHandlers() throws {
        // Given
        let instrumentation = RUMInstrumentation(
            featureScope: NOPFeatureScope(),
            predicates: makePredicates(
                rumViewsPredicate: UIKitRUMViewsPredicateMock(),
                rumActionsPredicate: UIKitRUMActionsPredicateMock(),
                swiftUIRUMViewsPredicate: SwiftUIRUMViewsPredicateMock(),
                swiftUIRUMActionsPredicate: SwiftUIRUMActionsPredicateMock()
            ),
            longTaskThreshold: 0.5,
            appHangThreshold: 2,
            mainQueue: .main,
            dateProvider: SystemDateProvider(),
            backtraceReporter: BacktraceReporterMock(),
            fatalErrorContext: FatalErrorContextNotifierMock(),
            processID: .mockAny(),
            notificationCenter: .default,
            bundleType: .iOSApp,
            watchdogTermination: .mockRandom(),
            memoryWarningMonitor: .mockRandom(),
            uuidGenerator: RUMUUIDGeneratorMock(),
            heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock()
        )
        let subscriber = RUMCommandSubscriberMock()

        // When
        instrumentation.publish(to: subscriber)

        // Then
        withExtendedLifetime(instrumentation) {
            XCTAssertIdentical(instrumentation.viewsHandler.subscriber, subscriber)
            XCTAssertIdentical((instrumentation.actionsHandler as? RUMActionsHandler)?.subscriber, subscriber)
            XCTAssertIdentical(instrumentation.longTasks?.subscriber, subscriber)
            XCTAssertIdentical(instrumentation.appHangs?.nonFatalHangsHandler.subscriber, subscriber)
        }
    }
    #else
    func testGivenAllInstrumentationsConfigured_whenSubscribed_itSetsSubsciberInRespectiveHandlers() throws {
        // Given
        let instrumentation = RUMInstrumentation(
            featureScope: NOPFeatureScope(),
            predicates: makePredicates(
                rumViewsPredicate: UIKitRUMViewsPredicateMock(),
                rumActionsPredicate: MacOSRUMActionsPredicateMock(),
                swiftUIRUMViewsPredicate: SwiftUIRUMViewsPredicateMock()
            ),
            longTaskThreshold: 0.5,
            appHangThreshold: 2,
            mainQueue: .main,
            dateProvider: SystemDateProvider(),
            backtraceReporter: BacktraceReporterMock(),
            fatalErrorContext: FatalErrorContextNotifierMock(),
            processID: .mockAny(),
            notificationCenter: .default,
            bundleType: .iOSApp,
            watchdogTermination: .mockRandom(),
            memoryWarningMonitor: .mockRandom(),
            uuidGenerator: RUMUUIDGeneratorMock(),
            heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock()
        )
        let subscriber = RUMCommandSubscriberMock()

        // When
        instrumentation.publish(to: subscriber)

        // Then
        withExtendedLifetime(instrumentation) {
            XCTAssertIdentical(instrumentation.viewsHandler.subscriber, subscriber)
            XCTAssertIdentical((instrumentation.actionsHandler as? RUMActionsHandler)?.subscriber, subscriber)
            XCTAssertIdentical(instrumentation.longTasks?.subscriber, subscriber)
            XCTAssertIdentical(instrumentation.appHangs?.nonFatalHangsHandler.subscriber, subscriber)
        }
    }
    #endif
}

internal func DDAssertActiveSwizzlings(_ expectedSwizzledSelectors: [String], file: StaticString = #fileID, line: UInt = #line) {
    _DDEvaluateAssertion(message: "Only \(expectedSwizzledSelectors) swizzlings should be active", file: file, line: line) {
        let actual = Swizzling.methods.map { "\(method_getName($0))" }.sorted()
        let expected = expectedSwizzledSelectors.sorted()

        guard actual == expected else {
            throw DDAssertError.expectedFailure("actual swizzlings: \(actual) don't match expected ones: \(expected)")
        }
    }
}
#endif
