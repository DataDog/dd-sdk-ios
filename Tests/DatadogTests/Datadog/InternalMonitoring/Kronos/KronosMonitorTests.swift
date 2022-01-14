/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

private struct IPConnectionMonitorMock: IPConnectionMonitorType {
    let queue: DispatchQueue
    let results: [KronosInternetAddress: IPConnectionCheckResult]
    let resultDelay: (KronosInternetAddress) -> TimeInterval

    func checkConnection(to ip: KronosInternetAddress, resultCallback: @escaping (IPConnectionCheckResult) -> Void) {
        queue.asyncAfter(deadline: .now() + resultDelay(ip)) {
            resultCallback(results[ip]!)
        }
    }
}

class KronosMonitorTests: XCTestCase {
    private let randomNTPPool: String = .mockRandom(among: .decimalDigits) + ".ntp.org"
    private let ip1: KronosInternetAddress = .mockWith(ipString: "10.0.0.1")
    private let ip2: KronosInternetAddress = .mockWith(ipString: "10.0.0.2")
    private let ip3: KronosInternetAddress = .mockWith(ipString: "10.0.0.3")

    func testWhenNTPPoolIsResolvedToRemoteIPAddresses_andServerOffsetIsRetrieved_itChecksAllConnections_andSendsINFOLog() throws {
        let (recordedLog, recordedSyncResult) = try simulateNTPSynchronisation(
            to: randomNTPPool,
            withDNSResolvingTo: [
                ip1: .mockWith(isLocalNetworkDenied: false), // remote IP
                ip2: .mockWith(isLocalNetworkDenied: false), // remote IP
                ip3: .mockWith(isLocalNetworkDenied: false), // remote IP
            ],
            andRetrievingServerOffset: .mockRandom() // server offset retrieved
        )

        XCTAssertEqual(recordedLog.status, .info, "It must send INFO log")
        XCTAssertEqual(recordedLog.message, "Kronos resolved \(randomNTPPool) with receiving server offset")

        XCTAssertEqual(recordedSyncResult.ips.count, 3, "It must record connection status for all resolved IPs")
        XCTAssertTrue(recordedSyncResult.ips.values.contains { $0.address == ip1.host! }, "It must check connection status for \(ip1.host!)")
        XCTAssertTrue(recordedSyncResult.ips.values.contains { $0.address == ip2.host! }, "It must check connection status for \(ip2.host!)")
        XCTAssertTrue(recordedSyncResult.ips.values.contains { $0.address == ip3.host! }, "It must check connection status for \(ip3.host!)")
        XCTAssertFalse(recordedSyncResult.ips.values.contains { $0.connectionCheckResult!.isLocalNetworkDenied }, "It must report all IPs as remote")
    }

    func testWhenNTPPoolIsResolvedToRemoteIPAddresses_butServerOffsetIsNotRetrieved_itChecksAllConnections_andSendsINFOLog() throws {
        let (recordedLog, recordedSyncResult) = try simulateNTPSynchronisation(
            to: randomNTPPool,
            withDNSResolvingTo: [
                ip1: .mockWith(isLocalNetworkDenied: false), // remote IP
                ip2: .mockWith(isLocalNetworkDenied: false), // remote IP
                ip3: .mockWith(isLocalNetworkDenied: false), // remote IP
            ],
            andRetrievingServerOffset: nil // no server offset retrieved
        )

        XCTAssertEqual(recordedLog.status, .info, "It must send INFO log")
        XCTAssertEqual(recordedLog.message, "Kronos resolved \(randomNTPPool) but received no server offset")

        XCTAssertEqual(recordedSyncResult.ips.count, 3, "It must record connection status for all resolved IPs")
        XCTAssertTrue(recordedSyncResult.ips.values.contains { $0.address == ip1.host! }, "It must check connection status for \(ip1.host!)")
        XCTAssertTrue(recordedSyncResult.ips.values.contains { $0.address == ip2.host! }, "It must check connection status for \(ip2.host!)")
        XCTAssertTrue(recordedSyncResult.ips.values.contains { $0.address == ip3.host! }, "It must check connection status for \(ip3.host!)")
        XCTAssertFalse(recordedSyncResult.ips.values.contains { $0.connectionCheckResult!.isLocalNetworkDenied }, "It must report all IPs as remote")
    }

