import Foundation
@testable import Datadog

/// Creates `Directory` pointing to unique subfolder in `/var/folders/`.
/// Does not create the subfolder - it must be later created with `.create()`.
func obtainUniqueTemporaryDirectory() -> Directory {
    let subdirectoryName = "com.datadoghq.ios-sdk-tests-\(UUID().uuidString)"
    let osTemporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(subdirectoryName, isDirectory: true)
    print("💡 Obtained temporary directory URL: \(osTemporaryDirectoryURL)")
    return Directory(url: osTemporaryDirectoryURL)
}

/// `Directory` pointing to subfolder in `/var/folders/`.
/// The subfolder does not exist and can be created and deleted by calling `.create()` and `.delete()`.
let temporaryDirectory = obtainUniqueTemporaryDirectory()

/// Extends `Directory` with set of utilities for convenient work with files in tests.
/// Provides handy methods to create / delete files and directires.
extension Directory {
    /// Creates empty directory with given attributes .
    func create(attributes: [FileAttributeKey: Any]? = nil) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: attributes)
            let initialFilesCount = try files().count
            precondition(initialFilesCount == 0) // ensure it's empty
        } catch {
            fatalError("🔥 Failed to create `TestsDirectory`: \(error)")
        }
    }

    /// Deletes entire directory with its content.
    func delete() {
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                fatalError("🔥 Failed to delete `TestsDirectory`: \(error)")
            }
        }
    }

    /// Deletes all files  in this directory.
    func deleteAllFiles() {
        delete()
        create()
    }

    /// Deletes particular file in this directory.
    func deleteFile(fileName: String) {
        let url = urlFor(fileNamed: fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Sets directory attributes.
    func set(attributes: [FileAttributeKey: Any]) {
        do {
            try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
        } catch {
            fatalError("🔥 Failed to set attributes: \(attributes) for `TestsDirectory`: \(error)")
        }
    }

    /// Returns size of a given file.
    func sizeOfFile(named fileName: String) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: urlFor(fileNamed: fileName).path)
        return attributes[.size] as? UInt64 ?? 0
    }

    /// Creates URL for given file name in this directory.
    func urlFor(fileNamed fileName: String) -> URL {
        return url.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Returns list of files matching given predicate.
    func files(matching filter: ((URL) -> Bool) = { _ in true }) throws -> [URL] {
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey]).filter(filter)
    }

    /// Returns names of all directory files.
    func allFileNames() throws -> Set<String> {
        return Set(try files().map { $0.lastPathComponent })
    }

    /// Checks if file with given name exists in this directory.
    func fileExists(fileName: String) -> Bool {
        let fileURL = urlFor(fileNamed: fileName)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Returns contents of file with given name or `nil` if file does not exist.
    func contentsOfFile(fileName: String) -> Data? {
        let fileURL = urlFor(fileNamed: fileName)
        return FileManager.default.contents(atPath: fileURL.path)
    }

    /// Returns UTF-8 encoded text content from the first file in this directory.
    /// If there are more files, it doesn't guarantee which one will be picked.
    func textEncodedDataFromFirstFile() throws -> String? {
        if let firstFileURL = try files().first {
            let data = try Data(contentsOf: firstFileURL)
            return String(data: data, encoding: .utf8)
        } else {
            return nil
        }
    }
}
