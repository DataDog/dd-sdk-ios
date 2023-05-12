/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public struct ShellError: Error, CustomStringConvertible {
    let result: ShellResult

    public var description: String {
        return """
        status: \(result.status)
        output: \(result.output ?? "")
        error: \(result.error ?? "")
        """
    }
}

/// Result of executing shell command.
public struct ShellResult {
    /// Command's STDOUT value.
    public let output: String?
    /// Command's STDERR value.
    public let error: String?
    /// Exit code of the command.
    public let status: Int32
}

/// Executes given shell command and returns STDOUT.
/// Throws if command ends with status code other than `0`.
@discardableResult
public func shell(_ command: String) throws -> String {
    let result = try shellResult(command)
    if result.status != 0 {
        throw ShellError(result: result)
    } else if let output = result.output, !output.isEmpty {
        return output
    } else if let error = result.error, !error.isEmpty {
        return error
    } else {
        return ""
    }
}

/// Executes given shell command.
@discardableResult
public func shellResult(_ command: String) throws -> ShellResult {
    print("🐚   `\(command)`")

    let process = Process()
    process.executableURL = URL(filePath: "/bin/zsh")
    process.arguments = ["-c", command]

    let outpipe = Pipe()
    process.standardOutput = outpipe

    let errpipe = Pipe()
    process.standardError = errpipe

    try process.run()
    process.waitUntilExit()

    func sanitizedRead(fileHandle: FileHandle) -> String? {
        let charSet = CharacterSet(charactersIn: "\n\r\t")
        return String(data: fileHandle.readDataToEndOfFile(), encoding: .utf8)?
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: charSet)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
    }

    return ShellResult(
        output: sanitizedRead(fileHandle: outpipe.fileHandleForReading),
        error: sanitizedRead(fileHandle: errpipe.fileHandleForReading),
        status: process.terminationStatus
    )
}
