/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal
@testable import DatadogTrace

class TraceConfiguration_RemoteConfigurationTests: XCTestCase {
    /// When there is no remote configuration (`nil`) or its `trace` namespace is absent, Trace must
    /// behave exactly as configured in-code.
    func testWhenNoRemoteValuesAreProvided_itLeavesConfigurationUnchanged() {
        let baseline = Trace.Configuration(
            sampleRate: 42,
            urlSessionTracking: .init(firstPartyHostsTracing: .trace(hosts: ["in-code.example.com"]))
        )

        var withNilRemote = baseline
        withNilRemote.apply(remoteConfiguration: nil)
        DDAssertReflectionEqual(withNilRemote, baseline)

        var withEmptyRemote = baseline
        withEmptyRemote.apply(remoteConfiguration: .mockWith()) // every namespace absent
        DDAssertReflectionEqual(withEmptyRemote, baseline)

        var withEmptyNamespace = baseline
        withEmptyNamespace.apply(remoteConfiguration: .mockWith(trace: .mockWith())) // all fields absent
        DDAssertReflectionEqual(withEmptyNamespace, baseline)
    }

    /// A remote `sampleRate` overrides the span sample rate.
    func testWhenRemoteProvidesSampleRate_itOverridesSpanSampleRate() {
        var configuration = Trace.Configuration(sampleRate: 10)

        configuration.apply(remoteConfiguration: .mockWith(trace: .mockWith(sampleRate: 90)))

        XCTAssertEqual(configuration.sampleRate, 90)
    }

