import Foundation

/// Provides convenient interface to append data to underlying file and tracks metadata of that file.
/// It doesn't own the file, which means the file presence is not guaranteed - the file can be deleted by OS at any time (e.g. due to memory pressure).
/// This class is should be the only interface for manipulating storage files in the "write" context (opening and writting).
internal final class WritableFile {
    /// Creates new file in given directory.
    /// Creation date is used to name the file by time interval elapsed since reference date (00:00:00 UTC on 1 January 2001).
    init(newFileInDirectory directory: Directory, createdAt date: Date) throws {
        let creationDate = date
        let fileName = fileNameFrom(fileCreationDate: date)
        let fileURL = try directory.createFile(named: fileName)
        self.fileURL = fileURL
        self.creationDate = creationDate
        self.size = 0
    }

    /// Opens file with given url.
    init(existingFileFromURL url: URL) throws {
        self.fileURL = url
        self.creationDate = fileCreationDateFrom(fileName: url.lastPathComponent)

        let fileHandle = try FileHandle(forWritingTo: url)
        defer { fileHandle.closeFile() }
        self.size = fileHandle.seekToEndOfFile()
    }

    /// URL of the underlying file in file system.
    let fileURL: URL

    /// Time of the file creation.
    let creationDate: Date

    /// Size of this file.
    private(set) var size: UInt64

    /// Checks if the file was written before.
    var isEmpty: Bool { return size == 0 }

    /// Appends given data do the end of this file within single "write" operation counted on `numberOfWrites`.
    func append(transaction: ((Data) -> Void) -> Void) throws {
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        defer { fileHandle.closeFile() }
        size = fileHandle.seekToEndOfFile()

        // Writes given data to file and seeks to the end of file.
        func writeAndSeek(data: Data) {
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
            size = fileHandle.seekToEndOfFile()
        }
        transaction(writeAndSeek)
    }
}
