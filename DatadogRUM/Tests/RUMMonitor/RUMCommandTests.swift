/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
@testable import TestUtilities

class RUMCommandTests: XCTestCase {
    struct SwiftError: Error, CustomDebugStringConvertible {
        let debugDescription = "error description"
    }

    enum SwiftEnumeratedError: Error {
        case errorLabel
    }

    let nsError = NSError(
        domain: "custom-domain",
        code: 10,
        userInfo: [NSLocalizedDescriptionKey: "error description"]
    )

    func testWhenRUMAddCurrentViewErrorCommand_isBuildWithErrorObject() {
        var command = RUMAddCurrentViewErrorCommand(
            time: .mockAny(),
            error: SwiftError(),
            source: .source,
            globalAttributes: [:],
            attributes: [:],
            completionHandler: NOPCompletionHandler
        )

        XCTAssertEqual(command.type, "SwiftError")
        XCTAssertEqual(command.message, "error description")
        XCTAssertEqual(command.stack, "error description")

        command = RUMAddCurrentViewErrorCommand(
            time: .mockAny(),
            error: SwiftEnumeratedError.errorLabel,
            source: .source,
            globalAttributes: [:],
            attributes: [:],
            completionHandler: NOPCompletionHandler
        )

        XCTAssertEqual(command.type, "SwiftEnumeratedError")
        XCTAssertEqual(command.message, "errorLabel")
        XCTAssertEqual(command.stack, "errorLabel")

        command = RUMAddCurrentViewErrorCommand(
            time: .mockAny(),
            error: nsError,
            source: .source,
            globalAttributes: [:],
            attributes: [:],
            completionHandler: NOPCompletionHandler
        )

        XCTAssertEqual(command.type, "custom-domain - 10")
        XCTAssertEqual(command.message, "error description")
        XCTAssertEqual(
            command.stack,
            """
            Error Domain=custom-domain Code=10 "error description" UserInfo={NSLocalizedDescription=error description}
            """
        )
    }

    func testWhenRUMAddCurrentViewErrorCommand_isPassedErrorSourceTypeAttribute() {
        let command1: RUMAddCurrentViewErrorCommand = .mockWithErrorObject(attributes: [CrossPlatformAttributes.errorSourceType: "react-native"])

        XCTAssertEqual(command1.errorSourceType, .reactNative)
        XCTAssertTrue(command1.attributes.isEmpty)

        let command2: RUMAddCurrentViewErrorCommand = .mockWithErrorMessage(attributes: [CrossPlatformAttributes.errorSourceType: "react-native"])

        XCTAssertEqual(command2.errorSourceType, .reactNative)
        XCTAssertTrue(command2.attributes.isEmpty)

        let defaultCommand1: RUMAddCurrentViewErrorCommand = .mockWithErrorObject(attributes: [:])
        let defaultCommand2: RUMAddCurrentViewErrorCommand = .mockWithErrorMessage(attributes: [:])

        XCTAssertEqual(defaultCommand1.errorSourceType, .ios)
        XCTAssertEqual(defaultCommand2.errorSourceType, .ios)
    }

    func testWhenRUMStartViewCommand_isPassedInstrumentationTypeAttribute() {
        let flutter: RUMStartViewCommand = .mockWith(attributes: [CrossPlatformAttributes.instrumentationType: "flutter"])
        XCTAssertEqual(flutter.instrumentationType, .crossPlatform("flutter"))
        XCTAssertTrue(flutter.attributes.isEmpty)

        let anyFutureCPSDK: RUMStartViewCommand = .mockWith(attributes: [CrossPlatformAttributes.instrumentationType: "some-future-cp-sdk"])
        XCTAssertEqual(anyFutureCPSDK.instrumentationType, .crossPlatform("some-future-cp-sdk"))
        XCTAssertTrue(anyFutureCPSDK.attributes.isEmpty)

        let empty: RUMStartViewCommand = .mockWith(attributes: [CrossPlatformAttributes.instrumentationType: ""], instrumentationType: .manual)
        XCTAssertEqual(empty.instrumentationType, .manual)
        XCTAssertTrue(empty.attributes.isEmpty)

        let missing: RUMStartViewCommand = .mockWith(attributes: [:], instrumentationType: .manual)
        XCTAssertEqual(missing.instrumentationType, .manual)

        #if canImport(UIKit)
        let uikit: RUMStartViewCommand = .mockWith(attributes: [:], instrumentationType: .uikit)
        XCTAssertEqual(uikit.instrumentationType, .uikit)
        #elseif canImport(AppKit)
        let appkit: RUMStartViewCommand = .mockWith(attributes: [:], instrumentationType: .appkit)
        XCTAssertEqual(appkit.instrumentationType, .appkit)
        #endif
    }

