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

/// Builds a module interface for an SPM library.
///
/// Building is split from parsing so that all modules can be compiled serially into a single, shared derived data
/// path (so common dependencies such as `DatadogInternal` compile only once and each leaf module compiles once),
/// keeping the expensive SourceKit parsing as a separate, clearly-bounded step.
public struct APISurface {
    /// The name of the SPM library this surface was generated for.
    public let libraryName: String
    private let module: Module

    // MARK: - Initialization

    /// Builds the module interface for an SPM library.
    ///
    /// - Parameters:
    ///   - libraryName: the name of Swift library for generating API surface.
    ///   - workspace: the shared, patched package workspace to run `xcodebuild` from.
    ///   - derivedDataPath: the shared derived data path so `xcodebuild` reuses build artifacts across modules.
    init(spmLibraryName libraryName: String, workspace: PatchedPackageWorkspace, derivedDataPath: String) throws {
        let module = Module(
            xcodeBuildArguments: [
                "-scheme", libraryName,
                "-destination", "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest",
                "-sdk", "iphonesimulator",
                "-derivedDataPath", derivedDataPath,
            ],
            inPath: workspace.path
        )

        guard let module = module else {
            throw APISurfaceError(description: "Failed to generate module interface with `SourceKittenFramework`.")
        }

        self.libraryName = libraryName
        self.module = module
    }

    // MARK: - Parsing inputs

    /// The module name as resolved by `xcodebuild`/SourceKitten (used to reconstruct the module for parsing).
    var moduleName: String { module.name }

    /// The compiler arguments SourceKit needs to parse this module.
    ///
    /// These are captured once from the build above and can be handed to a separate `parse-module` process so the
    /// expensive SourceKit parsing runs in parallel without rebuilding (each process gets its own sourcekitd).
    var compilerArguments: [String] { module.compilerArguments }
}

/// The parsed SourceKit documentation for a single module, ready to print for any language.
///
/// Created inside a `parse-module` child process (one per module). Parsing is isolated per process rather than
/// parallelized across threads in a single process because, in our own testing, parsing modules concurrently on
/// multiple threads produced incomplete output: declarations were silently dropped (e.g. the ObjC surface shrank
/// from 3566 to 1204 lines). A fresh SourceKit state per child process avoids that.
internal struct ParsedAPISurface {
    private let docs: [SwiftDocs]

    /// Reconstructs the module from its name and compiler arguments and parses it. No build is performed here; it
    /// relies on the build artifacts already produced into the shared derived data path by the parent process.
    init(moduleName: String, compilerArguments: [String]) {
        let module = Module(name: moduleName, compilerArguments: compilerArguments)
        self.docs = module.docs
    }

    /// Prints the API surface for the given language from the already-parsed module documentation.
    func print(language: Language) throws -> String {
        // A fresh `Generator` per call keeps this method free of shared mutable state.
        let items = try Generator().generateSurfaceItems(docs: docs, language: language)
        return Printer().print(items: items)
    }
}

/// Holds a temporary patched package workspace used to run `xcodebuild` and
/// automatically removes it when no longer referenced.
internal final class PatchedPackageWorkspace {
    let path: String

    init(originalPath: String) throws {
        self.path = try Self.patchXcodebuildConfusionAndReturnNewPath(originalPath: originalPath)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// When a folder contains both `Package.swift` and `.xcworkspace` then `xcodebuild` gets
    /// confused and instead of processing swift package, it builds the workspace. There is no option in `xcodebuild`
    /// to force required behaviour, hence we patch the entire concept by copying `Package.swift` to temporary folder
    /// and creating symbolic links to all source folders from original location.
    private static func patchXcodebuildConfusionAndReturnNewPath(originalPath: String) throws -> String {
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
}
