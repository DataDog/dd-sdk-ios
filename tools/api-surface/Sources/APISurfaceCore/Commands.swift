/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import ArgumentParser
import SourceKittenFramework

/// Internal worker command: parses a single, already-built module and writes its surface body per language.
///
/// `generate` fans out one of these per module so that parsing runs in parallel across processes (each with its own
/// sourcekitd). It is not meant to be called directly; it relies on build artifacts produced by the parent process.
public struct ParseModuleCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "parse-module",
        abstract: "Parse a single pre-built module and write its API surface body per language.",
        shouldDisplay: false
    )

    @Option(help: "The module name to parse.")
    var name: String

    @Option(help: "Path to a JSON file containing the module's compiler arguments.")
    var compilerArgsFile: String

    @Option(help: "The file to which the parsed surface body should be written (paired with `--language`).")
    var outputFile: [String]

    @Option(help: "The language of the surface body to print (paired with `--output-file`).")
    var language: [Language]

    public init() {}

    public func run() throws {
        let outputs = try zipLanguagesAndFiles(languages: language, outputFiles: outputFile)

        let data = try Data(contentsOf: URL(fileURLWithPath: compilerArgsFile))
        let compilerArguments = try JSONDecoder().decode([String].self, from: data)

        let parsed = ParsedAPISurface(moduleName: name, compilerArguments: compilerArguments)

        for output in outputs {
            let body = try parsed.print(language: output.language)
            try body.write(toFile: output.outputFile, atomically: true, encoding: .utf8)
        }
    }
}

public struct GenerateCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate API surface files for given SPM library or list of libraries."
    )

    @Option(help: "Specify a library name (use this option multiple times to provide list of libraries).")
    var libraryName: [String]

    @Option(help: "The path to the folder containing `Package.swift`.")
    var path: String

    @Option(help: "The file to which the generated API surface should be written (use once per language, paired with `--language`).")
    var outputFile: [String]

    @Option(help: "The language of the API surface to print (use once per output file, paired with `--output-file`).")
    var language: [Language]

    public init() {}

    public func run() throws {
        let outputs = try zipLanguagesAndFiles(languages: language, outputFiles: outputFile)
        try generateAPISurface(libraryName: libraryName, path: path, outputs: outputs)
    }
}

public struct VerifyCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Verify that a generated API surface matches the reference file."
    )

    @Option(help: "Specify a library name (use this option multiple times to provide a list of libraries).")
    var libraryName: [String]

    @Option(help: "The path to the folder containing `Package.swift`.")
    var path: String

    @Option(help: "The temporary file to which the generated API surface should be written (use once per language, paired with `--language`).")
    var outputFile: [String]

    @Option(help: "The language of the API surface to verify (use once per output file, paired with `--output-file`).")
    var language: [Language]

    @Option(help: "Path to the reference API surface file to compare against (use once per language, paired with `--output-file`).")
    var referenceFile: [String]

    public init() {}

    public func run() throws {
        let outputs = try zipLanguagesAndFiles(languages: language, outputFiles: outputFile)

        guard referenceFile.count == outputs.count else {
            throw ValidationError("The number of `--reference-file` options must match the number of `--output-file` options.")
        }

        try generateAPISurface(libraryName: libraryName, path: path, outputs: outputs)

        // Compare the generated files with the reference files
        var hasMismatch = false
        for (output, reference) in zip(outputs, referenceFile) {
            let diff = try compareFiles(reference: reference, generated: output.outputFile)
            if !diff.isEmpty {
                hasMismatch = true
                print("❌ API surface mismatch for \(output.language.rawValue): \(reference)")
            }
        }

        if hasMismatch {
            throw ValidationError("""
                ❌ API surface mismatch detected!
                Run `make api-surface` locally to update reference files and commit the changes.
                """)
        }

        print("✅ API surface files are up-to-date.")
    }

    private func compareFiles(reference: String, generated: String) throws -> String {
        let referenceContent = try String(contentsOfFile: reference)
        let generatedContent = try String(contentsOfFile: generated)

        return referenceContent == generatedContent ? "" : "Difference in \(reference)"
    }
}

