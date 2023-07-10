/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An error thrown when shell command exited with non-zero code.
public struct CommandError: Error, CustomStringConvertible {
    /// The full result of command.
    let result: CommandResult

    public var description: String {
        return """
        status: \(result.status)
        output: \(result.output ?? "")
        error: \(result.error ?? "")
        """
    }
}

/// Result of executing shell command.
public struct CommandResult {
    /// Command's STDOUT.
    public let output: String?
    /// Command's STDERR.
    public let error: String?
    /// Exit code of the command.
    public let status: Int32
}

/// Protocol for running command line commands
public protocol CommandLine {
    /// Executes given shell command.
    /// - Parameter command: The command to run.
    /// - Returns: The result of the command.
    func shellResult(_ command: String) throws -> CommandResult
}

public extension CommandLine {
    /// Executes given shell command and returns STDOUT or STDERR.
    /// Throws `ShellError` if command ends with status code other than `0`.
    /// - Parameter command: command to run
    /// - Returns: result of the command
    @discardableResult
    func shell(_ command: String) throws -> String {
        let result = try shellResult(command)
        if result.status != 0 {
            throw CommandError(result: result)
        } else if let output = result.output, !output.isEmpty {
            return output
        } else if let error = result.error, !error.isEmpty {
            return error
        } else {
            return ""
        }
    }
}
