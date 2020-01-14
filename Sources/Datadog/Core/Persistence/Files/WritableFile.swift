import Foundation

/// Provides convenient interface for getting metadata of the file and appending data to it.
/// `WritableFile` is an immutable `struct` designed to provide optimized and thread safe interface for file manipulation.
/// It doesn't own the file, which means the file presence is not guaranteed - the file can be deleted by OS at any time (e.g. due to memory pressure).
internal struct WritableFile {
    /// Creates new file in given directory.
    /// Creation date is used to name the file by time interval elapsed since reference date (00:00:00 UTC on 1 January 2001).
    init(newFileInDirectory directory: Directory, createdAt date: Date) throws {
        let creationDate = date
        let fileName = fileNameFrom(fileCreationDate: date)
        let fileURL = try directory.createFile(named: fileName)
        self.fileURL = fileURL
        self.creationDate = creationDate
        self.initialSize = 0
    }

    /// Opens file with given url.
    init(existingFileFromURL url: URL) throws {
        self.fileURL = url
        self.creationDate = fileCreationDateFrom(fileName: url.lastPathComponent)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        self.initialSize = fileAttributes[.size] as? UInt64 ?? 0
    }

    /// URL of the underlying file in file system.
    let fileURL: URL

    /// Time of the file creation.
    let creationDate: Date

    /// The initial size of the file. It doesn't change after data is appended.
    /// New immutable instance of `WritableFile` should be obtained to get updated info.
    let initialSize: UInt64

    /// Synchronously appends given data at the end of this file.
    func append(transaction: ((Data) -> Void) -> Void) throws {
        let fileHandle = try FileHandle(forWritingTo: fileURL)
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
}
