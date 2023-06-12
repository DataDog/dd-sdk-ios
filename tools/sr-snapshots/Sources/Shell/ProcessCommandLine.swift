/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public class ProcessCommandLine: CommandLine {
    private var output: [String] = []
    private var error: [String] = []

    private let notificationCenter: NotificationCenter

    public init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    @discardableResult
    public func shellResult(_ command: String) throws -> CommandLineResult {
        output = []
        error = []

        print("🐚 →   \(command)")

        let outpipe = Pipe()
        let outfh = outpipe.fileHandleForReading
        outfh.waitForDataInBackgroundAndNotify()
        notificationCenter.addObserver(self, selector: #selector(readOutput), name: NSNotification.Name.NSFileHandleDataAvailable, object: outfh)

        let errpipe = Pipe()
        let errfh = errpipe.fileHandleForReading
        errfh.waitForDataInBackgroundAndNotify()
        notificationCenter.addObserver(self, selector: #selector(readError), name: NSNotification.Name.NSFileHandleDataAvailable, object: errfh)

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        task.standardOutput = outpipe
        task.standardError = errpipe
        task.launch()
        task.waitUntilExit()

        if task.isRunning {
            fatalError()
        }

        return CommandLineResult(
            output: output.joined(separator: "\n"),
            error: error.joined(separator: "\n"),
            status: task.terminationStatus
        )
    }

    @objc
    private func readOutput(notification: Notification) {
        guard let handle = notification.object as? FileHandle else {
            return
        }

        let data = handle.availableData
        if let str = String(data: data, encoding: .utf8) {
            if let sanitized = sanitize(line: str) {
                print(sanitized)
                output.append(sanitized)
            }
        }

        handle.waitForDataInBackgroundAndNotify()
    }

    @objc
    private func readError(notification: Notification) {
        guard let handle = notification.object as? FileHandle else {
            return
        }

        let data = handle.availableData
        if let str = String(data: data, encoding: .utf8) {
            if let sanitized = sanitize(line: str) {
                print(sanitized)
                error.append(sanitized)
            }
        }
        handle.waitForDataInBackgroundAndNotify()
    }

    /// Removes new lines and trailing spaces from a string
    private func sanitize(line: String) -> String? {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 0 else {
            return nil
        }

        // replace tabs with space
        trimmed = trimmed.replacingOccurrences(of: "\t", with: " ")

        return trimmed
    }
}
