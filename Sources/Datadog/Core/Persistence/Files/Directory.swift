import Foundation

/// An abstraction over file system directory where SDK stores its files.
internal struct Directory {
    let url: URL

    init(withSubdirectoryPath path: String) throws {
        self.init(url: try createCachesSubdirectoryIfNotExists(subdirectoryPath: path))
    }

    init(url: URL) {
        self.url = url
    }

    /// Creates file with given name.
    func createFile(named fileName: String) throws -> URL {
        let fileURL = url.appendingPathComponent(fileName, isDirectory: false)
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil) == true else {
            throw InternalError(description: "Cannot create file at path: \(fileURL.path)")
        }
        return fileURL
    }

    /// Deletes file with given name.
    func deleteFile(named fileName: String) throws {
        let fileURL = url.appendingPathComponent(fileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Returns list of files in this directory.
    func allFiles() throws -> [URL] {
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey, .canonicalPathKey])
    }
}

/// Creates subdirectory at given path in `/Library/Caches` if it does not exist. Might throw `ProgrammerError` when it's not possible.
/// * `/Library/Caches` is exclduded from iTunes and iCloud backups by default.
/// * System may delete data in `/Library/Cache` to free up disk space which reduces the impact on devices working under heavy space pressure.
private func createCachesSubdirectoryIfNotExists(subdirectoryPath: String) throws -> URL {
    guard let cachesDirectoryURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
        throw ProgrammerError(description: "Cannot obtain `/Library/Caches/` url.")
    }
    let subdirectoryURL = cachesDirectoryURL.appendingPathComponent(subdirectoryPath, isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: subdirectoryURL, withIntermediateDirectories: true, attributes: nil)
    } catch {
        throw ProgrammerError(description: "Cannot create subdirectory in `/Library/Caches/` folder.")
    }
    return subdirectoryURL
}
