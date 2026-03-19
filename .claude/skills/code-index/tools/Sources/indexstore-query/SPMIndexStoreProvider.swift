/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
 
import Foundation

// MARK: - SPMIndexStoreProvider

/// Resolves the index store produced by `swift build --enable-index-building`.
///
/// SPM writes index data under `.build/index-build/<triple>/debug/index/`:
///
/// ```
/// .build/index-build/
///   <arch>-apple-macosx/
///     debug/
///       index/
///         store/    ← raw index store (storePath)
///         db/       ← query database (dbPath)
/// ```
///
/// The architecture triple is derived at compile time via conditional compilation so that
/// the tool always resolves the correct path on both Apple Silicon and Intel Macs.
///
/// Unlike `XcodeIndexStoreProvider`, this type always returns a provider even when the
/// store has not been built yet — the `openIndex` function validates existence before
/// opening.  This makes `SPMIndexStoreProvider` a safe unconditional fallback.
struct SPMIndexStoreProvider: IndexStoreProvider {
    /// Path to the raw index store (`store`) inside `.build/index-build/`.
    let store: URL

    /// Path to the query database (`db`) alongside `store`.
    let db: URL

    // MARK: Init

    /// Creates a provider whose paths are derived from `repoRoot` and the current
    /// architecture triple.
    ///
    /// - Parameter repoRoot: The root directory of the repository (where `.build/` lives).
    init(repoRoot: URL) {
        let triple = Self.archTriple
        let base = repoRoot.appendingPathComponent(".build/index-build/\(triple)/debug/index")
        store = base.appendingPathComponent("store")
        db = base.appendingPathComponent("db")
    }

    // MARK: Private helpers

    /// The architecture-specific triple used by SPM when naming its build output directories.
    ///
    /// Only `arm64` and `x86_64` are common on macOS; other architectures fall back to
    /// `arm64-apple-macosx` which is the current default for Apple Silicon.
    private static var archTriple: String {
        #if arch(arm64)
        return "arm64-apple-macosx"
        #elseif arch(x86_64)
        return "x86_64-apple-macosx"
        #else
        return "arm64-apple-macosx"
        #endif
    }
}
