/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

class KronosE2ETests: E2ETests {
    /// The logger sending logs on Kronos execution. These logs are available in Mobile Integrations org.
    private var logger: Logger! // swiftlint:disable:this implicitly_unwrapped_optional
    /// The logger sending telemetry on internal Kronos execution. These logs are available in Mobile Integrations org.
    private var telemetryLogger: Logger! // swiftlint:disable:this implicitly_unwrapped_optional
    private let queue = DispatchQueue(label: "kronos-monitor-queue")

    override func setUp() {
        super.setUp()
        logger = Logger
            .builder
            .set(loggerName: "kronos-e2e")
            .build()
        telemetryLogger = Logger.builder
            .set(loggerName: "kronos-e2e-internal-telemetry")
            .sendNetworkInfo(true)
            .build()
    }

    override func tearDown() {
        logger = nil
        telemetryLogger = nil
        super.tearDown()
    }

    /// Creates kronos monitor for checking connections to all IPs resolved from NTP pool and sending additional telemetry on their statuses.
    private func createKronosMonitor() -> KronosMonitor? {
        if #available(iOS 14.2, *) {
            let monitor = KronosInternalMonitor(
                queue: queue,
                connectionMonitor: IPConnectionMonitor(queue: queue)
            )
            // Here we redirect IM's logger to E2E Kronos logger (`telemetryLogger`) to send data to Mobile Integrations org, not IM's org
            monitor.export(to: InternalMonitor(sdkLogger: telemetryLogger))
            return monitor
        } else {
            return nil
        }
    }

    ///  TODO: RUMM-1859: Add E2E tests for monitoring Kronos in nightly tests
    func test_kronos_clock_performs_sync_using_datadog_ntp_pool() { // E2E:wip
        /// The result of `KronosClock.sync()`.
        struct KronosSyncResult {
            /// First received server date.
            var firstReceivedDate: Date? = nil
            /// First received server offset.
            var firstReceivedOffset: TimeInterval? = nil
            /// Last received server date.
            var lastReceivedDate: Date? = nil
            /// Last received server offset.
            var lastReceivedOffset: TimeInterval? = nil
            /// Device date measured at the moment of receiving any server date. Used for additional debugging and comparision.
            var measuredDeviceDate = Date()
        }

        func performKronosSync(using pool: String) -> KronosSyncResult {
            KronosClock.reset()
            defer { KronosClock.reset() }

            // Given
            let numberOfSamplesForEachIP = 2 // exchange only 2 samples with each resolved IP - to run test quick

            // Each IP (each server) is asked in parallel, but samples are obtained sequentially.
            // Here we compute test timeout, to ensure that all (parallel) servers complete querying their (sequential) samples
            // below `testTimeout` with assuming +50% margin. This should guarantee no flakiness on test timeout.
            let testTimeout = kronosDefaultTimeout * Double(numberOfSamplesForEachIP) * 1.5

            // When
            let completionExpectation = expectation(description: "KronosClock.sync() calls completion closure")
            var result = KronosSyncResult()

            KronosClock.sync(
                from: pool,
                samples: numberOfSamplesForEachIP,
                monitor: createKronosMonitor(),
                first: { date, offset in // this closure could not be called if all samples to all servers resulted with failure
                    result.firstReceivedDate = date
                    result.firstReceivedOffset = offset
                    result.measuredDeviceDate = Date()
                },
                completion: { date, offset in // this closure should always be called
                    result.lastReceivedDate = date
                    result.lastReceivedOffset = offset
                    result.measuredDeviceDate = Date()
                    completionExpectation.fulfill()
                }
            )

            // Then

            // We don't expect receiving timeout on `completionExpectation`. Number of samples and individual sample timeout
            // is configured in a way that lets `KronosNTPClient` always fulfill the `completionExpectation`.
            waitForExpectations(timeout: testTimeout)

            return result
        }

        // Run test for each Datadog NTP pool:
        DateCorrector.datadogNTPServers.forEach { ddNTPPool in
            let result = measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
                performKronosSync(using: ddNTPPool)
            }

            // Report result for this pool:
            if let _ = result.firstReceivedDate, let _ = result.firstReceivedOffset, let serverDate = result.lastReceivedDate, let serverOffset = result.lastReceivedOffset {
                // We consider `KronosClock.sync()` result to be consistent only if it has both `first` and `last` time values set.
                // We log consistent result as INFO log that can be seen in Mobile Integration org.
                logger.info("KronosClock.sync() completed with consistent result for \(ddNTPPool)", attributes: [
                    "serverOffset_measured": serverDate.timeIntervalSince(result.measuredDeviceDate),
                    "serverOffset_received": serverOffset,
                    "serverDate_received": iso8601DateFormatter.string(from: serverDate),
                ])
            } else {
                // Inconsistent result may correspond to flaky execution, e.g. if network was unreachable or if **all** NTP calls received timeout.
                // We track inconsistent result as WARN log that will be watched by E2E monitor.
                logger.warn("KronosClock.sync() completed with inconsistent result for \(ddNTPPool)", attributes: [
                    "serverDate_firstReceived": result.firstReceivedDate.flatMap { iso8601DateFormatter.string(from: $0) },
                    "serverDate_lastReceived": result.lastReceivedDate.flatMap { iso8601DateFormatter.string(from: $0) },
                    "serverOffset_firstReceived": result.firstReceivedOffset,
                    "serverOffset_lastReceived": result.lastReceivedOffset,
                ])
            }
        }
    }

    ///  TODO: RUMM-1859: Add E2E tests for monitoring Kronos in nightly tests
    func test_kronos_ntp_client_queries_both_ipv4_and_ipv6_ips() { // E2E:wip
        /// The result of `KronosNTPClient.query(pool:)`.
        struct KronosNTPClientQueryResult {
            /// Partial offsets received for each NTP packet sent to each resolved IP.
            var receivedOffsets: [TimeInterval?] = []
            /// Expected number of NTP packets to send.
            var expectedNumberOfSamples = 0
            /// Actual number of NTP packets that completed.
            var numberOfCompletedSamples = 0
        }

        func performKronosNTPClientQuery() -> KronosNTPClientQueryResult {
            let testTimeout: TimeInterval = 30
            let monitor = createKronosMonitor()

            // Given
            let pool = "2.datadog.pool.ntp.org" // a pool resolved to multiple IPv4 and IPv6 addresses (e.g. 4 + 4)
            let numberOfSamplesForEachIP = 2 // exchange only 2 samples with each resolved IP - to run test quick

            // Each IP (each server) is asked in parallel, but samples are obtained sequentially.
            // Here we compute individual sample timeout, to ensure that all (parallel) servers complete querying their (sequential) samples
            // below `testTimeout` with assuming -30% margin. This should guarantee no flakiness on test timeout.
            let timeoutForEachSample = (testTimeout / Double(numberOfSamplesForEachIP)) * 0.7

            // When
            let completionExpectation = expectation(description: "It completes all samples for all IPs")
            var result = KronosNTPClientQueryResult()

            monitor?.notifySyncStart(from: pool) // must be notified by hand because normally it's called from `KronosClock.sync()`

            KronosNTPClient()
                .query(
                    pool: pool,
                    numberOfSamples: numberOfSamplesForEachIP,
                    maximumServers: .max, // query all resolved IPs in the pool - to include both IPv4 and IPv6
                    timeout: timeoutForEachSample,
                    monitor: monitor
                ) { offset, completed, total in
                    result.receivedOffsets.append(offset)
                    result.numberOfCompletedSamples = completed
                    result.expectedNumberOfSamples = total

                    if completed == total {
                        monitor?.notifySyncEnd(serverOffset: offset) // must be notified by hand because normally it's called from `KronosClock.sync()`
                        completionExpectation.fulfill()
                    }
                }

            // Then

            // We don't expect receiving timeout on `completionExpectation`. Number of samples and individual sample timeout
            // is configured in a way that lets `KronosNTPClient` always fulfill the `completionExpectation`.
            // In worst case, it can fulfill it, with recording only `nil` offsets, which will mean receiving timeouts
            // or error on all NTP queries.
            waitForExpectations(timeout: testTimeout)

            return result
        }

        // Run test:
        let result = measure(resourceName: DD.PerfSpanName.fromCurrentMethodName()) {
            performKronosNTPClientQuery()
        }

        // Report result:
        if result.receivedOffsets.contains(where: { offset in offset != nil }) {
            // We consider `KronosNTPClient.query(pool:)` result to be consistent if it received at least one offset.
            let receivedOffsets: [String] = result.receivedOffsets.map { offset in
                if let offset = offset {
                    return "\(offset)"
                } else {
                    return "(nil)"
                }
            }
            logger.info(
                "KronosNTPClient.query(pool:) completed with consistent result receiving \(result.numberOfCompletedSamples)/\(result.expectedNumberOfSamples) NTP packets",
                attributes: [
                    "offsets_received": receivedOffsets
                ]
            )
        } else {
            // Inconsistent result may correspond to flaky execution, e.g. if network was unreachable or if **all** NTP calls received timeout.
            // We track inconsistent result as WARN log that will be watched by E2E monitor.
            logger.warn(
                "KronosNTPClient.query(pool:) completed with inconsistent result receiving \(result.numberOfCompletedSamples)/\(result.expectedNumberOfSamples) NTP packets"
            )
        }
    }
}
