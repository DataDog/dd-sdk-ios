import Foundation

internal struct WritableFileConditions {
    let maxDirectorySize: UInt64
    let maxFileSize: UInt64
    let maxFileAgeForWrite: TimeInterval
    let maxNumberOfUsesOfFile: Int
}

internal struct ReadableFileConditions {
    let minFileAgeForRead: TimeInterval
    let maxFileAgeForRead: TimeInterval
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

    init(
        directory: Directory,
        writeConditions: WritableFileConditions,
        readConditions: ReadableFileConditions,
        dateProvider: DateProvider
    ) {
        self.directory = directory
        self.writeConditions = writeConditions
        self.readConditions = readConditions
        self.dateProvider = dateProvider
    }

    // MARK: - `WritableFile` orchestration

    func getWritableFile(writeSize: UInt64) throws -> WritableFile {
        try purgeFilesDirectoryIfNeeded()

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
                    developerLogger?.info("💡 Previously used writable file does no longer exist.")
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
                developerLogger?.error("🔥 Failed to read previously used writable file: \(error)")
            }
        }

        return nil
    }

    // MARK: - `ReadableFile` orchestration

    func getReadableFile(excludingFilesNamed excludedFileNames: Set<String> = []) -> ReadableFile? {
        do {
            let filesWithCreationDate = try directory.allFiles()
                .map { (url: $0, creationDate: fileCreationDateFrom(fileName: $0.lastPathComponent)) }
                .compactMap { try deleteFileIfItsObsolete(url: $0.url, fileCreationDate: $0.creationDate) }

            guard let oldestFileURL = filesWithCreationDate
                .filter({ excludedFileNames.contains($0.url.lastPathComponent) == false })
                .sorted(by: { $0.creationDate < $1.creationDate })
                .first?.url
            else {
                return nil
            }

            let oldestFile = try ReadableFile(existingFileFromURL: oldestFileURL)
            let oldestFileAge = dateProvider.currentDate().timeIntervalSince(oldestFile.creationDate)
            let fileIsOldEnough = oldestFileAge >= readConditions.minFileAgeForRead

            return fileIsOldEnough ? oldestFile : nil
        } catch {
            developerLogger?.error("🔥 Failed to obtain readable file: \(error)")
            return nil
        }
    }

    func delete(readableFile: ReadableFile) {
        do {
            try directory.deleteFile(named: readableFile.fileURL.lastPathComponent)
        } catch {
            developerLogger?.error("🔥 Failed to delete file: \(error)")
        }
    }

    // MARK: - Directory size management

    /// Removes oldest files from the directory if it becomes too big.
    private func purgeFilesDirectoryIfNeeded() throws {
        let filesSortedByCreationDate = try directory.allFiles()
            .map { (url: $0, creationDate: fileCreationDateFrom(fileName: $0.lastPathComponent)) }
            .sorted { $0.creationDate < $1.creationDate }

        var filesWithSizeSortedByCreationDate = try filesSortedByCreationDate
            .map { (url: $0.url, size: try FileManager.default.attributesOfItem(atPath: $0.url.path)[.size] as? UInt64 ?? 0) }

        let accumulatedFilesSize = filesWithSizeSortedByCreationDate.map { $0.size }.reduce(0, +)

        if accumulatedFilesSize > writeConditions.maxDirectorySize {
            let sizeToFree = accumulatedFilesSize - writeConditions.maxDirectorySize
            var sizeFreed: UInt64 = 0

            while sizeFreed < sizeToFree && !filesWithSizeSortedByCreationDate.isEmpty {
                let file = filesWithSizeSortedByCreationDate.removeFirst()
                try directory.deleteFile(named: file.url.lastPathComponent)
                sizeFreed += file.size
            }
        }
    }

    private func deleteFileIfItsObsolete(url: URL, fileCreationDate: Date) throws -> (url: URL, creationDate: Date)? {
        let fileAge = dateProvider.currentDate().timeIntervalSince(fileCreationDate)

        if fileAge > readConditions.maxFileAgeForRead {
            try directory.deleteFile(named: url.lastPathComponent)
            return nil
        } else {
            return (url: url, creationDate: fileCreationDate)
        }
    }
}
