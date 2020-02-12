import Foundation
@testable import Datadog

class ServerMock {
    let url: String = "http://localhost:8000/"
    /// Directory where server saves request files.
    private let directory = obtainUniqueTemporaryDirectory()
    /// Process running python server.
    private var process: Process! // swiftlint:disable:this implicitly_unwrapped_optional

    /// Starts mock server.
    func start() {
        directory.create()
        process = Process()
        process.launchPath = "/usr/bin/python"
        process.arguments = [serverScriptPath(), directory.url.path]
        process.launch()
    }

    /// Stops mock server.
    func stop() {
        process.terminate()
        directory.delete()
    }

    /// Captures server session since `.start()` to now and passess it to verification closure.
    func verify(using verificationClosure: (ServerSession) throws -> Void) throws {
        let session = try ServerSession(recordedIn: directory)
        try verificationClosure(session)
    }

    // MARK: - Private

    private func serverScriptPath() -> String {
        return resolveSwiftPackageFolder().path + "/tools/server-mock/run-server-mock.py"
    }

    /// Resolve an url to the folder containing `Package.swift`
    private func resolveSwiftPackageFolder() -> URL {
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