/// A single output to produce: a language paired with the file it should be written to.
internal struct APISurfaceOutput {
    let language: Language
    let outputFile: String
}

/// Pairs `--language` options with `--output-file` options by position, validating that the counts match.
private func zipLanguagesAndFiles(languages: [Language], outputFiles: [String]) throws -> [APISurfaceOutput] {
    guard languages.count == outputFiles.count else {
        throw ValidationError("The number of `--language` options must match the number of `--output-file` options.")
    }
    guard !languages.isEmpty else {
        throw ValidationError("At least one `--language` / `--output-file` pair must be provided.")
    }
    return zip(languages, outputFiles).map { APISurfaceOutput(language: $0, outputFile: $1) }
}

/// Builds and parses every library exactly once, then writes the requested language outputs.
///
/// The pipeline runs in three phases:
/// 1. Build every module serially into one shared derived data path (so dependencies compile only once).
/// 2. Parse each module concurrently, one `parse-module` child process per module (each with its own sourcekitd).
/// 3. Print every requested language output from the parsed surfaces.
private func generateAPISurface(
    libraryName: [String],
    path: String,
    outputs: [APISurfaceOutput]
) throws {
    // Shared workspace and derived data path so common dependencies compile once and are reused across modules.
    let workspace = try PatchedPackageWorkspace(originalPath: path)
    let derivedDataPath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("com.datadoghq.api-surface-dd-\(UUID().uuidString)", isDirectory: true)
        .path
    defer { try? FileManager.default.removeItem(atPath: derivedDataPath) }

    // Phase 1 - Build each module serially into the shared derived data path.
    let buildStart = Date()
    var surfaces: [APISurface] = []
    for library in libraryName {
        do {
            let surface = try APISurface(
                spmLibraryName: library,
                workspace: workspace,
                derivedDataPath: derivedDataPath
            )
            surfaces.append(surface)
        } catch {
            print("❌ Error generating API surface for library \(library): \(error)")
            throw error
        }
    }
    logDuration("build", since: buildStart)

    // Phase 2 - Parse each module (in parallel via child processes when possible).
    let parseStart = Date()
    let languages = outputs.map(\.language)
    let bodiesByModule = try parseModules(surfaces: surfaces, languages: languages)
    logDuration("parse", since: parseStart)

    // Phase 3 - Print every requested language output from the parsed surfaces.
    for output in outputs {
        var content = ""
        var printSeparator = false

        for (index, surface) in surfaces.enumerated() {
            if printSeparator {
                content.append("\n")
            }

            content.append("""
            # ----------------------------------
            # API surface for \(surface.libraryName):
            # ----------------------------------

            """)

            content.append("\n")
            content.append((bodiesByModule[index][output.language] ?? "") + "\n")

            printSeparator = true
        }

        do {
            try content.write(toFile: output.outputFile, atomically: true, encoding: .utf8)
            print("✅ API surface written to \(output.outputFile)")
        } catch {
            print("❌ Error writing API surface to \(output.outputFile): \(error)")
            throw error
        }
    }
}

/// Parses every built module, returning per module (in input order) a map of language to its printed surface body.
///
/// Parsing runs in parallel via one `parse-module` child process per module when the running tool can re-invoke
/// itself (i.e. when launched as the `api-surface` executable). Otherwise, for example under `swift test` where the
/// host executable is the test runner, it falls back to serial, in-process parsing. We use child processes rather
/// than threads because, in our own testing, parsing modules concurrently on multiple threads in a single process
/// produced incomplete output (declarations were silently dropped); serial in-process parsing is the safe
/// single-process fallback.
private func parseModules(
    surfaces: [APISurface],
    languages: [Language]
) throws -> [[Language: String]] {
    if let executablePath = resolvedWorkerExecutablePath() {
        return try parseModulesInParallel(surfaces: surfaces, languages: languages, executablePath: executablePath)
    }
    return try parseModulesSerially(surfaces: surfaces, languages: languages)
}

