/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct PersistenceHelpers {
    /// Deletes data directories for all features (Logging, Tracing, RUM and Crash Reporting).
    static func deleteAllSDKData() {
        do {
            try FileManager.default
                .getCacheSubdirectories()
                .filter { isFeatureDirectory($0) }
                .forEach { FileManager.default.delete($0) }
        } catch {
            print("🔥 Failed to delete SDK data directory: \(error)")
        }
    }

    /// Checks if there is a pending crash report file.
    static func hasPendingCrashReportData() -> Bool {
        do {
            guard let crashReportsDirectory = try FileManager.default
                    .getCacheSubdirectories()
                    .filter(isCrashReporterDirectory)
                    .first
            else {
                return false
            }

            return FileManager.default
                .recursivelyFindFiles(in: crashReportsDirectory)
                .contains { isCrashReportFile($0) }
        } catch {
            print("🔥 Failed to inspect crash reports directory: \(error)")
            return false
        }
    }

    // MARK: - Private

    private static func isFeatureDirectory(_ url: URL) -> Bool {
        url.absoluteString.contains("com.datadoghq")
    }

    private static func isCrashReporterDirectory(_ url: URL) -> Bool {
        url.absoluteString.contains("com.plausiblelabs")
    }

    private static func isCrashReportFile(_ url: URL) -> Bool {
        do {
            let attributes = try url.resourceValues(forKeys:[.nameKey])
            return attributes.name?.hasSuffix("plcrash") ?? false
        } catch {
            print("🔥 Failed to inspect file name: \(error)")
            return false
        }
    }
}

// MARK: - Helpers

private extension FileManager {
    /// Lists urls for subdirectories of `caches` directory
    func getCacheSubdirectories() throws -> [URL] {
        guard let cachesDirectoryURL = urls(for: .cachesDirectory, in: .userDomainMask).first else {
            fatalError("🔥 Cannot obtain \"caches\" directory URL")
        }
        return try contentsOfDirectory(
            at: cachesDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .canonicalPathKey]
        )
    }

    /// Deletes file or directory at given `url`.
    func delete(_ url: URL) {
        do {
            print("🧹 Deleting directory: \(url)")
            try FileManager.default.removeItem(at: url)
        } catch {
            print("🧹🔥 Failed: \(error)")
        }
    }

    /// Recursively finds all files in given directory `url`.
    func recursivelyFindFiles(in directoryURL: URL) -> [URL] {
        guard let enumerator = self.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            print("🔥 Failed to recursively enumerate file names in \(directoryURL)")
            return []
        }
        var files: [URL] = []
        for case let fileURL as URL in enumerator { files.append(fileURL) }
        return files
    }
}