    func testWhenRUMAddCurrentViewErrorCommand_isPassedErrorIsCrashAttribute() {
        let command1: RUMAddCurrentViewErrorCommand = .mockWithErrorObject(attributes: [CrossPlatformAttributes.errorIsCrash: true])

        XCTAssertTrue(command1.isCrash ?? false)
        XCTAssertTrue(command1.attributes.isEmpty)

        let command2: RUMAddCurrentViewErrorCommand = .mockWithErrorMessage(attributes: [CrossPlatformAttributes.errorIsCrash: false])

        XCTAssertFalse(command2.isCrash ?? true)
        XCTAssertTrue(command2.attributes.isEmpty)

        let defaultCommand1: RUMAddCurrentViewErrorCommand = .mockWithErrorObject(attributes: [:])
        let defaultCommand2: RUMAddCurrentViewErrorCommand = .mockWithErrorMessage(attributes: [:])

        XCTAssertNil(defaultCommand1.isCrash)
        XCTAssertNil(defaultCommand2.isCrash)
    }

    func testWhenRUMStopResourceWithErrorCommand_isPassedErrorSourceTypeAttribute() {
        let command1: RUMStopResourceWithErrorCommand = .mockWithErrorObject(attributes: [CrossPlatformAttributes.errorSourceType: "react-native"])

        XCTAssertEqual(command1.errorSourceType, .reactNative)
        XCTAssertTrue(command1.attributes.isEmpty)

        let command2: RUMStopResourceWithErrorCommand = .mockWithErrorMessage(attributes: [CrossPlatformAttributes.errorSourceType: "react-native"])

        XCTAssertEqual(command2.errorSourceType, .reactNative)
        XCTAssertTrue(command2.attributes.isEmpty)

        let defaultCommand1: RUMStopResourceWithErrorCommand = .mockWithErrorObject(attributes: [:])
        let defaultCommand2: RUMStopResourceWithErrorCommand = .mockWithErrorMessage(attributes: [:])

        XCTAssertEqual(defaultCommand1.errorSourceType, .ios)
        XCTAssertEqual(defaultCommand2.errorSourceType, .ios)
    }

    func testResourceWithErrorCommand_forDifferentErrorCategories() {
        let command1: RUMStopResourceWithErrorCommand = .mockWithErrorObject(error: ErrorMock(), source: .network)

        XCTAssertEqual(command1.isNetworkError, false)
        XCTAssertEqual(command1.errorSource, .network)

        let networkError = NSError(domain: NSURLErrorDomain, code: -1_001, userInfo: [:])
        let command2: RUMStopResourceWithErrorCommand = .mockWithErrorObject(error: networkError, source: .network)

        XCTAssertEqual(command2.isNetworkError, true)
        XCTAssertEqual(command2.errorSource, .network)
    }

    // MARK: - RUMAddLongTaskCommand

    /// An app state in which the OS may suspend the process.
    private var suspendableAppState: AppState {
        #if os(macOS)
        return .sleeping
        #else
        return .background
        #endif
    }

    private func trimmedDuration(time: Date, duration: TimeInterval, threshold: TimeInterval? = 0.5, history: AppStateHistory) -> TimeInterval? {
        RUMAddLongTaskCommand(time: time, attributes: [:], duration: duration, mainRunLoopThreshold: threshold)
            .trimmingAppSuspension(given: history)?
            .duration
    }

