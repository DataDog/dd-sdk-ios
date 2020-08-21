/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog
import XCTest

extension RUMFeature {
    /// Mocks feature instance which performs no writes and no uploads.
    static func mockNoOp() -> RUMFeature {
        return RUMFeature(
            storage: .init(writer: NoOpFileWriter(), reader: NoOpFileReader()),
            upload: .init(uploader: NoOpDataUploadWorker()),
            configuration: .mockAny(),
            commonDependencies: .mockAny()
        )
    }

    /// Mocks the feature instance which performs uploads to `URLSession`.
    /// Use `ServerMock` to inspect and assert recorded `URLRequests`.
    static func mockWith(
        directory: Directory,
        configuration: FeaturesConfiguration.RUM = .mockAny(),
        dependencies: FeaturesCommonDependencies = .mockAny()
    ) -> RUMFeature {
        return RUMFeature(directory: directory, configuration: configuration, commonDependencies: dependencies)
    }

    /// Mocks the feature instance which performs uploads to mocked `DataUploadWorker`.
    /// Use `RUMFeature.waitAndReturnRUMEventMatchers()` to inspect and assert recorded `RUMEvents`.
    static func mockByRecordingRUMEventMatchers(
        directory: Directory,
        configuration: FeaturesConfiguration.RUM = .mockAny(),
        dependencies: FeaturesCommonDependencies = .mockAny()
    ) -> RUMFeature {
        // Get the full feature mock:
        let fullFeature: RUMFeature = .mockWith(directory: directory, dependencies: dependencies)
        let uploadWorker = DataUploadWorkerMock()
        let observedStorage = uploadWorker.observe(featureStorage: fullFeature.storage)
        // Replace by mocking the `FeatureUpload` and observing the `FatureStorage`:
        let mockedUpload = FeatureUpload(uploader: uploadWorker)
        return RUMFeature(
            storage: observedStorage,
            upload: mockedUpload,
            configuration: configuration,
            commonDependencies: dependencies
        )
    }

    // MARK: - Expecting RUMEvent Data

    static func waitAndReturnRUMEventMatchers(count: UInt, file: StaticString = #file, line: UInt = #line) throws -> [RUMEventMatcher] {
        guard let uploadWorker = RUMFeature.instance?.upload.uploader as? DataUploadWorkerMock else {
            preconditionFailure("Retrieving matchers requires that feature is mocked with `.mockByRecordingRUMEventMatchers()`")
        }
        return try uploadWorker.waitAndReturnBatchedData(count: count, file: file, line: line)
            .flatMap { batchData in try RUMEventMatcher.fromNewlineSeparatedJSONObjectsData(batchData) }
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
        return RUMEventBuilder()
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
        path: String? = nil,
        isInitialView: Bool = false
    ) -> RUMStartViewCommand {
        var command = RUMStartViewCommand(
            time: time,
            identity: identity,
            path: path,
            attributes: attributes
        )
        command.isInitialView = isInitialView
        return command
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
        actionType: RUMUserActionType = .swipe,
        name: String = .mockAny()
    ) -> RUMStartUserActionCommand {
        return RUMStartUserActionCommand(
            time: time, attributes: attributes, actionType: actionType, name: name
        )
    }
}

extension RUMStopUserActionCommand {
    static func mockAny() -> RUMStopUserActionCommand { mockWith() }

    static func mockWith(
        time: Date = Date(),
        attributes: [AttributeKey: AttributeValue] = [:],
        actionType: RUMUserActionType = .swipe,
        name: String? = nil
    ) -> RUMStopUserActionCommand {
        return RUMStopUserActionCommand(
            time: time, attributes: attributes, actionType: actionType, name: name
        )
    }
}

extension RUMAddUserActionCommand {
    static func mockAny() -> RUMAddUserActionCommand { mockWith() }

    static func mockWith(
        time: Date = Date(),
        attributes: [AttributeKey: AttributeValue] = [:],
        actionType: RUMUserActionType = .tap,
        name: String = .mockAny()
    ) -> RUMAddUserActionCommand {
        return RUMAddUserActionCommand(
            time: time, attributes: attributes, actionType: actionType, name: name
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
        userInfoProvider: RUMUserInfoProvider = RUMUserInfoProvider(userInfoProvider: .mockAny()),
        connectivityInfoProvider: RUMConnectivityInfoProvider = RUMConnectivityInfoProvider(
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock(networkConnectionInfo: nil),
            carrierInfoProvider: CarrierInfoProviderMock(carrierInfo: nil)
        ),
        eventBuilder: RUMEventBuilder = RUMEventBuilder(),
        eventOutput: RUMEventOutput = RUMEventOutputMock(),
        rumUUIDGenerator: RUMUUIDGenerator = DefaultRUMUUIDGenerator()
    ) -> RUMScopeDependencies {
        return RUMScopeDependencies(
            userInfoProvider: userInfoProvider,
            connectivityInfoProvider: connectivityInfoProvider,
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
        dependencies: RUMScopeDependencies = .mockAny(),
        samplingRate: Float = 100
    ) -> RUMApplicationScope {
        return RUMApplicationScope(
            rumApplicationID: rumApplicationID,
            dependencies: dependencies,
            samplingRate: samplingRate
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
        samplingRate: Float = 100,
        startTime: Date = .mockAny()
    ) -> RUMSessionScope {
        return RUMSessionScope(
            parent: parent,
            dependencies: dependencies,
            samplingRate: samplingRate,
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

/// Creates an instance of `UIViewController` subclass with a given name.
func createMockView(viewControllerClassName: String) -> UIViewController {
    var theClass: AnyClass! // swiftlint:disable:this implicitly_unwrapped_optional

    if let existingClass = objc_lookUpClass(viewControllerClassName) {
        theClass = existingClass
    } else {
        let newClass: AnyClass = objc_allocateClassPair(UIViewController.classForCoder(), viewControllerClassName, 0)!
        objc_registerClassPair(newClass)
        theClass = newClass
    }

    let viewController = theClass.alloc() as! UIViewController
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
        parent: RUMContextProvider = RUMContextProviderMock(),
        dependencies: RUMScopeDependencies = .mockAny(),
        identity: AnyObject = mockView,
        uri: String = .mockAny(),
        attributes: [AttributeKey: AttributeValue] = [:],
        startTime: Date = .mockAny()
    ) -> RUMViewScope {
        return RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: identity,
            uri: uri,
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
