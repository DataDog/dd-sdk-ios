/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Internal)
@testable import DatadogInternal
@testable import TestUtilities
@testable import DatadogRUM

class RUMMonitorProtocol_InternalTests: XCTestCase {
    func testInternalInterfaceIsAvailableOnMonitor() {
        let monitor: RUMMonitorProtocol

        // When
        monitor = Monitor(
            dependencies: .mockAny(),
            dateProvider: SystemDateProvider()
        )

        // Then
        XCTAssertIdentical(monitor._internal?.monitor, monitor)
    }

    func testInternalInterfaceIsNotAvailableOnNOPMonitor() {
        let monitor: RUMMonitorProtocol

        // When
        monitor = NOPMonitor()

        // Then
        XCTAssertNil(monitor._internal)
    }
}

#if os(iOS)
extension RUMMonitorProtocol_InternalTests {
    private func handoff(viewID: String? = nil, scene: String? = nil) -> RUMContextHandoff.CurrentValue {
        .init(
            rumContext: viewID.map { .mockWith(viewID: $0) },
            sceneIdentifier: scene,
            hasPendingUserAction: false,
            excludedUserActionID: nil
        )
    }

    func testExecutionTarget_prefersValidViewThenSceneThenProcess() {
        let subscriber = TargetedCommandSubscriber()
        let viewID = UUID()
        let cases: [(RUMContextHandoff.CurrentValue?, RUMCommandTarget)] = [
            (handoff(viewID: viewID.uuidString, scene: "scene-a"), .view(.init(rawValue: viewID))),
            (handoff(viewID: "invalid", scene: "scene-a"), .scene(.init(rawValue: "scene-a"))),
            (handoff(scene: "scene-b"), .scene(.init(rawValue: "scene-b"))),
            (handoff(viewID: "invalid"), .processRepresentative),
            (nil, .processRepresentative)
        ]
        for (value, expected) in cases {
            subscriber.value = value
            let before = subscriber.reads
            XCTAssertEqual(subscriber.currentExecutionTarget, expected)
            XCTAssertEqual(subscriber.reads, before + 1)
        }
    }

    func testCustomSubscriber_defaultOffDoesNotReadExecutionContext() {
        let subscriber = LegacyCommandSubscriber()
        XCTAssertEqual(subscriber.currentExecutionTarget, .processRepresentative)
        XCTAssertEqual(subscriber.reads, 0)
    }

    func testInternalFamilies_captureOneInferredTargetPerCommand() throws {
        let subscriber = TargetedCommandSubscriber()
        let interface = DatadogInternalInterface(monitor: subscriber)
        let viewID = UUID()
        subscriber.value = handoff(viewID: viewID.uuidString, scene: "scene-a")
        let time = Date(timeIntervalSince1970: 1_600_000_000)
        let calls: [(DatadogInternalInterface) -> Void] = [
            { $0.addLongTask(at: time, duration: 1) },
            { $0.updatePerformanceMetric(at: time, metric: .jsFrameTimeSeconds, value: 0.01) },
            { $0.setInternalViewAttribute(at: time, key: "native", value: "attribute") },
            { $0.addAction(at: time, type: .tap, name: "native-action", heatmapAttributes: nil) }
        ]
        for call in calls {
            let before = subscriber.reads
            call(interface)
            XCTAssertEqual(subscriber.reads, before + 1)
            let command = try XCTUnwrap(subscriber.commands.last)
            XCTAssertEqual(command.target, .view(.init(rawValue: viewID)))
            XCTAssertEqual(command.time, time)
        }
        XCTAssertEqual(subscriber.commands.count, calls.count)
    }

