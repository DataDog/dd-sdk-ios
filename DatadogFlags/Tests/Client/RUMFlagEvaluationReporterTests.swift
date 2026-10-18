/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import TestUtilities
@_spi(Internal)
import DatadogInternal
@_spi(Internal)
@testable import DatadogCore

@_spi(Internal)
@testable import DatadogFlags

final class RUMFlagEvaluationReporterTests: XCTestCase {
    private let featureScope = FeatureScopeMock()

    func testSendFlagEvaluation() throws {
        // Given
        let reporter = RUMFlagEvaluationReporter(featureScope: featureScope)

        // When
        reporter.sendFlagEvaluation(
            flagKey: "feature-flag",
            value: true
        )

        // Then
        let messages = featureScope.messagesSent()
        XCTAssertEqual(messages.count, 1, "Should send flag evaluation message")

        let flagEvaluation = try XCTUnwrap(messages.firstPayload as? RUMFlagEvaluationMessage)
        XCTAssertEqual(flagEvaluation.flagKey, "feature-flag")
        XCTAssertEqual(flagEvaluation.value as? Bool, true)
    }
}

#if os(iOS)
final class BuiltInFlagEvaluationCaptureTests: XCTestCase {
    private func assertNoLegacyFlagEvaluations(
        in receiver: FeatureMessageReceiverMock, file: StaticString = #file, line: UInt = #line
    ) {
        XCTAssertFalse(
            receiver.messages.contains { message in
                if case .payload(is RUMFlagEvaluationMessage) = message {
                    return true
                }
                return false
            },
            "Captured evaluation must not also dispatch an untargeted legacy payload",
            file: file,
            line: line
        )
    }

