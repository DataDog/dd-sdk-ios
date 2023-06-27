/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import ArgumentParser

public var printFunction: (String) -> Void = { print($0) }

public struct SPMLibrarySurfaceCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "spm",
        abstract: "Prints API surface for given SPM library or list of libraries."
    )

    @Option(help: "Specify a library name (use this option multiple times to provide list of libraries).")
    var libraryName: [String]

    @Option(help: "The path to the folder containing `Package.swift`.")
    var path: String

    public init() {}

    public func run() throws {
        var printSeparator = false
        for libraryName in libraryName {
            let surface = try APISurface(spmLibraryName: libraryName, inPath: path)
            if printSeparator {
                printFunction("\n")
            }
            printFunction("""
            # ----------------------------------
            # API surface for \(libraryName):
            # ----------------------------------

            """)
            printFunction(try surface.print())
            printSeparator = true
        }
    }
}