    func testInternalError_preservesCapturedActionAbsenceWithoutLiveInference() throws {
        let subscriber = TargetedCommandSubscriber()
        subscriber.value = handoff(viewID: UUID().uuidString, scene: "other-scene")
        let interface = DatadogInternalInterface(monitor: subscriber)
        let target = RUMCommandTarget.scene(.init(rawValue: "captured-scene"))
        interface.addError(
            at: Date(),
            message: "captured",
            type: nil,
            stack: nil,
            source: .source,
            globalAttributes: [:],
            attributes: [:],
            binaryImages: nil,
            target: target,
            userActionTarget: .captured(nil)
        )
        let command = try XCTUnwrap(subscriber.commands.last as? RUMAddCurrentViewErrorCommand)
        XCTAssertEqual(command.target, target)
        XCTAssertEqual(command.userActionTarget, .captured(nil))
        XCTAssertEqual(subscriber.reads, 0)
    }

    func testManualFamilies_keepExplicitAndInferredTargetsSeparate() throws {
        let monitor = TargetedMonitorRecorder(enabled: true)
        let inferredID = UUID()
        monitor.value = handoff(viewID: inferredID.uuidString, scene: "inferred-scene")
        let explicit = RUMCommandTarget.scene(.init(rawValue: "explicit-scene"))
        let calls: [(Monitor) -> Void] = [
            { $0.addError(message: "manual", type: nil, stack: nil, source: .source, attributes: [:], file: nil, line: nil, explicitTarget: explicit) },
            { $0.addError(error: NSError(domain: "test", code: 1), source: .source, attributes: [:], explicitTarget: explicit) },
            { $0.addError(error: NSError(domain: "test", code: 1), source: .source, attributes: [:], completionHandler: {}, explicitTarget: explicit) },
            { $0.startResource(resourceKey: "request", request: URLRequest(url: URL(string: "https://example.com")!), attributes: [:], explicitTarget: explicit) },
            { $0.startResource(resourceKey: "url", url: URL(string: "https://example.com")!, attributes: [:], explicitTarget: explicit) },
            { $0.startResource(resourceKey: "method", httpMethod: .get, urlString: "https://example.com", attributes: [:], explicitTarget: explicit) },
            { $0.addAction(type: .tap, name: "tap", attributes: [:], explicitTarget: explicit) },
            { $0.startAction(type: .custom, name: "long", attributes: [:], explicitTarget: explicit) },
            { $0.stopAction(type: .custom, name: "long", attributes: [:], explicitTarget: explicit) },
            { $0.addFeatureFlagEvaluation(name: "flag", value: true, explicitTarget: explicit) },
            { $0.addViewAttribute(forKey: "one", value: 1, explicitTarget: explicit) },
            { $0.addViewAttributes(["two": 2], explicitTarget: explicit) },
            { $0.removeViewAttribute(forKey: "one", explicitTarget: explicit) },
            { $0.removeViewAttributes(forKeys: ["two"], explicitTarget: explicit) },
            { $0.addTiming(name: "timing", explicitTarget: explicit) },
            { $0.addViewLoadingTime(overwrite: false, explicitTarget: explicit) }
        ]
        let expectedTypes: [RUMCommand.Type] = [
            RUMAddCurrentViewErrorCommand.self,
            RUMAddCurrentViewErrorCommand.self,
            RUMAddCurrentViewErrorCommand.self,
            RUMStartResourceCommand.self,
            RUMStartResourceCommand.self,
            RUMStartResourceCommand.self,
            RUMAddUserActionCommand.self,
            RUMStartUserActionCommand.self,
            RUMStopUserActionCommand.self,
            RUMAddFeatureFlagEvaluationCommand.self,
            RUMAddViewAttributesCommand.self,
            RUMAddViewAttributesCommand.self,
            RUMRemoveViewAttributesCommand.self,
            RUMRemoveViewAttributesCommand.self,
            RUMAddViewTimingCommand.self,
            RUMAddViewLoadingTime.self
        ]
        XCTAssertEqual(calls.count, expectedTypes.count)
        for (call, expectedType) in zip(calls, expectedTypes) {
            let commandCount = monitor.commands.count
            let before = monitor.reads
            call(monitor)
            XCTAssertEqual(monitor.reads, before + 1)
            XCTAssertEqual(monitor.commands.count, commandCount + 1)
            let command = try XCTUnwrap(monitor.commands.last)
            XCTAssertEqual(ObjectIdentifier(type(of: command)), ObjectIdentifier(expectedType))
            XCTAssertEqual(command.target, .view(.init(rawValue: inferredID)))
            if let action = command as? RUMUserActionCommand {
                XCTAssertEqual(action.explicitTarget, explicit)
            } else {
                let targetCommand = try XCTUnwrap(command as? RUMExplicitViewTargetCommand)
                XCTAssertEqual(targetCommand.explicitTarget, explicit)
            }
        }
        XCTAssertEqual(monitor.commands.count, calls.count)
    }

