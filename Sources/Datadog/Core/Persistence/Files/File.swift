import Foundation

/// Provides convenient interface for reading metadata and appending data to the file.
internal protocol WritableFile {
    /// Name of this file.
    var name: String { get }

    /// Current size of this file.
    func size() throws -> UInt64

    /// Synchronously appends given data at the end of this file.
    func append(transaction: ((Data) -> Void) -> Void) throws
}

/// Provides convenient interface for reading contents and metadata of the file.
internal protocol ReadableFile {
    /// Name of this file.
    var name: String { get }

    /// Reads the available data in this file.
    func read() throws -> Data

    /// Deletes this file.
    func delete() throws
}

/// An immutable `struct` designed to provide optimized and thread safe interface for file manipulation.
/// It doesn't own the file, which means the file presence is not guaranteed - the file can be deleted by OS at any time (e.g. due to memory pressure).
internal struct File: WritableFile, ReadableFile {
    let url: URL
    let name: String

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
    }

    /// Appends given data at the end of this file.
    func append(transaction: ((Data) -> Void) -> Void) throws {
        let fileHandle = try FileHandle(forWritingTo: url)
        defer { fileHandle.closeFile() }
        fileHandle.seekToEndOfFile()

        // Writes given data at the end of the file.
        func appendData(_ data: Data) {
            /*
             Apple documentation https://developer.apple.com/documentation/foundation/filehandle/1410936-write says
             that `fileHandle.write()` raises an exception if no free space is left on the file system,
             or if any other writing error occurs. Those are unchecked exceptions impossible to handle in Swift.

             It was already escalated to Apple in Swift open source project discussion:
             https://forums.swift.org/t/pitch-replacement-for-filehandle/5177

             Until better replacement is provided by Apple, the SDK sticks to this API. To mitigate the risk of
             crashing client applications, other precautions are implemented carefuly.
             */
            fileHandle.write(data)
        }
        transaction(appendData)
    }

    func read() throws -> Data {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { fileHandle.closeFile() }
        return fileHandle.readDataToEndOfFile()
    }

    func size() throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? UInt64 ?? 0
    }

    func delete() throws {
        try FileManager.default.removeItem(at: url)
    }
}