    /// The `trace` namespace must enable network instrumentation (even when none was configured
    /// in-code) and set up distributed tracing for the given hosts. When header formats are provided,
    /// they apply to every traced host, and the remote `sampleRate` drives the tracing sample rate.
    func testWhenRemoteTraceProvidesHostsAndHeaderTypes_itConfiguresDistributedTracing() {
        // Given no in-code network instrumentation
        var configuration = Trace.Configuration(urlSessionTracking: nil)

        // When
        configuration.apply(remoteConfiguration: .mockWith(
            trace: .init(
                sampleRate: 55,
                traceContextInjection: .all,
                tracedHosts: [
                    .init(host: "api.example.com", propagatorTypes: [.datadog, .b3]),
                    .init(host: "example.com", propagatorTypes: [.datadog, .b3])
                ]
            )
        ))

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

    /// When the `trace` namespace provides hosts but no header formats, those hosts are traced with no
    /// header formats; the sample rate / injection strategy fall back to the module defaults.
    func testWhenRemoteTraceProvidesHostsWithoutHeaderTypes_itUsesNoHeaderFormats() {
        var configuration = Trace.Configuration(urlSessionTracking: nil)

        configuration.apply(remoteConfiguration: .mockWith(trace: .init(tracedHosts: [.init(host: "example.com", propagatorTypes: [])])))

        guard case let .traceWithHeaders(hostsWithHeaders, sampleRate, injection) =
            configuration.urlSessionTracking?.firstPartyHostsTracing else {
            return XCTFail("Expected `.traceWithHeaders` first-party hosts tracing to be configured")
        }
        XCTAssertEqual(hostsWithHeaders, ["example.com": []])
        XCTAssertEqual(sampleRate, .maxSampleRate) // default when the remote omits `sampleRate`
        XCTAssertEqual(injection, .sampled) // default when the remote omits `traceContextInjection`
    }

    /// A `trace` namespace without hosts has nothing to instrument and must leave the configuration's
    /// network instrumentation untouched (only the span sample rate is affected).
    func testWhenRemoteTraceHasNoHosts_itLeavesNetworkInstrumentationUnchanged() {
        var configuration = Trace.Configuration(sampleRate: 10, urlSessionTracking: nil)

        configuration.apply(remoteConfiguration: .mockWith(trace: .mockWith(sampleRate: 42, tracedHosts: nil)))

        XCTAssertEqual(configuration.sampleRate, 42, "The span sample rate is still overridden")
        XCTAssertNil(configuration.urlSessionTracking, "No hosts means nothing to instrument")
    }

    /// An explicit empty host list means "stop propagating traces": no host would ever be first-party,
    /// so the URLSession instrumentation itself must be removed entirely (it would only pay swizzling
    /// overhead for no benefit).
    func testWhenRemoteTraceHasEmptyHosts_itRemovesInCodeInstrumentation() {
        var configuration = Trace.Configuration(
            urlSessionTracking: .init(
                firstPartyHostsTracing: .trace(hosts: ["in-code.example.com"]),
                redactedStatusCodes: [401, 403]
            )
        )

        configuration.apply(remoteConfiguration: .mockWith(trace: .init(tracedHosts: [])))

        XCTAssertNil(configuration.urlSessionTracking)
    }

    /// An explicit empty host list has nothing to clear when no network instrumentation was configured
    /// in-code, so the configuration must stay untouched (no default instrumentation is installed).
    func testWhenRemoteTraceHasEmptyHostsAndNoInCodeInstrumentation_itLeavesConfigurationUnchanged() {
        var configuration = Trace.Configuration(urlSessionTracking: nil)

        configuration.apply(remoteConfiguration: .mockWith(trace: .init(tracedHosts: [])))

        XCTAssertNil(configuration.urlSessionTracking)
    }

    /// When the developer already configured `urlSessionTracking`, applying remote hosts must replace
    /// only its first-party hosts tracing while preserving its other settings (e.g. redacted status
    /// codes).
    func testWhenRemoteTraceProvidesHosts_itPreservesOtherURLSessionTrackingSettings() {
        var configuration = Trace.Configuration(
            urlSessionTracking: .init(
                firstPartyHostsTracing: .trace(hosts: ["in-code.example.com"]),
                redactedStatusCodes: [401, 403]
            )
        )

        configuration.apply(remoteConfiguration: .mockWith(trace: .init(tracedHosts: [.init(host: "remote.example.com", propagatorTypes: [])])))

        guard case let .traceWithHeaders(hostsWithHeaders, _, _) = configuration.urlSessionTracking?.firstPartyHostsTracing else {
            return XCTFail("Expected `.traceWithHeaders` first-party hosts tracing to be configured")
        }
        XCTAssertEqual(hostsWithHeaders, ["remote.example.com": []], "First-party hosts tracing is replaced by the remote hosts")
        XCTAssertEqual(configuration.urlSessionTracking?.redactedStatusCodes, [401, 403], "Other settings are preserved")
    }

    /// When remote hosts are provided but the sample rate / injection strategy are omitted, the merge
    /// must keep the in-code values for those fields rather than falling back to the module defaults.
    func testWhenRemoteProvidesHostsWithoutSampleRateOrInjection_itPreservesInCodeValues() {
        var configuration = Trace.Configuration(
            urlSessionTracking: .init(
                firstPartyHostsTracing: .trace(hosts: ["in-code.example.com"], sampleRate: 30, traceControlInjection: .all)
            )
        )

        configuration.apply(remoteConfiguration: .mockWith(trace: .init(tracedHosts: [.init(host: "remote.example.com", propagatorTypes: [])])))

        guard case let .traceWithHeaders(hostsWithHeaders, sampleRate, injection) = configuration.urlSessionTracking?.firstPartyHostsTracing else {
            return XCTFail("Expected `.traceWithHeaders` first-party hosts tracing to be configured")
        }
        XCTAssertEqual(hostsWithHeaders, ["remote.example.com": []])
        XCTAssertEqual(sampleRate, 30)
        XCTAssertEqual(injection, .all)
    }

    /// A remote `sampleRate` drives both knobs: when the remote omits hosts but the app already
    /// configured `urlSessionTracking`, the propagation sample rate must be updated too (its hosts and
    /// injection strategy are preserved).
    func testWhenRemoteProvidesOnlySampleRate_itUpdatesExistingTracingSampleRate() {
        var configuration = Trace.Configuration(
            sampleRate: 10,
            urlSessionTracking: .init(
                firstPartyHostsTracing: .trace(hosts: ["in-code.example.com"], sampleRate: 20, traceControlInjection: .all)
            )
        )

        configuration.apply(remoteConfiguration: .mockWith(trace: .mockWith(sampleRate: 0, tracedHosts: nil)))

        XCTAssertEqual(configuration.sampleRate, 0)
        guard case let .trace(hosts, sampleRate, injection) = configuration.urlSessionTracking?.firstPartyHostsTracing else {
            return XCTFail("Expected `.trace` first-party hosts tracing to be configured")
        }
        XCTAssertEqual(hosts, ["in-code.example.com"])
        XCTAssertEqual(sampleRate, 0)
        XCTAssertEqual(injection, .all)
    }
}
