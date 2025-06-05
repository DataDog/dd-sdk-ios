/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class LaunchReasonResolverTests: XCTestCase {
    private let processLaunchDate = Date()
    private let threshold = AppLaunchWindow.Constants.launchWindowThreshold
    private lazy var resolver: LaunchReasonResolver = { LaunchReasonResolver(launchWindowThreshold: threshold) }()
    private let writer = FileWriterMock()

    // MARK: - Helper

    /// Sends an array of commands through the resolver, then verifies that each forwarded context has the same `launchReason`.
    /// Returns the resolved reason.
    private func resolveAndValidate(context: DatadogContext, commands: [RUMCommand], file: StaticString = #file, line: UInt = #line) throws -> LaunchReason {
        var forwarded: [(command: RUMCommand, context: DatadogContext, writer: Writer)] = []

        for command in commands {
            resolver.forwardWithLaunchReason(command: command, context: context, writer: writer) { items in
                forwarded.append(contentsOf: items)
            }
        }

        XCTAssertEqual(forwarded.count, commands.count, "Should forward all commands", file: file, line: line)

        let launchReason = try XCTUnwrap(forwarded.first?.context.launchInfo.launchReason)

        for (index, item) in forwarded.enumerated() {
            DDAssertReflectionEqual(item.command, commands[index], "Forwarded command should match original at index \(index)", file: file, line: line)
            XCTAssertEqual(item.context.launchInfo.launchReason, launchReason, "Launch reason should be consistent", file: file, line: line)
        }

        return launchReason
    }

    // MARK: - User Launch

    func testUserLaunch_injectsUserLaunchForAllCommandsBeforeAndAfterResolution() throws {
        // Given
        let context: DatadogContext = .mockWith(
            launchInfo: .mockWith(
                launchReason: .uncertain,
                processLaunchDate: processLaunchDate
            ),
            applicationStateHistory: .mockWith(
                initialState: .background, // like in UISceneDelegate
                date: processLaunchDate
            )
        )
        let commands: [RUMCommand] = [
            RUMCommandMock(time: processLaunchDate + 0.2 * threshold),
            RUMCommandMock(time: processLaunchDate + 0.5 * threshold),
            RUMHandleAppLifecycleEventCommand(
                time: processLaunchDate + 0.8 * threshold,
                event: .willEnterForeground
            ),
            RUMCommandMock(time: processLaunchDate + 1.2 * threshold)
        ]

        // When
        let reason = try resolveAndValidate(context: context, commands: commands)

        // Then
        XCTAssertEqual(reason, .userLaunch, "Resolved reason should be userLaunch")
    }

    func testUserLaunch_initialStateInactive_resolvesImmediately() throws {
        // Given
        let context: DatadogContext = .mockWith(
            launchInfo: .mockWith(
                launchReason: .uncertain,
                processLaunchDate: processLaunchDate
            ),
            applicationStateHistory: .mockWith(
                initialState: .inactive, // like in UIApplicationDelegate
                date: processLaunchDate
            )
        )
        let commands: [RUMCommand] = [
            RUMCommandMock(time: processLaunchDate),
            RUMCommandMock(time: processLaunchDate + 0.5 * threshold)
        ]

        // When
        let reason = try resolveAndValidate(context: context, commands: commands)

        // Then
        XCTAssertEqual(reason, .userLaunch, "Resolved reason should be userLaunch for inactive start")
    }

    // MARK: - Background Launch Path

    func testBackgroundLaunch_injectsBackgroundLaunchForAllCommandsBeforeAndAfterThreshold() throws {
        // Given
        let context: DatadogContext = .mockWith(
            launchInfo: .mockWith(
                launchReason: .uncertain,
                processLaunchDate: processLaunchDate
            ),
            applicationStateHistory: .mockWith(
                initialState: .background,
                date: processLaunchDate
            )
        )
        let commands: [RUMCommand] = [
            RUMCommandMock(time: processLaunchDate + 0.3 * threshold),
            RUMCommandMock(time: processLaunchDate + 0.6 * threshold),
            RUMCommandMock(time: processLaunchDate + threshold),
            RUMCommandMock(time: processLaunchDate + 1.5 * threshold)
        ]

        // When
        let reason = try resolveAndValidate(context: context, commands: commands)

        // Then
        XCTAssertEqual(reason, .backgroundLaunch, "Resolved reason should be backgroundLaunch")
    }

    // MARK: - Pre-set Launch Reason

    func testWhenLaunchReasonAlreadySet_forwardsAllCommandsWithoutChange() throws {
        // Given
        let prewarmLaunchInfo: LaunchInfo = .mockWith(
            launchReason: .prewarming,
            processLaunchDate: processLaunchDate
        )
        let context: DatadogContext = .mockWith(
            launchInfo: prewarmLaunchInfo,
            applicationStateHistory: .mockWith(
                initialState: .background,
                date: processLaunchDate
            )
        )
        let commands: [RUMCommand] = [
            RUMCommandMock(time: processLaunchDate + 0.1 * threshold),
            RUMCommandMock(time: processLaunchDate + 0.5 * threshold),
            RUMCommandMock(time: processLaunchDate + threshold)
        ]

        // When
        let reason = try resolveAndValidate(context: context, commands: commands)

        // Then
        XCTAssertEqual(reason, .prewarming, "Resolved reason should remain prewarming")
    }
}

