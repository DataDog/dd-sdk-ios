/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation
import SourceKittenFramework

public struct APISurfaceError: Error, CustomStringConvertible {
    public let description: String
}

public struct APISurface {
    private let module: Module
    private let language: Language
    private let generator = Generator()
    private let printer = Printer()

    // MARK: - Initialization

    /// Creates API surface for an SPM library.
    /// - Parameters:
    ///   - libraryName: the name of Swift library for generating API surface.
    ///   - path: the path to a folder containing `Package.swift`.
    ///   - language: the language of the API surface.
    public init(spmLibraryName libraryName: String, inPath path: String, language: Language) throws {
        // Create patch folder:
        let newPath = try patchXcodebuildConfusionAndReturnNewPath(originalPath: path)

        let module = Module(
            xcodeBuildArguments: [
                "-scheme", libraryName,
                "-destination", "platform='iOS Simulator'",
                "-sdk", "iphonesimulator",
            ],
            inPath: newPath
        )

        // Delete patch folder:
        try FileManager.default.removeItem(atPath: newPath)

        guard let module = module else {
            throw APISurfaceError(description: "Failed to generate module interface with `SourceKittenFramework`.")
        }

        self.module = module
        self.language = language
    }

    // MARK: - Output

    public func print() throws -> String {
        let items = try generator.generateSurfaceItems(for: module, language: language)
        return printer.print(items: items)
    }
}

/// When a folder contains both `Package.swift` and `.xcworkspace` then `xcodebuild` gets
/// confused and instead of processing swift package, it builds the workspace. There is no option in `xcodebuild`
/// to force required behaviour, hence we patch the entire concept by copying `Package.swift` to temporary folder
/// and creating symbolic links to all source folders from original location.
private func patchXcodebuildConfusionAndReturnNewPath(originalPath: String) throws -> String {
    let fm = FileManager.default

    func tempURL() throws -> URL {
        let osTemporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let testDirectoryName = "com.datadoghq.api-surface-\(UUID().uuidString)"
        let url = osTemporaryDirectoryURL.appending(component: testDirectoryName, directoryHint: .isDirectory)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func isDirectory(url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    let source = URL(filePath: originalPath, directoryHint: .isDirectory).standardizedFileURL
    let target = try tempURL()

    let copyFrom = source.appending(component: "Package.swift")
    let copyTo = target.appending(component: "Package.swift")
    try fm.copyItem(at: copyFrom, to: copyTo)

    let folders = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [])
        .filter { isDirectory(url: $0) } // `includingPropertiesForKeys: [.isDirectoryKey]` doesn't work
        .filter { !$0.lastPathComponent.starts(with: ".") } // skip hidden
        .filter { $0.pathExtension != "xcworkspace" }

    for folder in folders {
        let linkSource = folder
        let linkLocation = target.appending(component: folder.lastPathComponent)
        try fm.createSymbolicLink(at: linkLocation, withDestinationURL: linkSource)
    }

    return target.path()
}
