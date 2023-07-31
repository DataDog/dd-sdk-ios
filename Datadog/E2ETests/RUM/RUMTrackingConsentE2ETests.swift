/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogCore
import DatadogRUM

class RUMTrackingConsentE2ETests: E2ETests {
    private var rum: RUMMonitorProtocol { RUMMonitor.shared() }

    override func setUp() {
        skipSDKInitialization = true // we will initialize it in each test
        super.setUp()
    }

    /// - api-surface: RUM.enable() -> RUMMonitorProtocol
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_config_consent_pending
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_config_consent_pending: number of views is above expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_config_consent_pending\").rollup(\"count\").by(\"@type\").last(\"1d\") > 1"
    /// ```
    func test_rum_config_consent_pending() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .pending
            )

            RUM.enable(with: .e2e)
        }
        rum.sendRandomRUMEvent()
    }

    /// - api-surface: RUM.enable() -> RUMMonitorProtocol
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_config_consent_granted
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_config_consent_granted: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_config_consent_granted\").rollup(\"count\").by(\"@type\").last(\"1d\") < 1"
    /// ```
    func test_rum_config_consent_granted() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .granted
            )

            RUM.enable(with: .e2e)
        }
        rum.sendRandomRUMEvent()
    }

    /// - api-surface: RUM.enable() -> RUMMonitorProtocol
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_config_consent_not_granted
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_config_consent_not_granted: number of views is above expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_config_consent_not_granted\").rollup(\"count\").by(\"@type\").last(\"1d\") > 1"
    /// ```
    func test_rum_config_consent_not_granted() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .notGranted
            )

            RUM.enable(with: .e2e)
        }
        rum.sendRandomRUMEvent()
    }

    /// - api-surface: RUMMonitorProtocol.enable() -> RUMMonitorProtocol
    /// - api-surface: Datadog.set(trackingConsent: TrackingConsent)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_config_consent_pending_to_granted
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_config_consent_pending_to_granted: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_config_consent_pending_to_granted\").rollup(\"count\").by(\"@type\").last(\"1d\") < 1"
    /// ```
    func test_rum_config_consent_pending_to_granted() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .pending
            )

            RUM.enable(with: .e2e)
        }
        rum.dd.sendRandomRUMEvent()
        measure(resourceName: DD.PerfSpanName.setTrackingConsent) {
            Datadog.set(trackingConsent: .granted)
        }
    }

    /// - api-surface: RUM.enable() -> RUMMonitorProtocol
    /// - api-surface: Datadog.set(trackingConsent: TrackingConsent)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_config_consent_pending_to_not_granted
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_config_consent_pending_to_not_granted: number of views is above expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_config_consent_pending_to_not_granted\").rollup(\"count\").by(\"@type\").last(\"1d\") > 1"
    /// ```
    func test_rum_config_consent_pending_to_not_granted() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .pending
            )

            RUM.enable(with: .e2e)
        }
        rum.dd.sendRandomRUMEvent()
        measure(resourceName: DD.PerfSpanName.setTrackingConsent) {
            Datadog.set(trackingConsent: .notGranted)
        }
    }

    /// - api-surface: RUM.enable() -> RUMMonitorProtocol
    /// - api-surface: Datadog.set(trackingConsent: TrackingConsent)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_config_consent_granted_to_not_granted
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_config_consent_granted_to_not_granted: number of views is above expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_config_consent_granted_to_not_granted\").rollup(\"count\").by(\"@type\").last(\"1d\") > 1"
    /// ```
    func test_rum_config_consent_granted_to_not_granted() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .granted
            )

            RUM.enable(with: .e2e)
        }
        rum.dd.sendRandomRUMEvent()
        measure(resourceName: DD.PerfSpanName.setTrackingConsent) {
            Datadog.set(trackingConsent: .notGranted)
        }
    }

    /// - api-surface: RUM.enable() -> RUMMonitorProtocol
    /// - api-surface: Datadog.set(trackingConsent: TrackingConsent)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_config_consent_granted_to_pending
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_config_consent_granted_to_pending: number of views is above expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_config_consent_granted_to_pending\").rollup(\"count\").by(\"@type\").last(\"1d\") > 1"
    /// ```
    func test_rum_config_consent_granted_to_pending() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .granted
            )

            RUM.enable(with: .e2e)
        }
        rum.dd.sendRandomRUMEvent()
        measure(resourceName: DD.PerfSpanName.setTrackingConsent) {
            Datadog.set(trackingConsent: .pending)
        }
    }

    /// - api-surface: RUM.enable() -> RUMMonitorProtocol
    /// - api-surface: Datadog.set(trackingConsent: TrackingConsent)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_config_consent_not_granted_to_granted
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_config_consent_not_granted_to_granted: number of views is below expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_config_consent_not_granted_to_granted\").rollup(\"count\").by(\"@type\").last(\"1d\") < 1"
    /// ```
    func test_rum_config_consent_not_granted_to_granted() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .notGranted
            )

            RUM.enable(with: .e2e)
        }
        rum.dd.sendRandomRUMEvent()
        measure(resourceName: DD.PerfSpanName.setTrackingConsent) {
            Datadog.set(trackingConsent: .granted)
        }
    }

    /// - api-surface: RUM.enable() -> RUMMonitorProtocol
    /// - api-surface: Datadog.set(trackingConsent: TrackingConsent)
    ///
    /// - data monitor:
    /// ```rum
    /// $monitor_id = rum_config_consent_not_granted_to_pending
    /// $monitor_name = "[RUM] [iOS] Nightly - rum_config_consent_not_granted_to_pending: number of views is above expected value"
    /// $monitor_query = "rum(\"service:com.datadog.ios.nightly @type:action @context.test_method_name:rum_config_consent_not_granted_to_pending\").rollup(\"count\").by(\"@type\").last(\"1d\") > 1"
    /// ```
    func test_rum_config_consent_not_granted_to_pending() {
        measure(resourceName: DD.PerfSpanName.sdkInitialize) {
            Datadog.initialize(
                with: .e2e,
                trackingConsent: .notGranted
            )

            RUM.enable(with: .e2e)
        }
        rum.dd.sendRandomRUMEvent()
        measure(resourceName: DD.PerfSpanName.setTrackingConsent) {
            Datadog.set(trackingConsent: .pending)
        }
    }
}