class AppLaunchWindowTests: XCTestCase {
    private let launchInfo: LaunchInfo = .mockWith(launchReason: .uncertain, processLaunchDate: Date())
    private let threshold = AppLaunchWindow.Constants.launchWindowThreshold
    private lazy var window: AppLaunchWindow = { AppLaunchWindow(launchWindowThreshold: threshold) }()
    private let writer = FileWriterMock()

    // MARK: - User Launch Resolution

    func testResolvesUserLaunchImmediately_whenInitialStateIsNotBackground() {
        for foregroundState in [AppState.inactive, AppState.active] {
            // Given
            let window = AppLaunchWindow(launchWindowThreshold: threshold)
            let context: DatadogContext = .mockWith(
                launchInfo: launchInfo,
                applicationStateHistory: .mockWith(
                    initialState: foregroundState,
                    date: launchInfo.processLaunchDate
                )
            )

            // When
            let command = RUMCommandMock(time: launchInfo.processLaunchDate)
            window.buffer(command: command, context: context, writer: writer)

            // Then
            XCTAssertEqual(window.resolvedReason, .userLaunch, "Initial state \(foregroundState) should resolve to userLaunch")
            DDAssertReflectionEqual(window.flushBuffer(), [(command, context, writer)], "Buffer should contain the user command")
        }
    }

    func testResolvesUserLaunch_whenWillEnterForegroundInsideWindow() {
        // Given
        let context: DatadogContext = .mockWith(
            launchInfo: launchInfo,
            applicationStateHistory: .mockWith(
                initialState: .background,
                date: launchInfo.processLaunchDate
            )
        )
        let commands: [RUMCommand] = [
            RUMCommandMock(time: launchInfo.processLaunchDate + 0.2 * threshold),
            RUMCommandMock(time: launchInfo.processLaunchDate + 0.5 * threshold)
        ]
        for cmd in commands {
            window.buffer(command: cmd, context: context, writer: writer)
            XCTAssertEqual(window.resolvedReason, .uncertain, "Within window, reason remains uncertain")
        }

        // When
        let lifecycleCommand = RUMHandleAppLifecycleEventCommand(
            time: launchInfo.processLaunchDate + 0.8 * threshold,
            event: .willEnterForeground
        )
        window.buffer(command: lifecycleCommand, context: context, writer: writer)

        // Then
        XCTAssertEqual(window.resolvedReason, .userLaunch, "willEnterForeground should resolve to userLaunch")
        let expected = (commands + [lifecycleCommand]).map { cmd in (cmd, context, writer) }
        DDAssertReflectionEqual(window.flushBuffer(), expected, "Buffer should include all commands and lifecycle")
    }

    // MARK: - Background Launch Resolution

