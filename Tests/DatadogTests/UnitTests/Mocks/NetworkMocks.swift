import Network
@testable import Datadog

/*
A collection of mocks for different `Network` types.
It follows the mocking conventions described in `FoundationMocks.swift`.
 */

extension NWPath.Status {
    static func mockAny() -> NWPath.Status {
        return .satisfied
    }
}

extension NWCurrentPathInfo {
    static func mockAny() -> NWCurrentPathInfo {
        return mockWith()
    }

    static func mockWith(
        availableInterfaceTypes: [NWInterface.InterfaceType] = [],
        status: NWPath.Status = .mockAny(),
        supportsIPv4: Bool = .mockAny(),
        supportsIPv6: Bool = .mockAny(),
        isExpensive: Bool = .mockAny(),
        isConstrained: Bool? = .mockAny()
    ) -> NWCurrentPathInfo {
        return NWCurrentPathInfo(
            availableInterfaceTypes: availableInterfaceTypes,
            status: status,
            supportsIPv4: supportsIPv4,
            supportsIPv6: supportsIPv6,
            isExpensive: isExpensive,
            isConstrained: isConstrained
        )
    }
}

class NWCurrentPathMonitorMock: NWCurrentPathMonitor {
    var onStart: (() -> Void)?
    var onCancel: (() -> Void)?
    let pathInfo: NWCurrentPathInfo

    init(pathInfo: NWCurrentPathInfo) {
        self.pathInfo = pathInfo
    }

    func start(queue: DispatchQueue) {
        onStart?()
    }

    func cancel() {
        onCancel?()
    }

    func currentPathInfo() -> NWCurrentPathInfo {
        return pathInfo
    }
}
