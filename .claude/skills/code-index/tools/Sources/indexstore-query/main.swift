/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
 
import ArgumentParser
import Foundation
import IndexStoreDB

// MARK: - Path resolution

/// Resolves the best available index store provider for `repoRoot`.
///
/// Resolution order:
/// 1. **Xcode DerivedData** — preferred because it reflects the last full build and is
///    kept in sync by Xcode automatically.  Returns `nil` when no matching DerivedData
///    entry exists (e.g. when running in CI without Xcode).
/// 2. **SPM `.build/index-build/`** — fallback for command-line / CI workflows where
///    `swift build --enable-index-store` has been run.
///
/// - Parameter repoRoot: The root directory of the repository.
/// - Returns: A concrete provider, never fails (SPM path is always derivable).
func resolve(repoRoot: URL) -> any IndexStoreProvider {
    XcodeIndexStoreProvider.find(repoRoot: repoRoot) ?? SPMIndexStoreProvider(repoRoot: repoRoot)
}

// MARK: - libIndexStore helper

/// Locates `libIndexStore.dylib` relative to the active Xcode toolchain's `sourcekit-lsp`.
///
/// `libIndexStore.dylib` is the C library that understands the raw index store format.
/// `IndexStoreDB` wraps it via `IndexStoreLibrary`.  The dylib ships with Xcode's toolchain
/// and lives at `<toolchain>/usr/lib/libIndexStore.dylib`, two directories above
/// `sourcekit-lsp` in `<toolchain>/usr/bin/`.
///
/// - Throws: `IndexStoreError.indexNotFound` when `xcrun` cannot locate `sourcekit-lsp` or the
///   dylib is absent at the derived path.
func libIndexStorePath() throws -> String {
    let result = try shell("xcrun --find sourcekit-lsp")
    // libIndexStore.dylib lives two directories above sourcekit-lsp:
    //   <toolchain>/usr/bin/sourcekit-lsp  →  ../..  →  <toolchain>/usr/
    let lspURL = URL(fileURLWithPath: result.trimmingCharacters(in: .whitespacesAndNewlines))
    let libURL = lspURL
        .deletingLastPathComponent()        // removes sourcekit-lsp → …/bin
        .deletingLastPathComponent()        // removes bin/           → …/usr
        .appendingPathComponent("lib/libIndexStore.dylib")
    guard FileManager.default.fileExists(atPath: libURL.path) else {
        throw IndexStoreError.indexNotFound("libIndexStore.dylib not found at \(libURL.path)")
    }
    return libURL.path
}

// MARK: - Shell helper

/// Runs `command` in a `/bin/zsh` subprocess and returns its standard output.
///
/// - Parameter command: A shell command string passed to `zsh -c`.
/// - Returns: The trimmed standard output of the command.
/// - Throws: `IndexStoreError.queryFailed` when the process exits with a non-zero status.
@discardableResult
func shell(_ command: String) throws -> String {
    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", command]
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detail = errMsg.isEmpty ? "" : ": \(errMsg)"
        throw IndexStoreError.queryFailed("command exited with status \(process.terminationStatus): \(command)\(detail)")
    }
    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

// MARK: - Error

/// Errors thrown by the `indexstore` tool.
enum IndexStoreError: Error, CustomStringConvertible {
    /// The index store or a required file does not exist at the expected path.
    case indexNotFound(String)
    /// An index query or subprocess command failed.
    case queryFailed(String)

    var description: String {
        switch self {
        case .indexNotFound(let msg): return "Index not found: \(msg). Build in Xcode (⌘B) or run `swift build --enable-index-store`."
        case .queryFailed(let msg): return "Query failed: \(msg)"
        }
    }
}

// MARK: - JSON output

/// A relation to another symbol, emitted alongside the occurrence that carries it.
struct RelationResult: Codable {
    /// The role that describes how the related symbol relates to the occurrence's symbol
    /// (e.g. `calledBy`, `childOf`, `baseOf`).
    let roles: String
    let name: String
    let kind: String
    let usr: String
}

/// A single symbol occurrence serialised to JSON by the subcommands.
struct SymbolResult: Codable {
    let name: String
    let kind: String
    let usr: String
    let language: String
    /// `swift` or `clang` — the compiler that produced this index record.
    let provider: String
    let module: String
    let path: String
    let line: Int
    let column: Int
    /// Optional symbol properties (e.g. `local`, `swiftAsync`, `unitTest`, `protocolInterface`, `generic`).
    /// `nil` when the symbol has no notable properties.
    let properties: [String]?
    /// Relations carried by this occurrence (e.g. which type calls this method, which protocol
    /// this type conforms to).  `nil` when there are no relations.
    let relations: [RelationResult]?
}

