/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class LongTaskObserverTests: XCTestCase {
    func testGivenForeground_whenTaskIsShorterThanThreshold_itDoesNotSendCommand() {
        let commands = runTasks([(duration: 0.25, isInBackground: false)])

        XCTAssertTrue(commands.isEmpty)
    }

    func testGivenForeground_whenTaskIsLongerThanThreshold_itSendsLongTaskCommand() throws {
        let startDate = Date()
        let commands = runTasks([(duration: 1, isInBackground: false)])

        XCTAssertEqual(commands.count, 1)
        let command = try XCTUnwrap(commands.first as? RUMAddLongTaskCommand)
        XCTAssertEqual(command.duration, 1, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(command.time, startDate + 1)
        XCTAssertLessThanOrEqual(command.time, Date())
        XCTAssertTrue(command.attributes.isEmpty)
    }

    func testGivenBackground_whenTaskIsShorterThanThreshold_itDoesNotSendCommand() {
        let commands = runTasks([(duration: 0.25, isInBackground: true)])

        XCTAssertTrue(commands.isEmpty)
    }

    func testGivenBackground_whenTaskIsLongerThanThreshold_itDoesNotSendCommand() {
        let commands = runTasks([(duration: 1, isInBackground: true)])

        XCTAssertTrue(commands.isEmpty)
    }

    func testGivenForeground_whenMultipleLongTasksRun_itSendsOneCommandForEachTask() throws {
        let commands = runTasks([
            (duration: 1, isInBackground: false),
            (duration: 2, isInBackground: false)
        ])

        XCTAssertEqual(commands.count, 2)
        let longTasks = commands.compactMap { $0 as? RUMAddLongTaskCommand }
        let firstTask = try XCTUnwrap(longTasks.first)
        let lastTask = try XCTUnwrap(longTasks.last)
        XCTAssertEqual(firstTask.duration, 1, accuracy: 0.1)
        XCTAssertEqual(lastTask.duration, 2, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(lastTask.time.timeIntervalSince(firstTask.time), 2)
    }

    func testWhenAppEntersBackgroundAndReturnsToForeground_itOnlyReportsLongForegroundTasks() throws {
        let commands = runTasks([
            (duration: 1, isInBackground: false),
            (duration: 2, isInBackground: true),
            (duration: 0.25, isInBackground: false),
            (duration: 1, isInBackground: false)
        ])

        XCTAssertEqual(commands.count, 2)
        let longTasks = commands.compactMap { $0 as? RUMAddLongTaskCommand }
        let firstTask = try XCTUnwrap(longTasks.first)
        let lastTask = try XCTUnwrap(longTasks.last)
        XCTAssertEqual(firstTask.duration, 1, accuracy: 0.1)
        XCTAssertEqual(lastTask.duration, 1, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(lastTask.time.timeIntervalSince(firstTask.time), 3.25)
    }

    private func runTasks(
        _ tasks: [(duration: TimeInterval, isInBackground: Bool)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [RUMCommand] {
        let completed = expectation(description: "Run loop tasks completed")
        let receivedCommands = ReadWriteLock<[RUMCommand]>(wrappedValue: [])

        let thread = Thread {
            let runLoop = RunLoop.current
            let backgroundStateProvider = LongTaskObserverBackgroundStateProviderMock()
            let subscriber = RUMCommandSubscriberMock()
            let observer = LongTaskObserver(
                threshold: 0.5,
                dateProvider: SystemDateProvider(),
                backgroundStateProvider: backgroundStateProvider,
                runLoop: runLoop
            )
            observer.publish(to: subscriber)
            observer.start()
            defer {
                observer.stop()
                receivedCommands.wrappedValue = subscriber.receivedCommands
                completed.fulfill()
            }

            for task in tasks {
                backgroundStateProvider.isInBackgroundState = task.isInBackground
                let taskCompleted = ReadWriteLock(wrappedValue: false)
                runLoop.perform(inModes: [.default]) {
                    let deadline = Date().addingTimeInterval(task.duration)
                    while Date() < deadline {}
                    taskCompleted.wrappedValue = true
                }
                runLoop.run(until: Date().addingTimeInterval(task.duration + 0.1))
                XCTAssertTrue(taskCompleted.wrappedValue, "The task must execute on the observed run loop", file: file, line: line)
            }
        }
        thread.start()
        wait(for: [completed], timeout: tasks.reduce(5) { $0 + $1.duration + 0.1 })

        return receivedCommands.wrappedValue
    }
}
