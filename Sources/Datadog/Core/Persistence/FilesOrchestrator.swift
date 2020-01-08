import Foundation

internal struct WritableFileConditions {
    let maxFileSize: UInt64
    let maxFileAgeForWrite: TimeInterval
    let maxNumberOfUsesOfFile: Int

    static let `default` = WritableFileConditions(
        maxFileSize: LogsFileStrategy.Constants.maxBatchSize,
        maxFileAgeForWrite: LogsFileStrategy.Constants.maxFileAgeForWrite,
        maxNumberOfUsesOfFile: LogsFileStrategy.Constants.maxLogsPerBatch
    )
}

internal struct ReadableFileConditions {
    let minFileAgeForRead: TimeInterval

    static let `default` = ReadableFileConditions(
        minFileAgeForRead: LogsFileStrategy.Constants.minFileAgeForRead
    )
}

internal class FilesOrchestrator {
    /// Directory where files are stored.
    private let directory: Directory
    /// Date provider.
    private let dateProvider: DateProvider
    /// Conditions for picking up writable file.
    private let writeConditions: WritableFileConditions
    /// Conditions for picking up readable file.
    private let readConditions: ReadableFileConditions
    /// URL of the last file used by `getWritableFile()`.
    private var lastWritableFileURL: URL? = nil
    /// Tracks number of times the file at `lastWritableFileURL` was returned from `getWritableFile()`.
    private var lastWritableFileUsesCount: Int = 0

    init(directory: Directory, writeConditions: WritableFileConditions, readConditions: ReadableFileConditions, dateProvider: DateProvider) {
        self.directory = directory
        self.writeConditions = writeConditions
        self.readConditions = readConditions
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
                print("Failed to open previously used file \(error).")
            }
        }

        return nil
    }

    // MARK: - `ReadableFile` orchestration

    func getReadableFile(excludingFilesNamed excludedFileNames: Set<String> = []) -> ReadableFile? {
        do {
            let fileURLs = try directory.allFiles().filter { excludedFileNames.contains($0.lastPathComponent) == false }

            let fileURLsWithCreationDate = fileURLs.map {
                (url: $0, creationDate: fileCreationDateFrom(fileName: $0.lastPathComponent))
            }
            guard let oldestFileURL = fileURLsWithCreationDate.sorted(by: { $0.creationDate < $1.creationDate }).first?.url else {
                return nil
            }

            let oldestFile = try ReadableFile(existingFileFromURL: oldestFileURL)
            let oldestFileAge = dateProvider.currentDate().timeIntervalSince(oldestFile.creationDate)
            let fileIsOldEnough = oldestFileAge >= readConditions.minFileAgeForRead

            return fileIsOldEnough ? oldestFile : nil
        } catch {
            print("Failed to obtain readable file \(error).")
            return nil
        }
    }

    func delete(readableFile: ReadableFile) {
        do {
            try directory.deleteFile(named: readableFile.fileURL.lastPathComponent)
        } catch {
            print("Failed to delete readable file \(error).")
        }
    }
}
