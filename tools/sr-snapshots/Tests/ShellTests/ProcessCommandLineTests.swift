/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Shell

class ShellCommandTests: XCTestCase {
    private let cli = ProcessCommandLine()

    func testWhenCommandPrintsToStandardOutputAndExitsWith0() throws {
        let output = try cli.shell("echo 'STDOUT foo' && exit 0")
        XCTAssertEqual(output, "STDOUT foo")
    }

    func testWhenCommandPrintsToStandardErrorAndExitsWith0() throws {
        let output = try cli.shell("echo 'STDERR foo' 1>&2 && exit 0")
        XCTAssertEqual(output, "STDERR foo")
    }

    func testWhenCommandPrintsToBothOutputsAndExitsWith0() throws {
        let output = try cli.shell("echo 'STDERR foo' 1>&2 && echo 'STDOUT foo' && exit 0")
        XCTAssertEqual(output, "STDOUT foo")
    }

    func testWhenCommandExitsWithOtherCode() throws {
        XCTAssertThrowsError(try cli.shell("echo 'STDERR foo' 1>&2 && echo 'STDOUT foo' && exit 1")) { error in
            // swiftlint:disable trailing_whitespace
            XCTAssertEqual(
                (error as? CommandError)?.description,
                """
                status: 1
                output: STDOUT foo
                error: STDERR foo
                """
            )
            // swiftlint:enable trailing_whitespace
        }
    }

    func testCallingMultipleCommandsFromDifferentThreads() throws {
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            let output = try? cli.shell("echo 'STDOUT foo' && exit 0")
            XCTAssertEqual(output, "STDOUT foo")
        }
    }
}
