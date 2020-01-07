import Foundation

internal struct ReadableFile {
    /// Opens file with given url.
    init(existingFileFromURL url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw InternalError(description: "File does not exist at path: \(url.path)")
        }
        self.fileURL = url
        self.creationDate = fileCreationDateFrom(fileName: url.lastPathComponent)
    }

    /// URL of the underlying file in file system.
    let fileURL: URL

    /// Time of the file creation.
    let creationDate: Date

    /// Synchronously reads the available data in this file.
    func read() throws -> Data {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { fileHandle.closeFile() }
        return fileHandle.readDataToEndOfFile()
    }
}
