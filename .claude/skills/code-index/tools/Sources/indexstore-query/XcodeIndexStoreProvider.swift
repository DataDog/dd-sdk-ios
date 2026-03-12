/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
 
import Foundation

// MARK: - XcodeIndexStoreProvider

/// Resolves the most recently modified DerivedData index store for an Xcode project.
///
/// Xcode writes index data under `~/Library/Developer/Xcode/DerivedData/<ProjectName>-<hash>/`:
///
/// ```
/// <project>-<hash>/
///   Index.noindex/
///     DataStore/    ← raw index store (storePath)
///     UniDB/        ← query database (dbPath)
/// ```
///
/// `UniDB` is an LMDB-backed database created by `IndexStoreDB`.  It lives alongside
/// `DataStore` inside `Index.noindex/` so that Xcode can exclude it from Spotlight and
/// Time Machine backups (`.noindex` suffix).
///
/// When a repository contains multiple Xcode projects (e.g. workspace + sub-projects),
/// this type prefers `.xcworkspace` over `.xcodeproj` and picks the entry whose
/// `DataStore` was most recently modified — i.e. the build that ran last.
struct XcodeIndexStoreProvider: IndexStoreProvider {
    /// Path to the raw index store (`DataStore`) inside DerivedData.
    let store: URL

    /// Path to the UniDB query database alongside `DataStore` inside `Index.noindex/`.
    let db: URL

    // MARK: Factory

    /// Returns a provider for `repoRoot`, or `nil` when no matching DerivedData entry
    /// exists or when no `.xcworkspace` / `.xcodeproj` is found at `repoRoot`.
    static func find(repoRoot: URL) -> XcodeIndexStoreProvider? {
        guard let store = mostRecentStore(repoRoot: repoRoot) else { return nil }
        let uniDB = store.deletingLastPathComponent().appendingPathComponent("UniDB")
        guard let db = xcindexDirectory(under: uniDB) else { return nil }
        return XcodeIndexStoreProvider(store: store, db: db)
    }

    /// Returns the first `.xcindex` directory inside `uniDB/` — the `databasePath` root
    /// that IndexStoreDB expects on Xcode 26+.
    private static func xcindexDirectory(under uniDB: URL) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: uniDB, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return nil }
        return entries.first { $0.pathExtension == "xcindex" }
    }

    // MARK: Private helpers

    /// Infers the Xcode project name from the top-level workspace or project file.
    ///
    /// Prefers `.xcworkspace` over `.xcodeproj` to match the DerivedData naming convention
    /// (Xcode names DerivedData entries after the *workspace*, not the project, when both
    /// are present).
    private static func projectName(repoRoot: URL) -> String? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: repoRoot, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return nil }
        let sorted = entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let project = sorted.first { $0.pathExtension == "xcworkspace" }
            ?? sorted.first { $0.pathExtension == "xcodeproj" }
        return project?.deletingPathExtension().lastPathComponent
    }

    /// Finds the `DataStore` path with the most recent modification date among all
    /// DerivedData entries whose name starts with `<projectName>-`.
    ///
    /// The modification date of `DataStore` itself (rather than its contents) is used as
    /// a proxy for build recency — Xcode updates the directory's mtime after each build.
    private static func mostRecentStore(repoRoot: URL) -> URL? {
        guard let projectName = projectName(repoRoot: repoRoot) else { return nil }
        let derivedData = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: derivedData,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return nil }
        return entries
            .filter { $0.lastPathComponent.hasPrefix(projectName + "-") }
            .compactMap { folder -> (URL, Date)? in
                let store = folder.appendingPathComponent("Index.noindex/DataStore")
                guard
                    FileManager.default.fileExists(atPath: store.path),
                    let date = (try? store.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                else { return nil }
                return (store, date)
            }
            .max(by: { $0.1 < $1.1 })?
            .0
    }
}
