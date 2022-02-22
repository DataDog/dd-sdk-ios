/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Network

/// Telemetry monitor for `KronosClock`.
internal protocol KronosMonitor {
    // MARK: - Clock sync

    func notifySyncStart(from pool: String)
    func notifySyncEnd(serverOffset: TimeInterval?)

    // MARK: - DNS resolution

    func notifyResolveDNS(to addresses: [KronosInternetAddress])

    // MARK: - IP querying

    func notifyStartQuerying(ip address: KronosInternetAddress, numberOfSamples: Int)
    func notifyReceivePacket(from address: KronosInternetAddress, isValidSample: Bool)
    func notifyEndQuerying(ip address: KronosInternetAddress)

    // MARK: - Telemetry Export

    func export(to exporter: InternalMonitor)
}

#if DD_SDK_ENABLE_INTERNAL_MONITORING

/// `KronosMonitor` for diagnosing `KronosClock` in Internal Monitoring. Not used when Internal Monitoring is disabled (by default).
/// It is only implemented to collect extra telemetry  for troubleshooting  https://github.com/DataDog/dd-sdk-ios/issues/647
internal class KronosInternalMonitor: KronosMonitor {
    struct SyncResult: Encodable {
        /// The pool addres used by Kronos.
        let pool: String
        /// The server offset reported by Kronos.
        let serverOffset: TimeInterval?
        /// Stats for each IP resolved by Kronos DNS.
        let ips: [String: IP]

        struct IP: Encodable {
            let address: String?
            let connectionDuration: TimeInterval?
            let connectionCheckResult: IPConnectionCheckResult?
            let succeededPacketsCount: Int
            let failedPacketsCount: Int
        }
    }

    /// Used to gather stats on each IP during Kronos sync.
    private struct IPStats: Encodable {
        var connectionStart: Date? = nil
        var connectionEnd: Date? = nil
        var succeededPacketsCount = 0
        var failedPacketsCount = 0
        var checkResult: IPConnectionCheckResult? = nil
    }

    /// Queue for synchronising Kronos and `IPConnectionMonitor` callbacks.
    private let queue: DispatchQueue
    /// Dispatch group used to synchronize Kronos and `IPConnectionMonitor` tasks.
    /// It notifies readiness of all recorded details (collected asynchronously) so the `SyncResult` can be built and sent to Datadog.
    private let dispatchGroup = DispatchGroup()

    /// The address of the pool being synchronised by `KronosClock`.
    private var pool: String? = nil
    /// The final server offset retrieved from `KronosClock` (can be `nil` if anything went wrong).
    private var serverOffset: TimeInterval? = nil
    /// Stats for each IP resolved from the `pool`.
    private var statsByIP: [KronosInternetAddress: IPStats] = [:]
    /// Connection monitor checking additional reachability for each IP resolved from the `pool`. Only available from iOS 14.2.
    private let connectionMonitor: IPConnectionMonitorType?

    /// Internal Monitor for sending the `result` to Datadog.
    private var exporter: InternalMonitor? = nil