    func testWhenNTPPoolIsResolvedToLocalIPAddresses_itChecksAllConnections_andSendsERRORLog() throws {
        let (recordedLog, recordedSyncResult) = try simulateNTPSynchronisation(
            to: randomNTPPool,
            withDNSResolvingTo: [
                ip1: .mockWith(isLocalNetworkDenied: false), // remote IP
                ip2: .mockWith(isLocalNetworkDenied: false), // remote IP
                ip3: .mockWith(isLocalNetworkDenied: true),  // local IP, IRL this will trigger 'Local Network Permission'
            ],
            andRetrievingServerOffset: Bool.mockRandom() ? .mockRandom() : nil // no matter if retrieving offset
        )

        XCTAssertEqual(recordedLog.status, .error, "It must send ERROR log")
        XCTAssertEqual(recordedLog.message, "Kronos sync to \(randomNTPPool) was blocked on trying to connect to local network")

        XCTAssertEqual(recordedSyncResult.ips.count, 3, "It must record connection status for all resolved IPs")
        XCTAssertTrue(recordedSyncResult.ips.values.contains { $0.address == ip1.host! }, "It must check connection status for \(ip1.host!)")
        XCTAssertTrue(recordedSyncResult.ips.values.contains { $0.address == ip2.host! }, "It must check connection status for \(ip2.host!)")
        XCTAssertTrue(recordedSyncResult.ips.values.contains { $0.address == ip3.host! }, "It must check connection status for \(ip3.host!)")
        XCTAssertTrue(
            recordedSyncResult.ips.values.contains { $0.connectionCheckResult!.isLocalNetworkDenied } &&
            recordedSyncResult.ips.values.contains { !$0.connectionCheckResult!.isLocalNetworkDenied },
            "It must report both local and remote IPs"
        )
    }

    /// Simulates `KronosClock` execution and returns telemetry uploaded to Datadog.
    func simulateNTPSynchronisation(
        to pool: String,
        withDNSResolvingTo dnsResolution: [KronosInternetAddress: IPConnectionCheckResult],
        andRetrievingServerOffset serverOffset: TimeInterval?
    ) throws -> (log: LogEvent, syncResult: KronosInternalMonitor.SyncResult) {
        let queue = DispatchQueue(label: "kronos-monitor-tests")

        // Given
        let resolvedIPs = Array(dnsResolution.keys)
        let mockIPConnectionMonitor = IPConnectionMonitorMock(
            queue: queue,
            results: dnsResolution,
            resultDelay: { _ in .mockRandom(min: 0.1, max: 0.5) } // random delay for each connection
        )
        let mockLogOutput = LogOutputMock()
        let mockExporter = InternalMonitor(
            sdkLogger: .mockWith(logOutput: mockLogOutput)
        )

        let monitor = KronosInternalMonitor(queue: queue, connectionMonitor: mockIPConnectionMonitor)

        // When
        monitor.notifySyncStart(from: pool)
        monitor.notifyResolveDNS(to: resolvedIPs)
        resolvedIPs.forEach { ip in
            monitor.notifyStartQuerying(ip: ip, numberOfSamples: 1)
            monitor.notifyReceivePacket(from: ip, isValidSample: .mockRandom())
            monitor.notifyEndQuerying(ip: ip)
        }
        monitor.notifySyncEnd(serverOffset: serverOffset)
        monitor.export(to: mockExporter)

        // Then
        let expectation = self.expectation(description: "Send telemetry log")
        mockLogOutput.onLogRecorded = { _ in expectation.fulfill() }

        waitForExpectations(timeout: 5, handler: nil)

        let recordedLog = try XCTUnwrap(mockLogOutput.recordedLog)
        let recordedSyncResult = try XCTUnwrap(recordedLog.attributes.userAttributes["sync-result"] as? KronosInternalMonitor.SyncResult)
        return (recordedLog, recordedSyncResult)
    }
}

// MARK: - Helpers

private extension KronosInternetAddress {
    static func mockWith(ipString: String) -> KronosInternetAddress {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout.size(ofValue: addr))
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr(ipString)
        return .ipv4(addr)
    }
}

private extension IPConnectionCheckResult {
    static func mockWith(isLocalNetworkDenied: Bool) -> IPConnectionCheckResult {
        return .init(isLocalNetworkDenied: isLocalNetworkDenied, details: .mockRandom())
    }
}
