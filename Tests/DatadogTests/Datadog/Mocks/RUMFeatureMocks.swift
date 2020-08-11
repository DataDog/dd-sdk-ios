/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog
import XCTest

extension RUMFeature {
    /// Mocks feature instance which performs no writes and no uploads.
    static func mockNoOp(temporaryDirectory: Directory) -> RUMFeature {
        return RUMFeature(
            storage: .init(writer: NoOpFileWriter(), reader: NoOpFileReader()),
            upload: .init(uploader: NoOpDataUploadWorker()),
            commonDependencies: .mockAny()
        )
    }

    /// Mocks feature instance which performs uploads to given `ServerMock` with performance optimized for fast delivery in unit tests.
    static func mockWorkingFeatureWith(
        server: ServerMock,
        directory: Directory,
        configuration: Datadog.ValidConfiguration = .mockAny(),
        performance: PerformancePreset = .combining(
            storagePerformance: .writeEachObjectToNewFileAndReadAllFiles,
            uploadPerformance: .veryQuick
        ),
        mobileDevice: MobileDevice = .mockWith(
            currentBatteryStatus: {
                // Mock full battery, so it doesn't rely on battery condition for the upload
                return BatteryStatus(state: .full, level: 1, isLowPowerModeEnabled: false)
            }
        ),
        dateProvider: DateProvider = SystemDateProvider(),
        userInfoProvider: UserInfoProvider = .mockAny(),
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockWith(
            networkConnectionInfo: .mockWith(
                reachability: .yes, // so it always meets the upload condition
                availableInterfaces: [.wifi],
                supportsIPv4: true,
                supportsIPv6: true,
                isExpensive: true,
                isConstrained: false // so it always meets the upload condition
            )
        ),
        carrierInfoProvider: CarrierInfoProviderType = CarrierInfoProviderMock.mockAny()
    ) -> RUMFeature {
        let commonDependencies = FeaturesCommonDependencies(
            configuration: configuration,
            performance: performance,
            httpClient: HTTPClient(session: server.urlSession),
            mobileDevice: mobileDevice,
            dateProvider: dateProvider,
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
        return RUMFeature(
            directory: directory,
            commonDependencies: commonDependencies
        )
    }
}

// MARK: - Public API Mocks

extension RUMHTTPMethod {
    static func mockAny() -> RUMHTTPMethod { .GET }
}

extension RUMResourceKind {
    static func mockAny() -> RUMResourceKind { .image }
}

// MARK: - RUMDataModel Mocks

struct RUMDataModelMock: RUMDataModel, Equatable {
    let attribute: String
}

// MARK: - Component Mocks

extension RUMEventBuilder {
    static func mockAny() -> RUMEventBuilder {
        return mockWith()
    }

    static func mockWith(
        userInfoProvider: UserInfoProvider = .mockAny(),
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType = NetworkConnectionInfoProviderMock.mockAny(),
        carrierInfoProvider: CarrierInfoProviderType = CarrierInfoProviderMock.mockAny()
    ) -> RUMEventBuilder {
        return RUMEventBuilder(
            userInfoProvider: userInfoProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            carrierInfoProvider: carrierInfoProvider
        )
    }
}

class RUMEventOutputMock: RUMEventOutput {
    private var recordedEvents: [Any] = []

    func recordedEvents<E>(ofType type: E.Type, file: StaticString = #file, line: UInt = #line) throws -> [E] {
        return recordedEvents.compactMap { event in event as? E }
    }

    // MARK: - RUMEventOutput

    func write<DM: RUMDataModel>(rumEvent: RUMEvent<DM>) {
        recordedEvents.append(rumEvent)
    }
}

// MARK: - RUMCommand Mocks

struct RUMCommandMock: RUMCommand {
    var time = Date()
    var attributes: [AttributeKey: AttributeValue] = [:]
}

extension RUMStartViewCommand {
    static func mockAny() -> RUMStartViewCommand { mockWith() }

    static func mockWith(
        time: Date = Date(),
        attributes: [AttributeKey: AttributeValue] = [:],
        identity: AnyObject = mockView,
        isInitialView: Bool = false
    ) -> RUMStartViewCommand {
        return RUMStartViewCommand(
            time: time, attributes: attributes, identity: identity, isInitialView: isInitialView
        )
    }
}

extension RUMStopViewCommand {
    static func mockAny() -> RUMStopViewCommand { mockWith() }