    func testResolvesBackgroundLaunch_whenFirstCommandOutsideWindow() {
        // Given
        let context: DatadogContext = .mockWith(
            launchInfo: launchInfo,
            applicationStateHistory: .mockWith(
                initialState: .background,
                date: launchInfo.processLaunchDate
            )
        )
        let command = RUMCommandMock(time: launchInfo.processLaunchDate + threshold)

        // When
        window.buffer(command: command, context: context, writer: writer)

        // Then
        XCTAssertEqual(window.resolvedReason, .backgroundLaunch, "First command at threshold → backgroundLaunch")
        DDAssertReflectionEqual(window.flushBuffer(), [(command, context, writer)], "Buffer should contain the threshold command")
    }

    func testResolvesBackgroundLaunch_whenExceedingThresholdAfterBuffering() {
        // Given
        let context: DatadogContext = .mockWith(
            launchInfo: launchInfo,
            applicationStateHistory: .mockWith(
                initialState: .background,
                date: launchInfo.processLaunchDate
            )
        )
        let earlyCommand = RUMCommandMock(time: launchInfo.processLaunchDate + 0.3 * threshold)
        window.buffer(command: earlyCommand, context: context, writer: writer)
        XCTAssertEqual(window.resolvedReason, .uncertain, "Within window, reason remains uncertain")

        // When
        let thresholdCommand = RUMCommandMock(time: launchInfo.processLaunchDate + threshold)
        window.buffer(command: thresholdCommand, context: context, writer: writer)

        // Then
        XCTAssertEqual(window.resolvedReason, .backgroundLaunch, "Threshold command should resolve to backgroundLaunch")
        let expected = [(earlyCommand, context, writer), (thresholdCommand, context, writer)]
        DDAssertReflectionEqual(window.flushBuffer(), expected, "Buffer should contain early and threshold commands")
    }

    // MARK: - Uncertain State

    func testRemainsUncertain_ifNoLifecycleEventAndBelowThreshold() {
        // Given
        let context: DatadogContext = .mockWith(
            launchInfo: launchInfo,
            applicationStateHistory: .mockWith(
                initialState: .background,
                date: launchInfo.processLaunchDate
            )
        )
        let command = RUMCommandMock(time: launchInfo.processLaunchDate + 0.5 * threshold)

        // When
        window.buffer(command: command, context: context, writer: writer)

        // Then
        XCTAssertEqual(window.resolvedReason, .uncertain, "First command inside window should keep reason uncertain")
        DDAssertReflectionEqual(window.flushBuffer(), [(command, context, writer)], "Buffer should contain the single command")
    }

    // MARK: - Once Resolved, No Further Buffering

    func testNoFurtherBuffering_afterResolution() {
        // Given a resolved userLaunch
        let contextForeground: DatadogContext = .mockWith(
            launchInfo: launchInfo,
            applicationStateHistory: .mockWith(
                initialState: .inactive,
                date: launchInfo.processLaunchDate
            )
        )
        let firstCommand = RUMCommandMock(time: launchInfo.processLaunchDate)
        window.buffer(command: firstCommand, context: contextForeground, writer: writer)
        XCTAssertEqual(window.resolvedReason, .userLaunch, "Non-background initial state resolves to userLaunch")
        DDAssertReflectionEqual(window.flushBuffer(), [(firstCommand, contextForeground, writer)], "Buffer should contain the first command")

        // When (subsequent commands after resolution)
        let subsequentContext: DatadogContext = .mockWith(
            launchInfo: launchInfo,
            applicationStateHistory: .mockWith(
                initialState: .inactive,
                date: launchInfo.processLaunchDate
            )
        )
        let furtherCommands: [RUMCommand] = [
            RUMCommandMock(time: launchInfo.processLaunchDate + 1),
            RUMCommandMock(time: launchInfo.processLaunchDate + 2)
        ]
        for cmd in furtherCommands {
            window.buffer(command: cmd, context: subsequentContext, writer: writer)
            XCTAssertEqual(window.resolvedReason, .userLaunch, "Once resolved, reason stays userLaunch")
            XCTAssertTrue(window.flushBuffer().isEmpty, "After resolution, buffer should be empty")
        }
    }
}
