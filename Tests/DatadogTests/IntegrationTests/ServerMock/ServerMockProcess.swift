/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

#if os(macOS) && DD_SDK_DEVELOPMENT
/// Process running the mock server.
class ServerMockProcess {
    /// Process running python server.
    private let process: Process

    /// Launches and runs server process until `ServerMockProcess` is deallocated.
    static func runUntilDeallocated() -> ServerMockProcess {
        let process = Process()
        process.launchPath = "/usr/bin/python"
        process.arguments = [serverScriptPath()]
        process.launch()
        return ServerMockProcess(runningProcess: process)
    }

    private init(runningProcess: Process) {
        self.process = runningProcess
    }

    deinit {
        process.terminate()
    }

    /// Resolves the url to the Python script starting the server.
    private static func serverScriptPath() -> String {
        return resolveSwiftPackageFolder().path + "/tools/server-mock/run-server-mock.py"
    }

    /// Resolves the url to the folder containing `Package.swift`
    private static func resolveSwiftPackageFolder() -> URL {
        var currentFolder = URL(fileURLWithPath: #file).deletingLastPathComponent()

        while currentFolder.pathComponents.count > 0 {
            if FileManager.default.fileExists(atPath: currentFolder.appendingPathComponent("Package.swift").path) {
                return currentFolder
            } else {
                currentFolder.deleteLastPathComponent()
            }
        }

        fatalError("Cannot resolve the URL to folder containing `Package.swif`.")
    }
}
#endif