/// A plain file path result used by subcommands that return file paths rather than symbols.
struct FileResult: Codable {
    let path: String
}

/// Encodes `value` as pretty-printed, key-sorted JSON and returns it as a `String`.
func jsonOutput<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    return String(data: data, encoding: .utf8) ?? "[]"
}

// MARK: - Shared helpers

/// Extracts notable properties from `symbol` into an array of human-readable strings.
///
/// Returns `nil` instead of an empty array so that the JSON key is omitted entirely
/// when the symbol has no notable properties.
func symbolProperties(_ symbol: Symbol) -> [String]? {
    var props: [String] = []
    if symbol.properties.contains(.local) { props.append("local") }
    if symbol.properties.contains(.swiftAsync) { props.append("swiftAsync") }
    if symbol.properties.contains(.unitTest) { props.append("unitTest") }
    if symbol.properties.contains(.protocolInterface) { props.append("protocolInterface") }
    if symbol.properties.contains(.generic) { props.append("generic") }
    return props.isEmpty ? nil : props
}

/// Converts the relations on a `SymbolOccurrence` into `RelationResult` values for JSON output.
///
/// Returns `nil` instead of an empty array so that the JSON key is omitted entirely
/// when there are no relations.
func occurrenceRelations(_ occ: SymbolOccurrence) -> [RelationResult]? {
    let results = occ.relations.map { rel in
        RelationResult(
            roles: "\(rel.roles)",
            name: rel.symbol.name,
            kind: "\(rel.symbol.kind)",
            usr: rel.symbol.usr
        )
    }
    return results.isEmpty ? nil : results
}

/// Converts a `SymbolOccurrence` into a `SymbolResult` ready for JSON serialisation.
func makeResult(_ occ: SymbolOccurrence) -> SymbolResult {
    SymbolResult(
        name: occ.symbol.name,
        kind: "\(occ.symbol.kind)",
        usr: occ.symbol.usr,
        language: "\(occ.symbol.language)",
        provider: "\(occ.symbolProvider)",
        module: occ.location.moduleName,
        path: occ.location.path,
        line: occ.location.line,
        column: occ.location.utf8Column,
        properties: symbolProperties(occ.symbol),
        relations: occurrenceRelations(occ)
    )
}

/// Opens the index store at `path` (defaults to the current directory) and returns the
/// repo root together with a ready-to-query `IndexStoreDB`.
///
/// Resolution order for the store location:
/// 1. Xcode DerivedData (preferred — reflects the most recent Xcode build)
/// 2. SPM `.build/index-build/` (fallback for CI / command-line builds)
///
/// The database is opened with `readonly: true` so that multiple concurrent tool
/// invocations can share the same LMDB environment without write-lock contention.
///
/// - Parameter path: Optional explicit repo root path.
/// - Returns: A tuple of the resolved repo root URL and an initialised `IndexStoreDB`.
/// - Throws: `IndexStoreError.indexNotFound` when the store directory does not exist, or any
///   error propagated from `IndexStoreDB` initialisation.
func openIndex(path: String? = nil) throws -> (root: URL, index: IndexStoreDB) {
    let root = URL(fileURLWithPath: path ?? FileManager.default.currentDirectoryPath)
    let provider = resolve(repoRoot: root)
    let libPath = try libIndexStorePath()

    guard FileManager.default.fileExists(atPath: provider.store.path) else {
        throw IndexStoreError.indexNotFound("Store not found at \(provider.store.path)")
    }

    let lib = try IndexStoreLibrary(dylibPath: libPath)
    let index = try IndexStoreDB(
        storePath: provider.store.path,
        databasePath: provider.db.path,
        library: lib,
        waitUntilDoneInitializing: true,
        readonly: false
    )
    return (root, index)
}

// MARK: - Root command

/// Shared options inherited by every subcommand via `@OptionGroup`.
struct GlobalOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "Path to the repository root (defaults to current directory).")
    var path: String?
}

/// The root `ArgumentParser` command.  All index queries are exposed as subcommands.
struct IndexStoreTool: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "indexstore",
        abstract: "Query the Swift index store for symbol information.",
        subcommands: [
            Find.self,
            Search.self,
            Usages.self,
            Declarations.self,
            Callers.self,
            Conformers.self,
            Extends.self,
            Overrides.self,
            Accessors.self,
            Specializations.self,
            Children.self,
            ReceivedBy.self,
            IBTypes.self,
            UnitTests.self,
            AllTests.self,
            FileSymbols.self,
            MainFiles.self,
            Units.self,
            Includes.self,
            IncludedBy.self,
            UnitIncludes.self,
            ModuleSymbols.self,
        ]
    )
}

