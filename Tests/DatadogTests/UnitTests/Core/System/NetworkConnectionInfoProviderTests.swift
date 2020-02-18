import XCTest
import Network
@testable import Datadog

class NetworkConnectionInfoProviderTests: XCTestCase {
    func testItStartsAndCancelsNWPathMonitor() {
        let startExpectation = self.expectation(description: "call start")
        let cancelExpectation = self.expectation(description: "call cancel")

        let monitor = NWCurrentPathMonitorMock(pathInfo: .mockAny())
        monitor.onStart = { startExpectation.fulfill() }
        monitor.onCancel = { cancelExpectation.fulfill() }

        autoreleasepool {
            _ = NetworkConnectionInfoProvider(monitor: monitor) // `start()` when initialized
            wait(for: [startExpectation], timeout: 1)
        } // `cancel()` when deinitialized

        wait(for: [cancelExpectation], timeout: 1)
    }

    func testItReturnsCurrentNetworkConnectionInfo() {
        func networkConnectionInfo(for pathInfo: NWCurrentPathInfo) -> NetworkConnectionInfo {
            let monitor = NWCurrentPathMonitorMock(pathInfo: pathInfo)
            let provider = NetworkConnectionInfoProvider(monitor: monitor)
            return provider.current
        }

        // It maps `availableInterfaceTypes` info from `Network` domain to `Datadog`
        XCTAssertEqual(
            networkConnectionInfo(for: .mockWith(availableInterfaceTypes: [.wifi, .wiredEthernet, .cellular, .loopback, .other])).availableInterfaces,
            [.wifi, .wiredEthernet, .cellular, .loopback, .other]
        )

        // It maps reachability info
        XCTAssertEqual(networkConnectionInfo(for: .mockWith(status: .satisfied)).reachability, .yes)
        XCTAssertEqual(networkConnectionInfo(for: .mockWith(status: .requiresConnection)).reachability, .maybe)
        XCTAssertEqual(networkConnectionInfo(for: .mockWith(status: .unsatisfied)).reachability, .no)

        // It maps other info
        XCTAssertTrue(networkConnectionInfo(for: .mockWith(supportsIPv4: true)).supportsIPv4)
        XCTAssertFalse(networkConnectionInfo(for: .mockWith(supportsIPv4: false)).supportsIPv4)
        XCTAssertTrue(networkConnectionInfo(for: .mockWith(supportsIPv6: true)).supportsIPv6)
        XCTAssertFalse(networkConnectionInfo(for: .mockWith(supportsIPv6: false)).supportsIPv6)
        XCTAssertTrue(networkConnectionInfo(for: .mockWith(isExpensive: true)).isExpensive)
        XCTAssertFalse(networkConnectionInfo(for: .mockWith(isExpensive: false)).isExpensive)
        // swiftlint:disable xct_specific_matcher
        XCTAssertEqual(networkConnectionInfo(for: .mockWith(isConstrained: true)).isConstrained, true)
        XCTAssertEqual(networkConnectionInfo(for: .mockWith(isConstrained: false)).isConstrained, false)
        XCTAssertEqual(networkConnectionInfo(for: .mockWith(isConstrained: nil)).isConstrained, nil)
        // swiftlint:enable xct_specific_matcher
    }
}
