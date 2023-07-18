/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Dispatch

/// Runs a child process with capturing standard output and standard error.
///
/// Inspired by https://developer.apple.com/forums/thread/690310
public class ProcessCommandLine: CommandLine {
    public init() {}

    /// Executes given shell command.
    /// - Parameter command: The command to run.
    /// - Returns: The result of the command.
    public func shellResult(_ command: String) throws -> CommandResult {
        var result: Result<CommandResult, Error>? = nil
        let queue = DispatchQueue(label: "com.datadoghq.cli-\(UUID().uuidString)")

        print("🐚 →   \(command)")

        let semaphore = DispatchSemaphore(value: 0)
        shellWithCompletion(command, on: queue) { callbackResult in
            result = callbackResult
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .distantFuture)

        switch result! { // swiftlint:disable:this force_unwrapping
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }

    internal func shellWithCompletion(
        _ command: String,
        on queue: DispatchQueue,
        completion: @escaping (Result<CommandResult, Error>) -> Void
    ) {
        queue.async {
            let processGroup = DispatchGroup()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            var stdoutData = Data()
            var stderrData = Data()
            var posixError: Error? = nil

            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", command]
            task.standardOutput = stdoutPipe
            task.standardError = stderrPipe

            processGroup.enter()
            task.terminationHandler = { _ in
                // In case the latter `try task.run()` throws, bouncing the group leave()
                // on queue here ensures it is properly teared down.
                queue.async { processGroup.leave() }
            }

            // This runs the supplied block when all three events have completed (task
            // termination and the end of both STDOUT and STDERR reads).
            processGroup.notify(queue: queue) {
                if let error = posixError {
                    completion(.failure(error))
                } else {
                    let result = CommandResult(
                        stdoutData: stdoutData,
                        stderrData: stderrData,
                        terminationStatus: task.terminationStatus
                    )
                    completion(.success(result))
                }
            }

            do {
                func posixErr(_ error: Int32) -> Error {
                    NSError(domain: NSPOSIXErrorDomain, code: Int(error), userInfo: nil)
                }

                try task.run()

                // Enter the process group and leaver it only after STDOUT buffer is read.
                processGroup.enter()
                let stdoutFile = stdoutPipe.fileHandleForReading
                let stdoutReadIO = DispatchIO(type: .stream, fileDescriptor: stdoutFile.fileDescriptor, queue: queue) { _ in
                    try! stdoutFile.close() // swiftlint:disable:this force_try
                }
                stdoutReadIO.read(offset: 0, length: .max, queue: queue) { isDone, chunk, error in
                    stdoutData.append(contentsOf: chunk ?? .empty)
                    if isDone || error != 0 {
                        stdoutReadIO.close()
                        if posixError == nil && error != 0 { posixError = posixErr(error) }
                        processGroup.leave()
                    }
                }

                // Enter the process group and leaver it only after STDERR buffer is read.
                processGroup.enter()
                let stderrFile = stderrPipe.fileHandleForReading
                let stderrReadIO = DispatchIO(type: .stream, fileDescriptor: stderrFile.fileDescriptor, queue: queue) { _ in
                    try! stderrFile.close() // swiftlint:disable:this force_try
                }
                stderrReadIO.read(offset: 0, length: .max, queue: queue) { isDone, chunk, error in
                    stderrData.append(contentsOf: chunk ?? .empty)
                    if isDone || error != 0 {
                        stderrReadIO.close()
                        if posixError == nil && error != 0 { posixError = posixErr(error) }
                        processGroup.leave()
                    }
                }
            } catch {
                posixError = error
                // We’ve only entered the group once at this point, so the single leave done by the
                // termination handler is enough to run the notify block and call the
                // client’s completion handler.
                task.terminationHandler!(task) // swiftlint:disable:this force_unwrapping
            }
        }
    }
}

private extension CommandResult {
    init(stdoutData: Data, stderrData: Data, terminationStatus: Int32) {
        self.output = String(data: stdoutData, encoding: .utf8).flatMap(sanitize(output:))
        self.error = String(data: stderrData, encoding: .utf8).flatMap(sanitize(output:))
        self.status = terminationStatus
    }
}

/// Removes new lines and trailing spaces from a string
private func sanitize(output: String) -> String? {
    var trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > 0 else {
        return nil
    }
    trimmed = trimmed.replacingOccurrences(of: "\t", with: " ")
    return trimmed
}