/// Serial, in-process fallback for parsing modules (used when child processes can't be spawned, e.g. under tests).
private func parseModulesSerially(
    surfaces: [APISurface],
    languages: [Language]
) throws -> [[Language: String]] {
    try surfaces.map { surface in
        let parsed = ParsedAPISurface(moduleName: surface.moduleName, compilerArguments: surface.compilerArguments)
        var bodies: [Language: String] = [:]
        for language in languages where bodies[language] == nil {
            bodies[language] = try parsed.print(language: language)
        }
        return bodies
    }
}

/// Parses every built module concurrently, one `parse-module` child process per module.
private func parseModulesInParallel(
    surfaces: [APISurface],
    languages: [Language],
    executablePath: String
) throws -> [[Language: String]] {
    guard !surfaces.isEmpty else {
        return []
    }

    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("com.datadoghq.api-surface-parse-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    var results = [[Language: String]?](repeating: nil, count: surfaces.count)
    var firstError: Error?
    let lock = NSLock()
    let group = DispatchGroup()
    let maxConcurrent = max(1, min(surfaces.count, ProcessInfo.processInfo.activeProcessorCount))
    let semaphore = DispatchSemaphore(value: maxConcurrent)
    let queue = DispatchQueue(label: "com.datadoghq.api-surface.parse", attributes: .concurrent)

    for (index, surface) in surfaces.enumerated() {
        semaphore.wait()
        group.enter()
        queue.async {
            defer {
                semaphore.signal()
                group.leave()
            }
            do {
                let bodies = try runParseModuleChild(
                    executablePath: executablePath,
                    surface: surface,
                    languages: languages,
                    tempDir: tempDir,
                    index: index
                )
                lock.lock()
                results[index] = bodies
                lock.unlock()
            } catch {
                lock.lock()
                if firstError == nil { firstError = error }
                lock.unlock()
            }
        }
    }

    group.wait()

    if let firstError = firstError {
        throw firstError
    }

    return results.map { $0 ?? [:] }
}

/// Runs a single `parse-module` child process for one module and returns its printed body per language.
private func runParseModuleChild(
    executablePath: String,
    surface: APISurface,
    languages: [Language],
    tempDir: URL,
    index: Int
) throws -> [Language: String] {
    let argsFile = tempDir.appendingPathComponent("args-\(index).json")
    try JSONEncoder().encode(surface.compilerArguments).write(to: argsFile)

    var arguments = [
        "parse-module",
        "--name", surface.moduleName,
        "--compiler-args-file", argsFile.path,
    ]

    var outputFiles: [Language: URL] = [:]
    for language in languages where outputFiles[language] == nil {
        let outputFile = tempDir.appendingPathComponent("body-\(index)-\(language.rawValue)")
        outputFiles[language] = outputFile
        arguments.append(contentsOf: ["--language", language.rawValue, "--output-file", outputFile.path])
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw APISurfaceError(
            description: "Parsing module `\(surface.moduleName)` failed (exit code \(process.terminationStatus))."
        )
    }

    var bodies: [Language: String] = [:]
    for (language, outputFile) in outputFiles {
        bodies[language] = try String(contentsOf: outputFile, encoding: .utf8)
    }
    return bodies
}

/// Resolves the path to the running `api-surface` executable so it can be re-invoked as a `parse-module` child.
///
/// Returns `nil` when the host executable is not the tool itself (e.g. the `xctest` runner under `swift test`), in
/// which case parsing falls back to the serial, in-process path.
private func resolvedWorkerExecutablePath() -> String? {
    let path = Bundle.main.executablePath ?? CommandLine.arguments[0]
    return URL(fileURLWithPath: path).lastPathComponent == "api-surface" ? path : nil
}

/// Logs a phase duration to stderr, useful for profiling the build vs. parse split in CI.
private func logDuration(_ label: String, since start: Date) {
    let seconds = Date().timeIntervalSince(start)
    fputs(String(format: "⏱ api-surface %@ phase: %.1fs\n", label, seconds), stderr)
}