// MARK: - Subcommands

extension IndexStoreTool {

    /// Finds symbol definitions by exact name, then augments the results with fuzzy /
    /// subsequence matches.  Duplicates (same USR) are deduplicated before output.
    struct Find: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Find symbol definitions by name (exact + fuzzy)."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Symbol name to search for.")
        var name: String

        func run() throws {
            let (_, index) = try openIndex(path: globals.path)

            let exactOccurrences = index.canonicalOccurrences(ofName: name)
            let fuzzyOccurrences = index.canonicalOccurrences(
                containing: name,
                anchorStart: false,
                anchorEnd: false,
                subsequence: true,
                ignoreCase: true
            )

            let results = (exactOccurrences + fuzzyOccurrences)
                .filter { $0.roles.contains(.definition) }
                .reduce(into: [String: SymbolOccurrence]()) { dict, occ in
                    if dict[occ.symbol.usr] == nil { dict[occ.symbol.usr] = occ }
                }
                .values
                .sorted()
                .map(makeResult)

            print(try jsonOutput(results))
        }
    }

    /// Performs a fuzzy subsequence search across all symbol names in the index.
    struct Search: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Fuzzy/subsequence search across all symbol names."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Pattern to search for.")
        var pattern: String

        func run() throws {
            let (_, index) = try openIndex(path: globals.path)

            var seen = Set<String>()
            var results: [SymbolResult] = []

            index.forEachCanonicalSymbolOccurrence(
                containing: pattern,
                anchorStart: false,
                anchorEnd: false,
                subsequence: true,
                ignoreCase: true
            ) { occ in
                guard occ.roles.contains(.definition), !seen.contains(occ.symbol.usr) else { return true }
                seen.insert(occ.symbol.usr)
                results.append(makeResult(occ))
                return true
            }

            print(try jsonOutput(results))
        }
    }

    /// Returns all reference occurrences of a symbol identified by its USR.
    struct Usages: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "All references to a symbol (use USR from find output)."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "USR of the symbol.")
        var usr: String

        func run() throws {
            let (_, index) = try openIndex(path: globals.path)

            let roles: SymbolRole = [.reference, .read, .write, .call, .dynamic, .addressOf]
            let results = index.occurrences(ofUSR: usr, roles: roles)
                .filter { !$0.location.isSystem }
                .sorted()
                .map(makeResult)

            print(try jsonOutput(results))
        }
    }

    /// Returns only call-site occurrences — i.e. places that call a function / method.
    struct Callers: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Only call sites — who calls this function?"
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "USR of the symbol.")
        var usr: String

        func run() throws {
            let (_, index) = try openIndex(path: globals.path)

            let results = index.occurrences(relatedToUSR: usr, roles: .calledBy)
                .filter { !$0.location.isSystem }
                .sorted()
                .map(makeResult)

            print(try jsonOutput(results))
        }
    }

    /// Returns types that conform to or inherit from a given protocol or class.
    struct Conformers: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Types conforming to / inheriting from a protocol or class."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "USR of the protocol or class.")
        var usr: String

        func run() throws {
            let (_, index) = try openIndex(path: globals.path)

            let results = index.occurrences(relatedToUSR: usr, roles: .baseOf)
                .filter { !$0.location.isSystem }
                .sorted()
                .map(makeResult)

            print(try jsonOutput(results))
        }
    }

    /// Returns types that extend a given type (Swift `extension` declarations).
    struct Extends: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Extension declarations that extend a type."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "USR of the type.")
        var usr: String

        func run() throws {
            let (_, index) = try openIndex(path: globals.path)

            let results = index.occurrences(relatedToUSR: usr, roles: .extendedBy)
                .filter { !$0.location.isSystem }
                .sorted()
                .map(makeResult)

            print(try jsonOutput(results))
        }
    }

    /// Returns methods that override a given method.
    struct Overrides: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Methods overriding this method."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "USR of the method.")
        var usr: String

        func run() throws {
            let (_, index) = try openIndex(path: globals.path)

            let results = index.occurrences(relatedToUSR: usr, roles: .overrideOf)
                .filter { !$0.location.isSystem }
                .sorted()
                .map(makeResult)

            print(try jsonOutput(results))
        }
    }

    /// Returns accessor symbols (getters/setters/observers) for a property identified by USR.
    struct Accessors: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Accessor symbols (get/set/willSet/didSet) for a property."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "USR of the property.")
        var usr: String

        func run() throws {
            let (_, index) = try openIndex(path: globals.path)

            let results = index.occurrences(relatedToUSR: usr, roles: .accessorOf)
                .filter { !$0.location.isSystem }
                .sorted()
                .map(makeResult)

            print(try jsonOutput(results))
        }
    }

    /// Lists test symbols that reference (and therefore cover) a given source file.
    struct UnitTests: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "unit-tests",
            abstract: "Test symbols that reference a source file."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Relative path to the source file from repo root.")
        var filePath: String

        func run() throws {
            let (root, index) = try openIndex(path: globals.path)
            let fullPath = root.appendingPathComponent(filePath).path

            let results = index.unitTests(referencedByMainFiles: [fullPath])
                .filter { !$0.location.isSystem }
                .sorted()
                .map(makeResult)

            print(try jsonOutput(results))
        }
    }

    /// Lists every unit test symbol in the entire index.
    struct AllTests: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "all-tests",
            abstract: "All unit test symbols in the index."
        )

        @OptionGroup var globals: GlobalOptions

        func run() throws {
            let (_, index) = try openIndex(path: globals.path)

            let results = index.unitTests()
                .filter { !$0.location.isSystem }
                .sorted()
                .map(makeResult)

            print(try jsonOutput(results))
        }
    }

    /// Lists all symbols defined in a single source file.
    struct FileSymbols: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "file-symbols",
            abstract: "All symbols defined in a file."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Relative path to the source file from repo root.")
        var filePath: String

        func run() throws {
            let (root, index) = try openIndex(path: globals.path)
            let fullPath = root.appendingPathComponent(filePath).path

            let results = index.symbolOccurrences(inFilePath: fullPath)
                .filter { $0.roles.contains(.definition) }
                .sorted()
                .map(makeResult)

            print(try jsonOutput(results))
        }
    }

    /// Returns the translation-unit (main) files that compile a given source file.
    ///
    /// Useful for understanding which targets include a shared file.
    struct MainFiles: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "main-files",
            abstract: "Translation-unit files that compile a given source file."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Relative path to the source file from repo root.")
        var filePath: String

        func run() throws {
            let (root, index) = try openIndex(path: globals.path)
            let fullPath = root.appendingPathComponent(filePath).path

            let results = index.mainFilesContainingFile(path: fullPath, crossLanguage: true)
                .sorted()
                .map { FileResult(path: $0) }

            print(try jsonOutput(results))
        }
    }

    /// Lists files that a given file `#include`s (C/Objective-C header inclusion graph).
    struct Includes: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Files #included by a given file (C/ObjC only)."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Relative path to the source file from repo root.")
        var filePath: String

        func run() throws {
            let (root, index) = try openIndex(path: globals.path)
            let fullPath = root.appendingPathComponent(filePath).path

            let results = index.filesIncludedByFile(path: fullPath)
                .sorted()
                .map { FileResult(path: $0) }

            print(try jsonOutput(results))
        }
    }

    /// Lists files that `#include` a given file (reverse header inclusion graph).
    struct IncludedBy: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "included-by",
            abstract: "Files that #include a given file (C/ObjC only)."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Relative path to the source file from repo root.")
        var filePath: String

        func run() throws {
            let (root, index) = try openIndex(path: globals.path)
            let fullPath = root.appendingPathComponent(filePath).path

            let results = index.filesIncludingFile(path: fullPath)
                .sorted()
                .map { FileResult(path: $0) }

            print(try jsonOutput(results))
        }
    }

    /// Lists compilation unit names that contain a given source file.
    ///
    /// Useful for understanding which targets / build outputs compiled a file.
    struct Units: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Compilation unit names that contain a given source file."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Relative path to the source file from repo root.")
        var filePath: String

        func run() throws {
            let (root, index) = try openIndex(path: globals.path)
            let fullPath = root.appendingPathComponent(filePath).path

            let results = index.unitNamesContainingFile(path: fullPath)
                .sorted()
                .map { FileResult(path: $0) }

            print(try jsonOutput(results))
        }
    }

    /// Lists the `#include` entries recorded for a compilation unit.
    ///
    /// Returns richer data than `includes` / `included-by`: source path, target path, and line.
    struct UnitIncludes: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "unit-includes",
            abstract: "Detailed #include entries for a compilation unit (C/ObjC only)."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Unit name (e.g. from `units` output).")
        var unitName: String

        func run() throws {
            let (_, index) = try openIndex(path: globals.path)

            struct UnitIncludeResult: Codable {
                let sourcePath: String
                let targetPath: String
                let line: Int
            }

            let results = index.includesOfUnit(unitName: unitName)
                .sorted { ($0.sourcePath, $0.line) < ($1.sourcePath, $1.line) }
                .map { UnitIncludeResult(sourcePath: $0.sourcePath, targetPath: $0.targetPath, line: $0.line) }

            print(try jsonOutput(results))
        }
    }

    /// Returns declaration occurrences of a symbol identified by its USR.
    ///
    /// Complements `usages` which filters to reference/read/write/call roles.
    struct Declarations: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Declaration occurrences of a symbol (use USR from find output)."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "USR of the symbol.")
        var usr: String

        func run() throws {
            let (_, index) = try openIndex(path: globals.path)

            let results = index.occurrences(ofUSR: usr, roles: .declaration)
                .filter { !$0.location.isSystem }
                .sorted()
                .map(makeResult)

            print(try jsonOutput(results))
        }
    }

    /// Returns specializations of a generic symbol identified by its USR.
    struct Specializations: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Specializations of a generic type or function."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "USR of the generic symbol.")
        var usr: String

        func run() throws {
            let (_, index) = try openIndex(path: globals.path)

            let results = index.occurrences(relatedToUSR: usr, roles: .specializationOf)
                .filter { !$0.location.isSystem }
                .sorted()
                .map(makeResult)

            print(try jsonOutput(results))
        }
    }

    /// Returns symbols lexically contained inside a given symbol (nesting relationships).
    struct Children: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Symbols lexically contained inside a type or function."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "USR of the containing symbol.")
        var usr: String

        func run() throws {
            let (_, index) = try openIndex(path: globals.path)

            let results = index.occurrences(relatedToUSR: usr, roles: .childOf)
                .filter { !$0.location.isSystem }
                .sorted()
                .map(makeResult)

            print(try jsonOutput(results))
        }
    }

    /// Returns ObjC method dispatch receivers for a given selector.
    struct ReceivedBy: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "received-by",
            abstract: "ObjC method dispatch receivers (receivedBy role)."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "USR of the ObjC selector.")
        var usr: String

        func run() throws {
            let (_, index) = try openIndex(path: globals.path)

            let results = index.occurrences(relatedToUSR: usr, roles: .receivedBy)
                .filter { !$0.location.isSystem }
                .sorted()
                .map(makeResult)

            print(try jsonOutput(results))
        }
    }

    /// Returns IB type relationships for a given symbol.
    struct IBTypes: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "ib-types",
            abstract: "Interface Builder type relationships (ibTypeOf role)."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "USR of the symbol.")
        var usr: String

        func run() throws {
            let (_, index) = try openIndex(path: globals.path)

            let results = index.occurrences(relatedToUSR: usr, roles: .ibTypeOf)
                .filter { !$0.location.isSystem }
                .sorted()
                .map(makeResult)

            print(try jsonOutput(results))
        }
    }

    /// Lists all symbols defined in a named Swift module.
    ///
    /// To avoid LMDB re-entrant read errors (`MDB_BAD_RSLOT`), all symbol names are
    /// collected first, then each is queried individually outside the iteration closure.
    struct ModuleSymbols: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "module-symbols",
            abstract: "All symbols in a module."
        )

        @OptionGroup var globals: GlobalOptions
        @Argument(help: "Module name.")
        var module: String

        @Option(name: .shortAndLong, help: "Maximum number of results to return (0 = unlimited).")
        var limit: Int = 0

        func run() throws {
            let (_, index) = try openIndex(path: globals.path)

            var seen = Set<String>()
            var results: [SymbolResult] = []

            // Collect all symbol names first to avoid LMDB re-entrant read (MDB_BAD_RSLOT)
            let allNames = index.allSymbolNames()
            outer: for name in allNames {
                index.forEachCanonicalSymbolOccurrence(byName: name) { occ in
                    guard occ.roles.contains(.definition),
                          occ.location.moduleName == module,
                          !seen.contains(occ.symbol.usr) else { return true }
                    seen.insert(occ.symbol.usr)
                    results.append(makeResult(occ))
                    return true
                }
                if limit > 0 && results.count >= limit { break outer }
            }

            results.sort { ($0.path, $0.line) < ($1.path, $1.line) }
            print(try jsonOutput(results))
        }
    }
}

// MARK: - Entry point

IndexStoreTool.main()
