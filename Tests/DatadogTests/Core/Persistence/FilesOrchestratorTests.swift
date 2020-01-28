import XCTest
@testable import Datadog

let mockUseSingleFile = WritableFileConditions(
    maxFileSize: UInt64.max,
    maxFileAgeForWrite: TimeInterval.greatestFiniteMagnitude,
    maxNumberOfUsesOfFile: Int.max
)

class FilesOrchestratorTests: XCTestCase {
    private var dateProvider: DateProviderMock!  // swiftlint:disable:this implicitly_unwrapped_optional
    private var orchestrator: FilesOrchestrator! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        temporaryDirectory.create()
        dateProvider = DateProviderMock()
        orchestrator = FilesOrchestrator(
            directory: temporaryDirectory,
            writeConditions: LogsPersistenceStrategy.defaultWriteConditions,
            readConditions: LogsPersistenceStrategy.defaultReadConditions,
            dateProvider: dateProvider
        )
    }

    override func tearDown() {
        temporaryDirectory.delete()
        dateProvider = nil
        orchestrator = nil
        super.tearDown()
    }

    // MARK: - Writable file tests

    func testGivenDefaultWriteConditions_whenUsedFirstTime_itCreatesNewWritableFile() throws {
        dateProvider.currentDates = [.mockDecember15th2019At10AMUTC()]
        dateProvider.currentFileCreationDates = [.mockDecember15th2019At10AMUTC()]
        _ = try orchestrator.getWritableFile(writeSize: 1)

        XCTAssertEqual(try temporaryDirectory.allFiles().count, 1)
    }

    func testGivenDefaultWriteConditions_whenUsedNextTime_itReusesWritableFile() throws {
        dateProvider.currentDates = [.mockDecember15th2019At10AMUTC()]
        dateProvider.currentFileCreationDates = [.mockDecember15th2019At10AMUTC()]
        let file1 = try orchestrator.getWritableFile(writeSize: 1)
        let file2 = try orchestrator.getWritableFile(writeSize: 1)

        XCTAssertEqual(file1.fileURL, file2.fileURL)
        XCTAssertEqual(try temporaryDirectory.allFiles().count, 1)
    }

    func testGivenDefaultWriteConditions_whenFileCanNotBeUsedMoreTimes_itCreatesNewFile() throws {
        dateProvider.currentDates = [.mockDecember15th2019At10AMUTC()]
        dateProvider.currentFileCreationDates = [
            .mockDecember15th2019At10AMUTC(), // time of initially created file
            .mockDecember15th2019At10AMUTC(addingTimeInterval: 1) // time of next created file
        ]

        var previousFile: WritableFile = try orchestrator.getWritableFile(writeSize: 1) // first use
        var nextFile: WritableFile

        // use file maximum number of times
        for _ in (0 ..< (LogsPersistenceStrategy.defaultWriteConditions.maxNumberOfUsesOfFile - 1)) { // skip first use
            nextFile = try orchestrator.getWritableFile(writeSize: 1)
            XCTAssertEqual(nextFile.fileURL, previousFile.fileURL) // assert it reuses previous file
            previousFile = nextFile
        }

        // use it one more time
        nextFile = try orchestrator.getWritableFile(writeSize: 1)
        XCTAssertNotEqual(nextFile.fileURL, previousFile.fileURL) // assert it uses different flie
    }

    func testGivenDefaultWriteConditions_whenFileHasNoRoomForMore_itCreatesNewFile() throws {
        dateProvider.currentDates = [.mockDecember15th2019At10AMUTC()]
        dateProvider.currentFileCreationDates = [
            .mockDecember15th2019At10AMUTC(), // time of initially created file
            .mockDecember15th2019At10AMUTC(addingTimeInterval: 1) // time of next created file
        ]

        // chunks of data to fill entire file
        let chunkedData: [Data] = .mockChunksOf(totalSize: LogsPersistenceStrategy.defaultWriteConditions.maxFileSize)

        let file1 = try orchestrator.getWritableFile(writeSize: LogsPersistenceStrategy.defaultWriteConditions.maxFileSize)
        try file1.append { write in chunkedData.forEach { chunk in write(chunk) } }
        let file2 = try orchestrator.getWritableFile(writeSize: 1)

        XCTAssertNotEqual(file1.fileURL, file2.fileURL)
    }

    func testGivenDefaultWriteConditions_fileIsNotRecentEnough_itCreatesNewFile() throws {
        let timeIntervalExceedingMaxFileAge = 1 + LogsPersistenceStrategy.defaultWriteConditions.maxFileAgeForWrite
        dateProvider.currentFileCreationDates = [
            .mockDecember15th2019At10AMUTC(),
            .mockDecember15th2019At10AMUTC(addingTimeInterval: timeIntervalExceedingMaxFileAge)
        ]
        dateProvider.currentDates = [
            .mockDecember15th2019At10AMUTC(addingTimeInterval: timeIntervalExceedingMaxFileAge)
        ]

        let file1 = try orchestrator.getWritableFile(writeSize: 1)
        let file2 = try orchestrator.getWritableFile(writeSize: 1)

        XCTAssertNotEqual(file1.fileURL, file2.fileURL)
    }

    func testWhenCurrentWritableFileIsDeleted_itCreatesNewOne() throws {
        dateProvider.currentDates = [.mockDecember15th2019At10AMUTC()]
        dateProvider.currentFileCreationDates = [
            .mockDecember15th2019At10AMUTC(), // time of initially created file
            .mockDecember15th2019At10AMUTC(addingTimeInterval: 1) // time of next created file
        ]

        let file1URL = try orchestrator.getWritableFile(writeSize: 1).fileURL
        temporaryDirectory.deleteAllFiles()
        let file2URL = try orchestrator.getWritableFile(writeSize: 1).fileURL

        XCTAssertNotEqual(file1URL, file2URL)
    }

    /// This test makes sure that if SDK is used by multiple processes simultaneously, each `FileOrchestrator` works on a separate writable file.
    /// It is important when SDK is used by iOS App and iOS App Extension at the same time.
    func testWhenRequestedFirstTime_eachOrchestratorInstanceCreatesNewWritableFile() throws {
        dateProvider.currentDates = [.mockDecember15th2019At10AMUTC()]
        dateProvider.currentFileCreationDates = [
            .mockDecember15th2019At10AMUTC(), // file created by 1st orchestrator
            .mockDecember15th2019At10AMUTC(addingTimeInterval: 1) // file created by 2nd orchestrator
        ]
        let orchestrator1 = FilesOrchestrator(
            directory: temporaryDirectory,
            writeConditions: LogsPersistenceStrategy.defaultWriteConditions,
            readConditions: LogsPersistenceStrategy.defaultReadConditions,
            dateProvider: dateProvider
        )
        let orchestrator2 = FilesOrchestrator(
            directory: temporaryDirectory,
            writeConditions: LogsPersistenceStrategy.defaultWriteConditions,
            readConditions: LogsPersistenceStrategy.defaultReadConditions,
            dateProvider: dateProvider
        )

        _ = try orchestrator1.getWritableFile(writeSize: 1)
        XCTAssertEqual(try temporaryDirectory.allFiles().count, 1)

        _ = try orchestrator2.getWritableFile(writeSize: 1)
        XCTAssertEqual(try temporaryDirectory.allFiles().count, 2)
    }

    // MARK: - Readable file tests

    func testGivenDefaultReadConditions_itReturnsReadableFile() throws {
        dateProvider.currentDates = [.mockDecember15th2019At10AMUTC()]
        let ageExceedingMinFileAge = 1 + LogsPersistenceStrategy.defaultReadConditions.minFileAgeForRead
        let creationDateExceedingMinFileAge: Date = .mockDecember15th2019At10AMUTC(addingTimeInterval: -ageExceedingMinFileAge)
        let mockedFileURL = try temporaryDirectory.createFile(named: fileNameFrom(fileCreationDate: creationDateExceedingMinFileAge))

        let readableFile = orchestrator.getReadableFile()

        XCTAssertEqual(readableFile?.fileURL.lastPathComponent, mockedFileURL.lastPathComponent)
    }

    func testGivenDefaultReadConditions_whenThereAreSeveralFiles_itReturnsTheOldestOne() throws {
        dateProvider.currentDates = [.mockDecember15th2019At10AMUTC()]

        let fileNames = [
            fileNameFrom(fileCreationDate: dateProvider.currentDate().addingTimeInterval(-10)),
            fileNameFrom(fileCreationDate: dateProvider.currentDate().addingTimeInterval(-9)),
            fileNameFrom(fileCreationDate: dateProvider.currentDate().addingTimeInterval(-8)),
            fileNameFrom(fileCreationDate: dateProvider.currentDate().addingTimeInterval(-7))
        ]

        try fileNames.forEach { fileName in _ = try temporaryDirectory.createFile(named: fileName) }

        XCTAssertEqual(orchestrator.getReadableFile()?.fileURL.lastPathComponent, fileNames[0])
        try temporaryDirectory.deleteFile(named: fileNames[0])
        XCTAssertEqual(orchestrator.getReadableFile()?.fileURL.lastPathComponent, fileNames[1])
        try temporaryDirectory.deleteFile(named: fileNames[1])
        XCTAssertEqual(orchestrator.getReadableFile()?.fileURL.lastPathComponent, fileNames[2])
        try temporaryDirectory.deleteFile(named: fileNames[2])
        XCTAssertEqual(orchestrator.getReadableFile()?.fileURL.lastPathComponent, fileNames[3])
        try temporaryDirectory.deleteFile(named: fileNames[3])
        XCTAssertNil(orchestrator.getReadableFile())
    }

    func testGivenDefaultReadConditions_whenThereAreSeveralFiles_itExcludesGivenFileNames() throws {
        dateProvider.currentDates = [.mockDecember15th2019At10AMUTC()]

        let fileNames = [
            fileNameFrom(fileCreationDate: dateProvider.currentDate().addingTimeInterval(-10)),
            fileNameFrom(fileCreationDate: dateProvider.currentDate().addingTimeInterval(-9)),
            fileNameFrom(fileCreationDate: dateProvider.currentDate().addingTimeInterval(-8)),
            fileNameFrom(fileCreationDate: dateProvider.currentDate().addingTimeInterval(-7))
        ]

        try fileNames.forEach { fileName in _ = try temporaryDirectory.createFile(named: fileName) }

        XCTAssertEqual(
            orchestrator.getReadableFile(excludingFilesNamed: Set(fileNames[0...2]))?.fileURL.lastPathComponent,
            fileNames[3]
        )
    }

    func testGivenDefaultReadConditions_whenThereAreNoFiles_itReturnsNil() throws {
        XCTAssertNil(orchestrator.getReadableFile())
    }

    func testGivenDefaultReadConditions_whenFileIsTooYoung_itReturnsNoFile() throws {
        dateProvider.currentDates = [.mockDecember15th2019At10AMUTC()]
        let notEnoughInThePast: Date = .mockDecember15th2019At10AMUTC(
            addingTimeInterval: -0.5 * LogsPersistenceStrategy.defaultReadConditions.minFileAgeForRead
        )
        _ = try temporaryDirectory.createFile(named: fileNameFrom(fileCreationDate: notEnoughInThePast))

        XCTAssertNil(orchestrator.getReadableFile())
    }

    func testGivenDefaultReadConditions_whenFileIsTooOld_itGetsDeleted() throws {
        dateProvider.currentDates = [.mockDecember15th2019At10AMUTC()]

        let fileNames = [
            fileNameFrom(
                fileCreationDate: dateProvider.currentDate().addingTimeInterval(
                    -2 * LogsPersistenceStrategy.defaultReadConditions.maxFileAgeForRead
                )
            ),
            fileNameFrom(
                fileCreationDate: dateProvider.currentDate().addingTimeInterval(
                    -1.5 * LogsPersistenceStrategy.defaultReadConditions.maxFileAgeForRead
                )
            ),
            fileNameFrom(fileCreationDate: dateProvider.currentDate().addingTimeInterval(-8)),
            fileNameFrom(fileCreationDate: dateProvider.currentDate().addingTimeInterval(-7))
        ]

        try fileNames.forEach { fileName in _ = try temporaryDirectory.createFile(named: fileName) }

        XCTAssertEqual(orchestrator.getReadableFile()?.fileURL.lastPathComponent, fileNames[2])
        try temporaryDirectory.deleteFile(named: fileNames[2])
        XCTAssertEqual(orchestrator.getReadableFile()?.fileURL.lastPathComponent, fileNames[3])
        try temporaryDirectory.deleteFile(named: fileNames[3])
        XCTAssertEqual(try temporaryDirectory.allFiles().count, 0)
    }

    func testItDeletesReadableFile() throws {
        let mockedFileURL = try temporaryDirectory.createFile(named: fileNameFrom(fileCreationDate: .mockAny()))
        let readableFile = try ReadableFile(existingFileFromURL: mockedFileURL)

        orchestrator.delete(readableFile: readableFile)

        XCTAssertEqual(try temporaryDirectory.allFiles().count, 0)
    }
}
