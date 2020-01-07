import Foundation

internal struct WritableFileConditions {
    let maxFileSize: UInt64
    let maxFileAgeForWrite: TimeInterval
    let maxNumberOfUsesOfFile: Int

    static let `default`: WritableFileConditions = WritableFileConditions(
        maxFileSize: LogsFileStrategy.Constants.maxBatchSize,
        maxFileAgeForWrite: LogsFileStrategy.Constants.maxFileAgeForWrite,
        maxNumberOfUsesOfFile: LogsFileStrategy.Constants.maxLogsPerBatch
    )
}

internal class FilesOrchestrator {
    /// Directory where files are stored.
    private let directory: Directory
    /// Date provider.
    private let dateProvider: DateProvider
    /// Conditions for picking up writable file.
    private let writeConditions: WritableFileConditions
    /// URL of the last file used by `getWritableFile()`.
    private var lastWritableFileURL: URL? = nil
    /// Tracks number of times the file at `lastWritableFileURL` was returned from `getWritableFile()`.
    private var lastWritableFileUsesCount: Int = 0

    init(directory: Directory, writeConditions: WritableFileConditions, dateProvider: DateProvider) {
        self.directory = directory
        self.writeConditions = writeConditions
        self.dateProvider = dateProvider
    }

    // MARK: - `WritableFile` orchestration

    func getWritableFile(writeSize: UInt64) throws -> WritableFile {
        let lastWritableFileOrNil = reuseLastWritableFileIfPossible(writeSize: writeSize)

        if let lastWritableFile = lastWritableFileOrNil { // if last writable file can be reused
            lastWritableFileUsesCount += 1
            return lastWritableFile
        } else {
            let newFile = try WritableFile(newFileInDirectory: directory, createdAt: dateProvider.currentFileCreationDate())
            lastWritableFileURL = newFile.fileURL
            lastWritableFileUsesCount = 1
            return newFile
        }
    }

    private func reuseLastWritableFileIfPossible(writeSize: UInt64) -> WritableFile? {
        if let lastFileURL = lastWritableFileURL {
            do {
                guard FileManager.default.fileExists(atPath: lastFileURL.path) else {
                    print("Previously used file does not exist.")
                    return nil
                }

                let lastFile = try WritableFile(existingFileFromURL: lastFileURL)
                let lastFileAge = dateProvider.currentDate().timeIntervalSince(lastFile.creationDate)
                let fileIsRecentEnough = lastFileAge <= writeConditions.maxFileAgeForWrite
                let fileHasRoomForMore = (lastFile.initialSize + writeSize) <= writeConditions.maxFileSize
                let fileCanBeUsedMoreTimes = (lastWritableFileUsesCount + 1) <= writeConditions.maxNumberOfUsesOfFile

                if fileIsRecentEnough && fileHasRoomForMore && fileCanBeUsedMoreTimes {
                    return lastFile
                }
            } catch {
                print("Failed to open previously used file.")
            }
        }

        return nil
    }
}
