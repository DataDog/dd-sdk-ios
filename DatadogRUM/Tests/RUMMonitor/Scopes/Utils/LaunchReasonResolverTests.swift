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
    private let threshold = LaunchReasonResolver.Constants.launchWindowThreshold
    private lazy var resolver = LaunchReasonResolver(launchWindowThreshold: threshold)
    private let writer = FileWriterMock()

    private var baseLaunchInfo: LaunchInfo {
        .mockWith(launchReason: .uncertain, processLaunchDate: Date())
    }

    // MARK: - Helper

    /// Sends each command through the resolver, collects the contexts when `onReady` is called,
    /// and asserts that the launch reason is the same for all. Returns that reason.
    private func resolveAndValidate(
        context: DatadogContext,
        commands: [RUMCommand],
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> LaunchReason {
        var received: [(RUMCommand, DatadogContext)] = []

        for command in commands {
            resolver.deferUntilLaunchReasonResolved(command: command,context: context, writer: writer) { cmd, ctx, _ in
                received.append((cmd, ctx))
            }
        }

        XCTAssertEqual(received.count, commands.count, "Should forward all commands", file: file, line: line)
        let reason = try XCTUnwrap(received.first?.1.launchInfo.launchReason, file: file, line: line)
        for (index, (cmd, ctx)) in received.enumerated() {
            DDAssertReflectionEqual(cmd, commands[index], "Forwarded command[\(index)] must match original", file: file, line: line)
            XCTAssertEqual(ctx.launchInfo.launchReason, reason, "All contexts must share the same launchReason", file: file, line: line)
        }
        return reason
    }

    // MARK: - User Launch

    func testUserLaunch_resolvesUserLaunchForSceneDelegateFlow() throws {
        let context: DatadogContext = .mockWith(
            launchInfo: baseLaunchInfo,
            applicationStateHistory: .mockWith(
                initialState: .background,
                date: baseLaunchInfo.processLaunchDate
            )
        )
        let commands: [RUMCommand] = [
            RUMCommandMock(time: baseLaunchInfo.processLaunchDate + 0.2 * threshold),
            RUMCommandMock(time: baseLaunchInfo.processLaunchDate + 0.5 * threshold),
            RUMHandleAppLifecycleEventCommand(
                time: baseLaunchInfo.processLaunchDate + 0.8 * threshold,
                event: .willEnterForeground
            ),
            RUMCommandMock(time: baseLaunchInfo.processLaunchDate + 1.2 * threshold)
        ]

        let reason = try resolveAndValidate(context: context, commands: commands)
        XCTAssertEqual(reason, .userLaunch, "Should resolve to userLaunch after willEnterForeground")
    }

    func testUserLaunch_resolvesImmediately_whenInitialStateInactiveOrActive() throws {
        let context: DatadogContext = .mockWith(
            launchInfo: baseLaunchInfo,
            applicationStateHistory: .mockWith(
                initialState: [.inactive, .active].randomElement()!,
                date: baseLaunchInfo.processLaunchDate
            )
        )
        let commands: [RUMCommand] = [
            RUMCommandMock(time: baseLaunchInfo.processLaunchDate),
            RUMCommandMock(time: baseLaunchInfo.processLaunchDate + 0.5 * threshold)
        ]

        let reason = try resolveAndValidate(context: context, commands: commands)
        XCTAssertEqual(reason, .userLaunch, "Should resolve to userLaunch immediately when initialState is inactive or active")
    }

    // MARK: - Background Launch

    func testBackgroundLaunch_resolvesAfterThreshold() throws {
        let context: DatadogContext = .mockWith(
            launchInfo: baseLaunchInfo,
            applicationStateHistory: .mockWith(
                initialState: .background,
                date: baseLaunchInfo.processLaunchDate
            )
        )
        let commands: [RUMCommand] = [
            RUMCommandMock(time: baseLaunchInfo.processLaunchDate + 0.3 * threshold),
            RUMCommandMock(time: baseLaunchInfo.processLaunchDate + 0.6 * threshold),
            RUMCommandMock(time: baseLaunchInfo.processLaunchDate + threshold),
            RUMCommandMock(time: baseLaunchInfo.processLaunchDate + 1.5 * threshold)
        ]

        let reason = try resolveAndValidate(context: context, commands: commands)
        XCTAssertEqual(reason, .backgroundLaunch, "Should resolve to backgroundLaunch after threshold")
    }

    // MARK: - Pre-set Launch Reason

    func testPrewarmingContext_forwardsAllCommandsUnchanged() throws {
        let prewarmInfo: LaunchInfo = .mockWith(
            launchReason: .prewarming,
            processLaunchDate: baseLaunchInfo.processLaunchDate
        )
        let context: DatadogContext = .mockWith(
            launchInfo: prewarmInfo,
            applicationStateHistory: .mockWith(
                initialState: .background,
                date: baseLaunchInfo.processLaunchDate
            )
        )
        let commands: [RUMCommand] = [
            RUMCommandMock(time: baseLaunchInfo.processLaunchDate + 0.1 * threshold),
            RUMCommandMock(time: baseLaunchInfo.processLaunchDate + 0.5 * threshold),
            RUMCommandMock(time: baseLaunchInfo.processLaunchDate + threshold)
        ]

        let reason = try resolveAndValidate(context: context, commands: commands)
        XCTAssertEqual(reason, .prewarming, "Should leave launchReason as prewarming for prewarm context")
    }
}