    static func mockWith(
        time: Date = Date(),
        attributes: [AttributeKey: AttributeValue] = [:],
        identity: AnyObject = mockView
    ) -> RUMStopViewCommand {
        return RUMStopViewCommand(
            time: time, attributes: attributes, identity: identity
        )
    }
}

extension RUMAddCurrentViewErrorCommand {
    static func mockWithErrorObject(
        time: Date = Date(),
        error: Error = ErrorMock(),
        source: RUMErrorSource = .source,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) -> RUMAddCurrentViewErrorCommand {
        return RUMAddCurrentViewErrorCommand(
            time: time, error: error, source: source, attributes: attributes
        )
    }

    static func mockWithErrorMessage(
        time: Date = Date(),
        message: String = .mockAny(),
        source: RUMErrorSource = .source,
        stack: (file: StaticString, line: UInt)? = (file: "Foo.swift", line: 10),
        attributes: [AttributeKey: AttributeValue] = [:]
    ) -> RUMAddCurrentViewErrorCommand {
        return RUMAddCurrentViewErrorCommand(
            time: time, message: message, source: source, stack: stack, attributes: attributes
        )
    }
}

extension RUMStartResourceCommand {
    static func mockAny() -> RUMStartResourceCommand { mockWith() }

    static func mockWith(
        resourceName: String = .mockAny(),
        time: Date = Date(),
        attributes: [AttributeKey: AttributeValue] = [:],
        url: String = .mockAny(),
        httpMethod: RUMHTTPMethod = .mockAny()
    ) -> RUMStartResourceCommand {
        return RUMStartResourceCommand(
            resourceName: resourceName, time: time, attributes: attributes, url: url, httpMethod: httpMethod
        )
    }
}

extension RUMStopResourceCommand {
    static func mockAny() -> RUMStopResourceCommand { mockWith() }

    static func mockWith(
        resourceName: String = .mockAny(),
        time: Date = Date(),
        attributes: [AttributeKey: AttributeValue] = [:],
        kind: RUMResourceKind = .mockAny(),
        httpStatusCode: Int? = .mockAny(),
        size: UInt64? = .mockAny()
    ) -> RUMStopResourceCommand {
        return RUMStopResourceCommand(
            resourceName: resourceName, time: time, attributes: attributes, kind: kind, httpStatusCode: httpStatusCode, size: size
        )
    }
}

extension RUMStopResourceWithErrorCommand {
    static func mockWithErrorObject(
        resourceName: String = .mockAny(),
        time: Date = Date(),
        error: Error = ErrorMock(),
        source: RUMErrorSource = .source,
        httpStatusCode: Int? = .mockAny(),
        attributes: [AttributeKey: AttributeValue] = [:]
    ) -> RUMStopResourceWithErrorCommand {
        return RUMStopResourceWithErrorCommand(
            resourceName: resourceName, time: time, error: error, source: source, httpStatusCode: httpStatusCode, attributes: attributes
        )
    }

    static func mockWithErrorMessage(
        resourceName: String = .mockAny(),
        time: Date = Date(),
        message: String = .mockAny(),
        source: RUMErrorSource = .source,
        httpStatusCode: Int? = .mockAny(),
        attributes: [AttributeKey: AttributeValue] = [:]
    ) -> RUMStopResourceWithErrorCommand {
        return RUMStopResourceWithErrorCommand(
            resourceName: resourceName, time: time, message: message, source: source, httpStatusCode: httpStatusCode, attributes: attributes
        )
    }
}

extension RUMStartUserActionCommand {
    static func mockAny() -> RUMStartUserActionCommand { mockWith() }

    static func mockWith(
        time: Date = Date(),
        attributes: [AttributeKey: AttributeValue] = [:],
        actionType: RUMUserActionType = .swipe
    ) -> RUMStartUserActionCommand {
        return RUMStartUserActionCommand(
            time: time, attributes: attributes, actionType: actionType
        )
    }
}

extension RUMStopUserActionCommand {
    static func mockAny() -> RUMStopUserActionCommand { mockWith() }

