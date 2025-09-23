/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import ArgumentParser
import SourceKittenFramework

public struct GenerateCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate API surface files for given SPM library or list of libraries."
    )

    @Option(help: "Specify a library name (use this option multiple times to provide list of libraries).")
    var libraryName: [String]

    @Option(help: "The path to the folder containing `Package.swift`.")
    var path: String

    @Option(help: "The file to which the generated API surface should be written.")
    var outputFile: String

    @Option(help: "The language of the API surface to print.")
    var language: Language

    public init() {}

    public func run() throws {
        try generateAPISurface(
            libraryName: libraryName,
            path: path,
            outputFile: outputFile,
            language: language
        )
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

    @Option(help: "The temporary file to which the generated API surface should be written.")
    var outputFile: String

    @Option(help: "The language of the API surface to verify.")
    var language: Language

    @Argument(help: "Path to the reference API surface file to compare against.")
    var referencePath: String

    public init() {}

    public func run() throws {
        try generateAPISurface(
            libraryName: libraryName,
            path: path,
            outputFile: outputFile,
            language: language
        )

        // Compare the generated files with the reference files
        let diff = try compareFiles(reference: referencePath, generated: outputFile)

        if !diff.isEmpty {
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

private func generateAPISurface(
    libraryName: [String],
    path: String,
    outputFile: String,
    language: Language
) throws {
    var output = ""
    var printSeparator = false

    for library in libraryName {
        do {
            let surface = try APISurface(spmLibraryName: library, inPath: path, language: language)
            if printSeparator {
                output.append("\n")
            }

            output.append("""
            # ----------------------------------
            # API surface for \(library):
            # ----------------------------------

            """)

            output.append("\n")
            output.append(try surface.print() + "\n")

            printSeparator = true
        } catch {
            print("❌ Error generating API surface for library \(library): \(error)")
            throw error
        }
    }

    // Write the output to the specified file
    do {
        try output.write(toFile: outputFile, atomically: true, encoding: .utf8)
        print("✅ API surface written to \(outputFile)")
    } catch {
        print("❌ Error writing API surface to \(outputFile): \(error)")
        throw error
    }
}