    func testWhenLongTaskMeasuredOnMainRunLoopOverlapsSuspendableAppState_itKeepsOnlyTheNotSuspendedDuration() throws {
        let t0: Date = .mockDecember15th2019At10AMUTC()
        let history: AppStateHistory = .mockWith(
            initialState: .active,
            date: t0,
            transitions: [
                (state: suspendableAppState, date: t0 + 1),
                (state: .active, date: t0 + 61)
            ]
        )

        // spanning the whole suspendable period only
        XCTAssertNil(trimmedDuration(time: t0 + 61, duration: 60, history: history))
        // spanning it with real work on both sides
        XCTAssertEqual(try XCTUnwrap(trimmedDuration(time: t0 + 63, duration: 62.5, history: history)), 2.5, accuracy: 0.001)
        // starting before it, with the not suspended part below threshold
        XCTAssertNil(trimmedDuration(time: t0 + 2, duration: 1.3, history: history))
        // ending after it, with the not suspended part at threshold
        XCTAssertEqual(try XCTUnwrap(trimmedDuration(time: t0 + 61.5, duration: 1, history: history)), 0.5, accuracy: 0.001)
        // entirely inside it
        XCTAssertNil(trimmedDuration(time: t0 + 30, duration: 1, history: history))
        // the trimmed command keeps its time
        let command = RUMAddLongTaskCommand(time: t0 + 63, attributes: [:], duration: 62.5, mainRunLoopThreshold: 0.5)
        XCTAssertEqual(command.trimmingAppSuspension(given: history)?.time, t0 + 63)
    }

    func testWhenLongTaskMeasuredOnMainRunLoopDoesNotOverlapSuspendableAppState_itIsUnchanged() {
        let t0: Date = .mockDecember15th2019At10AMUTC()
        let history: AppStateHistory = .mockWith(
            initialState: .active,
            date: t0,
            transitions: [
                (state: suspendableAppState, date: t0 + 2),
                (state: .active, date: t0 + 5)
            ]
        )

        // ending exactly when the app may start being suspended
        XCTAssertEqual(trimmedDuration(time: t0 + 2, duration: 1, history: history), 1)
        // starting exactly when the app resumes
        XCTAssertEqual(trimmedDuration(time: t0 + 6, duration: 1, history: history), 1)
        // no app state change at all
        XCTAssertEqual(trimmedDuration(time: t0 + 61.5, duration: 60, history: .mockWith(initialState: .active, date: t0)), 60)
    }

    func testWhenLongTaskMeasuredOnMainRunLoopSpansAppResume_itKeepsTheHang() throws {
        // Given: the app leaves the foreground, then the run loop iteration resuming it records `.inactive` before `.active`
        let t0: Date = .mockDecember15th2019At10AMUTC()
        let history: AppStateHistory = .mockWith(
            initialState: .active,
            date: t0,
            transitions: [
                (state: suspendableAppState, date: t0 + 1),
                (state: .inactive, date: t0 + 61),
                (state: .active, date: t0 + 61.2)
            ]
        )

        // a hang in the resuming iteration starts while the app may still be suspended
        XCTAssertEqual(try XCTUnwrap(trimmedDuration(time: t0 + 63, duration: 2.5, history: history)), 2, accuracy: 0.001)
        // the suspension itself ends in the same iteration
        XCTAssertNil(trimmedDuration(time: t0 + 61.1, duration: 60.3, history: history))
    }

    func testWhenLongTaskIsMeasuredByCallerOrHasNoDuration_itIsUnchanged() {
        let t0: Date = .mockDecember15th2019At10AMUTC()
        let history: AppStateHistory = .mockWith(
            initialState: .active,
            date: t0,
            transitions: [(state: suspendableAppState, date: t0 + 1)]
        )

        // measured by the caller (e.g. a cross-platform SDK) and reported through the API
        XCTAssertEqual(trimmedDuration(time: t0 + 61.5, duration: 60, threshold: nil, history: history), 60)
        XCTAssertEqual(
            RUMAddLongTaskCommand(time: t0 + 61.5, attributes: [:], duration: 60).trimmingAppSuspension(given: history)?.duration,
            60
        )
        // no duration to trim
        XCTAssertEqual(trimmedDuration(time: t0 + 2, duration: 0, history: history), 0)
    }
}
