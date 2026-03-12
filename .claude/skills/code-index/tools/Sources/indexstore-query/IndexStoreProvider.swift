/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
 
import Foundation

// MARK: - IndexStoreProvider

/// Abstracts the location of an index store and its associated query database.
///
/// An index store is a directory tree produced by the Swift compiler (or Xcode) that
/// contains raw unit/record data for every compiled file.  `IndexStoreDB` builds a
/// query-optimised view of that data (the *database*) the first time it opens a store.
///
/// Conforming types know how to derive `storePath` and `dbPath` from a project layout —
/// Xcode uses DerivedData, SPM uses `.build/index-build/`.
protocol IndexStoreProvider {
    /// Path to the raw index store directory (unit files and records).
    var store: URL { get }

    /// Path to the query database directory (query-optimised view over `storePath`).
    ///
    /// `IndexStoreDB` creates or reuses this directory automatically; it never needs to
    /// exist before the first call.  Xcode stores it in `Index.noindex/UniDB/` next to
    /// `DataStore`; SPM stores it in `.build/index-build/<triple>/debug/index/db/`.
    var db: URL { get }
}
