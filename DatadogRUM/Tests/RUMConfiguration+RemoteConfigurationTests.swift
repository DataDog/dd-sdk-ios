/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal
@testable import DatadogRUM

class RUMConfiguration_RemoteConfigurationTests: XCTestCase {
    /// When there is no remote configuration (`nil`) or its namespaces carry no value, RUM must
    /// behave exactly as configured in-code.
    func testWhenNoRemoteValuesAreProvided_itLeavesConfigurationUnchanged() {
        let baseline: RUM.Configuration = .mockRandom()

        var withNilRemote = baseline
        withNilRemote.apply(remoteConfiguration: nil)
        DDAssertReflectionEqual(withNilRemote, baseline)

        var withEmptyRemote = baseline
        withEmptyRemote.apply(remoteConfiguration: .mockWith()) // every namespace absent
        DDAssertReflectionEqual(withEmptyRemote, baseline)
    }

    /// A fully-populated remote `rum` namespace must override every mapped behavioral parameter,
    /// regardless of the in-code baseline. Both the baseline and the remote are randomized and the
    /// check repeated, so random enum/boolean values exercise every branch (e.g.
    /// `vitalsUpdateFrequency == .never`, `trackResources == false`) over the run.
    func testItOverridesEveryBehavioralParameterFromRemoteValues() throws {
        for _ in 0..<100 {
            // Given
            let rum: RemoteConfiguration.RUM = .mockRandom()
            var configuration: RUM.Configuration = .mockRandom()

            // When
            configuration.apply(remoteConfiguration: .mockWith(rum: rum))

            // Then
            XCTAssertEqual(configuration.telemetrySampleRate, SampleRate(try XCTUnwrap(rum.telemetrySampleRate)))
            XCTAssertEqual(configuration.trackAnonymousUser, rum.trackAnonymousUser)
            XCTAssertEqual(configuration.trackBackgroundEvents, rum.trackBackgroundEvents)
            XCTAssertEqual(configuration.trackFrustrations, rum.trackFrustrations)
            XCTAssertEqual(configuration.longTaskThreshold, .ddFromMilliseconds(.ddWithNoOverflow(try XCTUnwrap(rum.longTaskThresholdMs))))
            XCTAssertEqual(configuration.appHangThreshold, .ddFromMilliseconds(.ddWithNoOverflow(try XCTUnwrap(rum.appHangThresholdMs))))
            XCTAssertEqual(configuration.trackSlowFrames, rum.trackSlowFrames)
            XCTAssertEqual(configuration.trackWatchdogTerminations, rum.trackWatchdogTerminations)
            XCTAssertEqual(configuration.vitalsUpdateFrequency, expectedVitalsFrequency(try XCTUnwrap(rum.vitalsUpdateFrequency)))

            // `trackResources` / `trackUserInteractions` are modeled as the presence of a tracking
            // config / action predicate: enabling keeps whatever is set, disabling clears it. Either
            // way, `presence == remote flag`.
            XCTAssertEqual(configuration.urlSessionTracking != nil, try XCTUnwrap(rum.trackResources))
            #if !os(watchOS)
            XCTAssertEqual(configuration.trackMemoryWarnings, try XCTUnwrap(rum.trackMemoryWarnings))
            XCTAssertEqual(configuration.uiKitActionsPredicate != nil, try XCTUnwrap(rum.trackUserInteractions))
            #endif
        }
    }

    /// `trackResources` / `trackUserInteractions` are modeled as the presence of a tracking config or
    /// action predicate. When the remote enables them but the developer already provided one, the
    /// in-code value must be preserved rather than replaced with a default.
    func testWhenRemoteEnablesAlreadyConfiguredTracking_itPreservesInCodeValues() {
        // Given
        let customHost = "custom.example.com"
        #if !os(watchOS)
        let predicate = UIKitRUMActionsPredicateMock()
        #endif

        var configuration: RUM.Configuration = .mockWith { configuration in
            configuration.urlSessionTracking = .init(firstPartyHostsTracing: .trace(hosts: [customHost]))
            #if !os(watchOS)
            configuration.uiKitActionsPredicate = predicate
            #endif
        }

        // When
        configuration.apply(remoteConfiguration: .mockWith(rum: .mockWith(trackResources: true, trackUserInteractions: true)))

        // Then
        guard case let .trace(hosts, _, _) = configuration.urlSessionTracking?.firstPartyHostsTracing else {
            return XCTFail("Expected in-code first-party hosts tracing to be preserved")
        }
        XCTAssertEqual(hosts, [customHost])
        #if !os(watchOS)
        XCTAssertIdentical(configuration.uiKitActionsPredicate as AnyObject, predicate)
        #endif
    }

    // MARK: - Trace namespace (distributed tracing / network instrumentation)