    convenience init() {
        let queue = DispatchQueue(label: "com.datadoghq.kronos-monitor", qos: .utility)
        if #available(iOS 14.2, tvOS 14.2, *) {
            self.init(
                queue: queue,
                connectionMonitor: IPConnectionMonitor(queue: queue)
            )
        } else {
            self.init(
                queue: queue,
                connectionMonitor: nil
            )
        }
    }

    init(queue: DispatchQueue, connectionMonitor: IPConnectionMonitorType?) {
        self.queue = queue
        self.connectionMonitor = connectionMonitor

        self.dispatchGroup.enter() // await Kronos completion
        self.dispatchGroup.enter() // await exporter registration

        self.dispatchGroup.notify(queue: self.queue) { [weak self] in
            self?.sendTelemetryToDatadog()
        }
    }

    // MARK: - Clock sync

    func notifySyncStart(from pool: String) {
        queue.async {
            self.pool = pool
        }
    }

    func notifySyncEnd(serverOffset: TimeInterval?) {
        queue.async {
            self.serverOffset = serverOffset
            self.dispatchGroup.leave() // notify Kronos completion
        }
    }

    // MARK: - Exporting

    func export(to exporter: InternalMonitor) {
        queue.async {
            self.exporter = exporter
            self.dispatchGroup.leave() // notify exporter registration
        }
    }

    // MARK: - DNS resolution

    func notifyResolveDNS(to addresses: [KronosInternetAddress]) {
        queue.async {
            addresses.forEach { ip in
                self.statsByIP[ip] = IPStats()

                if let connectionMonitor = self.connectionMonitor {
                    self.dispatchGroup.enter() // await connection check result
                    connectionMonitor.checkConnection(to: ip) { [weak self] result in // completion is called on `queue`
                        self?.statsByIP[ip]?.checkResult = result
                        self?.dispatchGroup.leave() // notify connection check result
                    }
                }
            }
        }
    }

    // MARK: - IP querying

    func notifyStartQuerying(ip address: KronosInternetAddress, numberOfSamples: Int) {
        queue.async {
            self.statsByIP[address]?.connectionStart = Date()
        }
    }

    func notifyReceivePacket(from address: KronosInternetAddress, isValidSample: Bool) {
        queue.async {
            if isValidSample {
                self.statsByIP[address]?.succeededPacketsCount += 1
            } else {
                self.statsByIP[address]?.failedPacketsCount += 1
            }
        }
    }

    func notifyEndQuerying(ip address: KronosInternetAddress) {
        queue.async {
            self.statsByIP[address]?.connectionEnd = Date()
        }
    }

    // MARK: - Exporting telemetry to Internal Monitoring

    private func sendTelemetryToDatadog() {
        guard let sdkLogger = exporter?.sdkLogger else {
            return // cannot happen
        }

        guard let pool = self.pool else {
            sdkLogger.debug("Kronos pool was not registered in `KronosMonitor`")  // cannot happen, but log it for sanity
            return
        }

        var ips: [String: SyncResult.IP] = [:]
        statsByIP.forEach { address, stats in
            let key = "ip\(ips.count)"
            ips[key] = SyncResult.IP(
                address: address.host,
                connectionDuration: stats.connectionStart.flatMap { stats.connectionEnd?.timeIntervalSince($0) },
                connectionCheckResult: stats.checkResult,
                succeededPacketsCount: stats.succeededPacketsCount,
                failedPacketsCount: stats.failedPacketsCount
            )
        }

        let syncResult = SyncResult(
            pool: pool,
            serverOffset: serverOffset,
            ips: ips
        )

        let ipsFailedDueToLocalNetworkDenied = syncResult.ips.values.filter { $0.connectionCheckResult?.isLocalNetworkDenied ?? false }

        if !ipsFailedDueToLocalNetworkDenied.isEmpty {
            // Send error, as this indicates the issue reported in https://github.com/DataDog/dd-sdk-ios/issues/647.
            sdkLogger.error("Kronos sync to \(pool) was blocked on trying to connect to local network", attributes: ["sync-result": syncResult])
        } else if syncResult.serverOffset != nil {
            // Send info - everything went fine
            sdkLogger.info("Kronos resolved \(pool) with receiving server offset", attributes: ["sync-result": syncResult])
        } else {
            // Send info - something went wrong, but it could be due to network unreachability or other env factors
            sdkLogger.info("Kronos resolved \(pool) but received no server offset", attributes: ["sync-result": syncResult])
        }
    }
}

// MARK: - IPConnectionMonitor

internal struct IPConnectionCheckResult: Encodable {
    let isLocalNetworkDenied: Bool
    let details: String
}

/// Checks connection to certain IP. Not used when Internal Monitoring is disabled (by default).
/// It is only implemented to collect extra telemetry  for troubleshooting  https://github.com/DataDog/dd-sdk-ios/issues/647
internal protocol IPConnectionMonitorType {
    func checkConnection(to ip: KronosInternetAddress, resultCallback: @escaping (IPConnectionCheckResult) -> Void)
}

@available(iOS 14.2, tvOS 14.2, *)
internal class IPConnectionMonitor: IPConnectionMonitorType {
    /// Timeout for checking each connection.
    private let timeout: TimeInterval = 20

    private let queue: DispatchQueue
    private var pendingConnections: [NWConnection] = []

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func checkConnection(to ip: KronosInternetAddress, resultCallback: @escaping (IPConnectionCheckResult) -> Void) {
        guard let host = ip.host else {
            return
        }

        let connection = NWConnection(host: .init(host), port: 123, using: .udp)
        queue.async { self.pendingConnections.append(connection) }
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self else {
                return
            }

            if self.pendingConnections.contains(where: { $0 === connection }) {
                self.cancelCheck(for: connection)
            }
        }

        connection.pathUpdateHandler = { [weak self] latestPath in
            let checkResult: IPConnectionCheckResult

            switch latestPath.status {
            case .unsatisfied:
                // Here we check if the connection won't lead to reaching host in local network
                // Ref.: 'How do I use the unsatisfied reason property?'
                // https://developer.apple.com/forums/thread/663769
                switch latestPath.unsatisfiedReason {
                case .localNetworkDenied:   checkResult = .init(isLocalNetworkDenied: true, details: "unsatisfied: localNetworkDenied")
                case .notAvailable:         checkResult = .init(isLocalNetworkDenied: false, details: "unsatisfied: notAvailable")
                case .cellularDenied:       checkResult = .init(isLocalNetworkDenied: false, details: "unsatisfied: cellularDenied")
                case .wifiDenied:           checkResult = .init(isLocalNetworkDenied: false, details: "unsatisfied: wifiDenied")
                @unknown default:           checkResult = .init(isLocalNetworkDenied: false, details: "unsatisfied: unknown")
                }
            case .satisfied:                checkResult = .init(isLocalNetworkDenied: false, details: "satisfied")
            case .requiresConnection:       checkResult = .init(isLocalNetworkDenied: false, details: "requiresConnection")
            @unknown default:               checkResult = .init(isLocalNetworkDenied: false, details: "unknown")
            }

            resultCallback(checkResult)
            self?.cancelCheck(for: connection)
        }

        connection.start(queue: queue)
    }

    private func cancelCheck(for connection: NWConnection) {
        connection.cancel()
        pendingConnections = pendingConnections.filter { $0 !== connection }
    }
}

#endif