    func testManualFamilies_offDiscardsExplicitTargetsWithoutInference() throws {
        let monitor = TargetedMonitorRecorder(enabled: false)
        monitor.value = handoff(viewID: UUID().uuidString, scene: "inferred-scene")
        let explicit = RUMCommandTarget.scene(.init(rawValue: "explicit-scene"))
        let calls: [(Monitor) -> Void] = [
            { $0.addAction(type: .tap, name: "tap", attributes: [:], explicitTarget: explicit) },
            { $0.addTiming(name: "timing", explicitTarget: explicit) },
            { $0.startResource(resourceKey: "resource", httpMethod: .get, urlString: "https://example.com", attributes: [:], explicitTarget: explicit) }
        ]
        let expectedTypes: [RUMCommand.Type] = [RUMAddUserActionCommand.self, RUMAddViewTimingCommand.self, RUMStartResourceCommand.self]
        XCTAssertEqual(calls.count, expectedTypes.count)
        for (call, expectedType) in zip(calls, expectedTypes) {
            let commandCount = monitor.commands.count
            call(monitor)
            XCTAssertEqual(monitor.commands.count, commandCount + 1)
            XCTAssertEqual(monitor.reads, 0)
            let command = try XCTUnwrap(monitor.commands.last)
            XCTAssertEqual(ObjectIdentifier(type(of: command)), ObjectIdentifier(expectedType))
            XCTAssertEqual(command.target, .processRepresentative)
            if let action = command as? RUMUserActionCommand {
                XCTAssertNil(action.explicitTarget)
            } else {
                let targetCommand = try XCTUnwrap(command as? RUMExplicitViewTargetCommand)
                XCTAssertNil(targetCommand.explicitTarget)
            }
        }
        XCTAssertEqual(monitor.reads, 0)
        XCTAssertEqual(monitor.commands.count, 3)
    }
}

private final class TargetedCommandSubscriber: RUMCommandSubscriber {
    var commands: [RUMCommand] = []
    var value: RUMContextHandoff.CurrentValue?
    var reads = 0
    var isMultiSceneTrackingEnabled: Bool { true }
    var currentExecutionContext: RUMContextHandoff.CurrentValue? { reads += 1; return value }
    func process(command: RUMCommand) { commands.append(command) }
}

private final class LegacyCommandSubscriber: RUMCommandSubscriber {
    var reads = 0
    var currentExecutionContext: RUMContextHandoff.CurrentValue? { reads += 1; return nil }
    func process(command: RUMCommand) {}
}

private final class TargetedMonitorRecorder: Monitor {
    var commands: [RUMCommand] = []
    var value: RUMContextHandoff.CurrentValue?
    var reads = 0
    override var currentExecutionContext: RUMContextHandoff.CurrentValue? { reads += 1; return value }
    init(enabled: Bool) {
        super.init(dependencies: .mockWith(featureFlags: [.multiSceneTracking: enabled]), dateProvider: DateProviderMock())
    }
    override func process(command: RUMCommand) { commands.append(command) }
}
#endif