    private func core(stopAtTeardown: Bool = true) throws -> DatadogCore {
        let directory = try temporaryUniqueCoreDirectory().create()
        addTeardownBlock { try directory.delete() }
        let core = DatadogCore(
            directory: directory,
            dateProvider: SystemDateProvider(),
            initialConsent: .notGranted,
            performance: .mockAny(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: .mockAny(),
            applicationVersion: .mockAny(),
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: false
        )
        if stopAtTeardown {
            addTeardownBlock { core.stop() }
        }
        return core
    }

    private func value(_ name: String) -> RUMContextHandoff.CurrentValue {
        .init(rumContext: .mockWith(viewID: name), sceneIdentifier: "a", hasPendingUserAction: false, excludedUserActionID: nil)
    }

    func testBuiltInReporterBeforeActivationSendsOneLegacyPayload() throws {
        let core = try core()
        let receiver = FeatureMessageReceiverMock()
        core.bus.connect(receiver, forKey: "flag-test")
        let scope = core.scope(for: FlagsFeature.self)
        XCTAssertTrue(scope is RUMFlagEvaluationSending)
        RUMFlagEvaluationReporter(featureScope: scope).sendFlagEvaluation(flagKey: "off", value: true)
        core.bus.flush()
        let evaluations = receiver.messages.compactMap { message -> RUMFlagEvaluationMessage? in
            guard case let .payload(value as RUMFlagEvaluationMessage) = message else {
                return nil
            }
            return value
        }
        XCTAssertEqual(evaluations.count, 1)
        XCTAssertEqual(evaluations.first?.flagKey, "off")
        XCTAssertEqual(evaluations.first?.value as? Bool, true)
        XCTAssertFalse(receiver.messages.contains { message in
            if case .payload(is RUMCapturedFlagEvaluationMessage) = message {
                return true
            }
            return false
        })
    }

    @available(iOS 27.0, *)
    func testReadyRepositoryAndInternalEvaluationCaptureWithoutChangingClientOutputs() throws {
        let core = try core()
        let receiver = FeatureMessageReceiverMock()
        core.bus.connect(receiver, forKey: "flag-test")
        let exposure = ExposureLoggerMock()
        let evaluation = EvaluationLoggerMock()
        let assignment = FlagAssignment(
            allocationKey: "allocation", variationKey: "enabled", variation: .boolean(true), reason: "TARGETING_MATCH", doLog: true
        )
        let context = FlagsEvaluationContext.mockAny()
        let client = FlagsClient(
            repository: FlagsRepositoryMock(flagsData: .init(flags: ["normal": assignment], context: context, date: .mockAny())),
            exposureLogger: exposure,
            evaluationLogger: evaluation,
            rumFlagEvaluationReporter: RUMFlagEvaluationReporter(featureScope: core.scope(for: FlagsFeature.self))
        )
        // Both paths use a reporter/scope created before RUM activation.
        let owner = try core.activateRUMContextHandoff()
        let details = RUMContextHandoff.withValue(value("normal-view"), for: owner) {
            client.getDetails(key: "normal", defaultValue: false)
        }
        RUMContextHandoff.withValue(value("internal-view"), for: owner) {
            client.sendFlagEvaluation(key: "internal", assignment: assignment, context: context)
        }
        core.bus.flush()
        assertNoLegacyFlagEvaluations(in: receiver)
        XCTAssertEqual(details.value, true)
        XCTAssertEqual(details.variant, "enabled")
        XCTAssertEqual(details.reason, "TARGETING_MATCH")
        XCTAssertEqual(details.allocationKey, "allocation")
        XCTAssertNil(details.error)
        XCTAssertEqual(exposure.logExposureCalls.map(\.flagKey), ["normal", "internal"])
        XCTAssertEqual(evaluation.logEvaluationCalls.map(\.flagKey), ["normal", "internal"])
        XCTAssertTrue(evaluation.logEvaluationCalls.allSatisfy { $0.error == nil })
        let evaluations = receiver.messages.compactMap { message -> RUMCapturedFlagEvaluationMessage? in
            guard case let .payload(value as RUMCapturedFlagEvaluationMessage) = message else {
                return nil
            }
            return value
        }
        XCTAssertEqual(evaluations.map { $0.evaluation.flagKey }, ["normal", "internal"])
        XCTAssertEqual(evaluations.map { $0.evaluation.value as? String }, ["enabled", "enabled"])
        XCTAssertEqual(evaluations.map { $0.capture?.value.rumContext?.viewID }, ["normal-view", "internal-view"])
        XCTAssertTrue(evaluations.allSatisfy { $0.capture?.owner === owner })
    }

    @available(iOS 27.0, *)
    func testRetainedRealClientAndScopeDoNotKeepCoreAliveInEitherTrackingMode() throws {
        for activate in [false, true] {
            var sdkCore: DatadogCore? = try core(stopAtTeardown: false)
            weak var weakCore = sdkCore
            defer { weakCore?.stop() }
            let receiver = FeatureMessageReceiverMock()
            let bus = try XCTUnwrap(sdkCore).bus
            bus.connect(receiver, forKey: "retained-client-lifetime")
            let scope = try XCTUnwrap(sdkCore).scope(for: FlagsFeature.self)
            let owner = activate ? try XCTUnwrap(sdkCore).activateRUMContextHandoff() : nil
            let configuration = Flags.Configuration(trackExposures: false, trackEvaluations: false, rumIntegrationEnabled: true)
            try Flags.enableOrThrow(with: configuration, in: XCTUnwrap(sdkCore))
            let client = try XCTUnwrap(FlagsClient.create(name: "retained-lifetime", in: XCTUnwrap(sdkCore)) as? FlagsClient)
            let assignment = FlagAssignment(
                allocationKey: "allocation", variationKey: "enabled", variation: .boolean(true), reason: "TARGETING_MATCH", doLog: false
            )
            let sendBeforeRelease = {
                client.sendFlagEvaluation(key: "before-release", assignment: assignment, context: .mockAny())
            }
            if let owner {
                RUMContextHandoff.withValue(value("original-view"), for: owner, operation: sendBeforeRelease)
            } else {
                sendBeforeRelease()
            }
            sdkCore?.flush()
            let before = receiver.messages.compactMap { message -> String? in
                switch message {
                case let .payload(evaluation as RUMFlagEvaluationMessage):
                    XCTAssertFalse(activate)
                    XCTAssertEqual(evaluation.value as? String, "enabled")
                    return evaluation.flagKey
                case let .payload(captured as RUMCapturedFlagEvaluationMessage):
                    XCTAssertTrue(activate)
                    XCTAssertTrue(captured.capture?.owner === owner)
                    XCTAssertEqual(captured.capture?.value.rumContext?.viewID, "original-view")
                    XCTAssertEqual(captured.evaluation.value as? String, "enabled")
                    return captured.evaluation.flagKey
                default:
                    return nil
                }
            }
            XCTAssertEqual(before, ["before-release"])

            // Keep the real registered client, scope and bus alive while releasing Core.
            sdkCore = nil
            XCTAssertNil(weakCore)
            if let owner {
                XCTAssertFalse(owner.isValid)
            }
            client.sendFlagEvaluation(key: "after-release", assignment: assignment, context: .mockAny())
            scope.sendFlagEvaluation(.init(flagKey: "scope-after-release", value: true))
            bus.flush()
            let evaluationsAfter = receiver.messages.filter { message in
                if case .payload(is RUMFlagEvaluationMessage) = message {
                    return true
                }
                if case .payload(is RUMCapturedFlagEvaluationMessage) = message {
                    return true
                }
                return false
            }
            XCTAssertEqual(evaluationsAfter.count, 1)
            withExtendedLifetime((client, scope, bus, owner)) {}
        }
    }

    @available(iOS 27.0, *)
    func testRetainedRealClientCapturesAfterFlagsReplacementInBothActivationOrders() throws {
        for activateBeforeFlags in [false, true] {
            let core = try core()
            let receiver = FeatureMessageReceiverMock()
            core.bus.connect(receiver, forKey: "flag-test")
            let initialOwner = activateBeforeFlags ? try core.activateRUMContextHandoff() : nil
            let configuration = Flags.Configuration(trackExposures: false, trackEvaluations: false, rumIntegrationEnabled: true)
            try Flags.enableOrThrow(with: configuration, in: core)
            let originalFeature = try XCTUnwrap(core.get(feature: FlagsFeature.self))
            let retained = try XCTUnwrap(FlagsClient.create(name: "retained", in: core) as? FlagsClient)
            let owner = try initialOwner ?? core.activateRUMContextHandoff()
            // Replace the actual feature/registry without recreating the retained client.
            try Flags.enableOrThrow(with: configuration, in: core)
            let replacementFeature = try XCTUnwrap(core.get(feature: FlagsFeature.self))
            XCTAssertFalse(originalFeature.clientRegistry === replacementFeature.clientRegistry)
            let replacement = try XCTUnwrap(FlagsClient.create(name: "replacement", in: core) as? FlagsClient)
            let assignment = FlagAssignment.mockAnyBoolean(doLog: false)
            RUMContextHandoff.withValue(value("retained-view"), for: owner) {
                retained.sendFlagEvaluation(key: "retained", assignment: assignment, context: .mockAny())
            }
            RUMContextHandoff.withValue(value("replacement-view"), for: owner) {
                replacement.sendFlagEvaluation(key: "replacement", assignment: assignment, context: .mockAny())
            }
            core.bus.flush()
            assertNoLegacyFlagEvaluations(in: receiver)
            let evaluations = receiver.messages.compactMap { message -> RUMCapturedFlagEvaluationMessage? in
                guard case let .payload(value as RUMCapturedFlagEvaluationMessage) = message else {
                    return nil
                }
                return value
            }
            XCTAssertEqual(evaluations.map { $0.evaluation.flagKey }, ["retained", "replacement"])
            XCTAssertEqual(evaluations.map { $0.capture?.value.rumContext?.viewID }, ["retained-view", "replacement-view"])
            XCTAssertTrue(evaluations.allSatisfy { $0.capture?.owner === owner })
            core.stop()
        }
    }
}
#endif