    /// The `trace` namespace must enable network instrumentation (even when none was configured
    /// in-code) and set up distributed tracing for the given hosts. When header formats are provided,
    /// they apply to every traced host.
    func testWhenRemoteTraceProvidesHostsAndHeaderTypes_itConfiguresDistributedTracing() throws {
        // Given no in-code network instrumentation
        var configuration: RUM.Configuration = .mockWith { $0.urlSessionTracking = nil }
        let remote: RemoteConfiguration = .mockWith(
            trace: .init(
                sampleRate: 55,
                traceContextInjection: .all,
                tracedHosts: ["api.example.com", "example.com"],
                tracingHeaderTypes: [.datadog, .b3]
            )
        )

        // When
        configuration.apply(remoteConfiguration: remote)

        // Then
        guard case let .traceWithHeaders(hostsWithHeaders, sampleRate, injection) =
            configuration.urlSessionTracking?.firstPartyHostsTracing else {
            return XCTFail("Expected `.traceWithHeaders` first-party hosts tracing to be configured")
        }
        XCTAssertEqual(hostsWithHeaders, [
            "api.example.com": [.datadog, .b3],
            "example.com": [.datadog, .b3]
        ])
        XCTAssertEqual(sampleRate, 55)
        XCTAssertEqual(injection, .all)
    }

    /// When the `trace` namespace provides hosts but no header formats, RUM falls back to the default
    /// trace headers and the default sample rate / injection strategy.
    func testWhenRemoteTraceProvidesHostsWithoutHeaderTypes_itUsesDefaultTraceHeaders() throws {
        // Given no in-code network instrumentation
        var configuration: RUM.Configuration = .mockWith { $0.urlSessionTracking = nil }
        let remote: RemoteConfiguration = .mockWith(trace: .init(tracedHosts: ["example.com"]))

        // When
        configuration.apply(remoteConfiguration: remote)

        // Then
        guard case let .trace(hosts, sampleRate, injection) =
            configuration.urlSessionTracking?.firstPartyHostsTracing else {
            return XCTFail("Expected `.trace` first-party hosts tracing to be configured")
        }
        XCTAssertEqual(hosts, ["example.com"])
        XCTAssertEqual(sampleRate, .maxSampleRate) // default when the remote omits `sampleRate`
        XCTAssertEqual(injection, .sampled) // default when the remote omits `traceContextInjection`
    }

    /// A `trace` namespace without hosts has nothing to instrument and must leave the configuration's
    /// network instrumentation untouched.
    func testWhenRemoteTraceHasNoHosts_itLeavesNetworkInstrumentationUnchanged() {
        var configuration: RUM.Configuration = .mockWith { $0.urlSessionTracking = nil }

        configuration.apply(remoteConfiguration: .mockWith(trace: .init(sampleRate: 42, tracedHosts: nil)))

        XCTAssertNil(configuration.urlSessionTracking)
    }

    /// An explicit empty host list means "stop propagating traces": it must clear the in-code
    /// first-party hosts tracing while keeping the rest of the network instrumentation.
    func testWhenRemoteTraceHasEmptyHosts_itClearsInCodeTracing() {
        var configuration: RUM.Configuration = .mockWith {
            $0.urlSessionTracking = .init(firstPartyHostsTracing: .trace(hosts: ["custom.example.com"]))
        }

        configuration.apply(remoteConfiguration: .mockWith(trace: .init(tracedHosts: [])))

        XCTAssertNotNil(configuration.urlSessionTracking)
        XCTAssertNil(configuration.urlSessionTracking?.firstPartyHostsTracing)
    }

    /// An explicit empty host list has nothing to clear when no network instrumentation was configured
    /// in-code, so the configuration must stay untouched (no default instrumentation is installed).
    func testWhenRemoteTraceHasEmptyHostsAndNoInCodeInstrumentation_itLeavesConfigurationUnchanged() {
        var configuration: RUM.Configuration = .mockWith { $0.urlSessionTracking = nil }

        configuration.apply(remoteConfiguration: .mockWith(trace: .init(tracedHosts: [])))

        XCTAssertNil(configuration.urlSessionTracking)
    }

    /// An explicit `rum.trackResources == false` disables resource tracking regardless, so it must
    /// suppress trace instrumentation even when the `trace` namespace provides hosts.
    func testWhenRemoteTrackResourcesIsFalse_itSuppressesTraceInstrumentation() {
        var configuration: RUM.Configuration = .mockWith { $0.urlSessionTracking = nil }

        configuration.apply(
            remoteConfiguration: .mockWith(
                rum: .mockWith(trackResources: false),
                trace: .init(tracedHosts: ["example.com"])
            )
        )

        XCTAssertNil(configuration.urlSessionTracking)
    }

    // MARK: - Helpers

    /// The independent oracle for the `vitalsUpdateFrequency` mapping (`.never` disables vitals).
    private func expectedVitalsFrequency(
        _ remote: RemoteConfiguration.RUM.VitalsUpdateFrequency
    ) -> RUM.Configuration.VitalsFrequency? {
        switch remote {
        case .frequent: return .frequent
        case .average: return .average
        case .rare: return .rare
        case .never: return nil
        }
    }
}