    static func mockWith(
        time: Date = Date(),
        attributes: [AttributeKey: AttributeValue] = [:],
        actionType: RUMUserActionType = .swipe
    ) -> RUMStopUserActionCommand {
        return RUMStopUserActionCommand(
            time: time, attributes: attributes, actionType: actionType
        )
    }
}

extension RUMAddUserActionCommand {
    static func mockAny() -> RUMAddUserActionCommand { mockWith() }

    static func mockWith(
        time: Date = Date(),
        attributes: [AttributeKey: AttributeValue] = [:],
        actionType: RUMUserActionType = .tap
    ) -> RUMAddUserActionCommand {
        return RUMAddUserActionCommand(
            time: time, attributes: attributes, actionType: actionType
        )
    }
}

// MARK: - RUMContext Mocks

extension RUMUUID {
    static func mockRandom() -> RUMUUID {
        return RUMUUID(rawValue: UUID())
    }
}

extension RUMContext {
    static func mockAny() -> RUMContext {
        return mockWith()
    }

    static func mockWith(
        rumApplicationID: String = .mockAny(),
        sessionID: RUMUUID = .mockRandom(),
        activeViewID: RUMUUID? = nil,
        activeViewURI: String? = nil,
        activeUserActionID: RUMUUID? = nil
    ) -> RUMContext {
        return RUMContext(
            rumApplicationID: rumApplicationID,
            sessionID: sessionID,
            activeViewID: activeViewID,
            activeViewURI: activeViewURI,
            activeUserActionID: activeUserActionID
        )
    }
}

// MARK: - RUMScope Mocks

extension RUMScopeDependencies {
    static func mockAny() -> RUMScopeDependencies {
        return mockWith()
    }

    static func mockWith(
        eventBuilder: RUMEventBuilder = RUMEventBuilder(
            userInfoProvider: .mockAny(),
            networkConnectionInfoProvider: nil,
            carrierInfoProvider: nil
        ),
        eventOutput: RUMEventOutput = RUMEventOutputMock(),
        rumUUIDGenerator: RUMUUIDGenerator = DefaultRUMUUIDGenerator()
    ) -> RUMScopeDependencies {
        return RUMScopeDependencies(
            eventBuilder: eventBuilder,
            eventOutput: eventOutput,
            rumUUIDGenerator: rumUUIDGenerator
        )
    }
}

extension RUMApplicationScope {
    static func mockAny() -> RUMApplicationScope {
        return mockWith()
    }

    static func mockWith(
        rumApplicationID: String = .mockAny(),
        dependencies: RUMScopeDependencies = .mockAny()
    ) -> RUMApplicationScope {
        return RUMApplicationScope(
            rumApplicationID: rumApplicationID,
            dependencies: dependencies
        )
    }
}

extension RUMSessionScope {
    static func mockAny() -> RUMSessionScope {
        return mockWith()
    }

    static func mockWith(
        parent: RUMApplicationScope = .mockAny(),
        dependencies: RUMScopeDependencies = .mockAny(),
        startTime: Date = .mockAny()
    ) -> RUMSessionScope {
        return RUMSessionScope(
            parent: parent,
            dependencies: dependencies,
            startTime: startTime
        )
    }
}

private let mockWindow = UIWindow(frame: .zero)

func createMockView() -> UIViewController {
    let viewController = UIViewController()
    mockWindow.rootViewController = viewController
    mockWindow.makeKeyAndVisible()
    return viewController
}

/// Holds the `mockView` object so it can be weakily referenced by `RUMViewScope` mocks.
let mockView: UIViewController = createMockView()

extension RUMViewScope {
    static func mockAny() -> RUMViewScope {
        return mockWith()
    }

    static func mockWith(
        parent: RUMSessionScope = .mockAny(),
        dependencies: RUMScopeDependencies = .mockAny(),
        identity: AnyObject = mockView,
        attributes: [AttributeKey: AttributeValue] = [:],
        startTime: Date = .mockAny()
    ) -> RUMViewScope {
        return RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: identity,
            attributes: attributes,
            startTime: startTime
        )
    }
}

class RUMContextProviderMock: RUMContextProvider {
    init(context: RUMContext = .mockAny()) {
        self.context = context
    }

    let context: RUMContext
}
