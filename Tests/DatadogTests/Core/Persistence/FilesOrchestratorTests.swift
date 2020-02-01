import XCTest
@testable import Datadog

let mockUseSingleFile = WritableFileConditions(
    maxDirectorySize: UInt64.max,
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

        XCTAssertEqual(try temporaryDirectory.files().count, 1)
    }

    func testGivenDefaultWriteConditions_whenUsedNextTime_itReusesWritableFile() throws {
        dateProvider.currentDates = [.mockDecember15th2019At10AMUTC()]
        dateProvider.currentFileCreationDates = [.mockDecember15th2019At10AMUTC()]
        let file1 = try orchestrator.getWritableFile(writeSize: 1)
        let file2 = try orchestrator.getWritableFile(writeSize: 1)

        XCTAssertEqual(file1.name, file2.name)
        XCTAssertEqual(try temporaryDirectory.files().count, 1)
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
            XCTAssertEqual(nextFile.name, previousFile.name) // assert it reuses previous file
            previousFile = nextFile
        }

        // use it one more time
        nextFile = try orchestrator.getWritableFile(writeSize: 1)
        XCTAssertNotEqual((nextFile as! File).url, (previousFile as! File).url) // assert it uses different flie
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

        XCTAssertNotEqual(file1.name, file2.name)
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

        XCTAssertNotEqual(file1.name, file2.name)
    }

    func testWhenCurrentWritableFileIsDeleted_itCreatesNewOne() throws {
        dateProvider.currentDates = [.mockDecember15th2019At10AMUTC()]
        dateProvider.currentFileCreationDates = [
            .mockDecember15th2019At10AMUTC(), // time of initially created file
            .mockDecember15th2019At10AMUTC(addingTimeInterval: 1) // time of next created file
        ]

        let file1 = try orchestrator.getWritableFile(writeSize: 1)
        try temporaryDirectory.files().forEach { file in try file.delete() }
        let file2 = try orchestrator.getWritableFile(writeSize: 1)

        XCTAssertNotEqual(file1.name, file2.name)
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
        XCTAssertEqual(try temporaryDirectory.files().count, 1)

        _ = try orchestrator2.getWritableFile(writeSize: 1)
        XCTAssertEqual(try temporaryDirectory.files().count, 2)
    }

    func testWhenFilesDirectorySizeIsBig_itKeepsItUnderLimit_byRemovingOldestFilesFirst() throws {
        dateProvider.currentFileCreationDates = [
            .mockDecember15th2019At10AMUTC(addingTimeInterval: -30),
            .mockDecember15th2019At10AMUTC(addingTimeInterval: -25),
            .mockDecember15th2019At10AMUTC(addingTimeInterval: -20),
            .mockDecember15th2019At10AMUTC(addingTimeInterval: -15),
            .mockDecember15th2019At10AMUTC(addingTimeInterval: -10),
        ]

        let oneMB: UInt64 = 1_024 * 1_024

        let orchestrator = FilesOrchestrator(
            directory: temporaryDirectory,
            writeConditions: .init(
                maxDirectorySize: 3 * oneMB, // 3MB
                maxFileSize: oneMB, // 1MB
                maxFileAgeForWrite: .greatestFiniteMagnitude,
                maxNumberOfUsesOfFile: 1
            ),
            readConditions: LogsPersistenceStrategy.defaultReadConditions,
            dateProvider: dateProvider
        )

        // write 1MB to first file (1MB of directory size in total)
        let file1 = try orchestrator.getWritableFile(writeSize: oneMB)
        try file1.append { write in write(.mock(ofSize: oneMB)) }

        // write 1MB to second file (2MB of directory size in total)
        let file2 = try orchestrator.getWritableFile(writeSize: oneMB)
        try file2.append { write in write(.mock(ofSize: oneMB)) }

        // write 1MB to third file (3MB of directory size in total)
        let file3 = try orchestrator.getWritableFile(writeSize: oneMB + 1) // +1 byte to exceed the limit
        try file3.append { write in write(.mock(ofSize: oneMB + 1)) }

        XCTAssertEqual(try temporaryDirectory.files().count, 3)

        // At this point, directory reached its maximum size.
        // Asking for the next file should purge the oldest one.
        let file4 = try orchestrator.getWritableFile(writeSize: oneMB)
        XCTAssertEqual(try temporaryDirectory.files().count, 3)
        XCTAssertNil(try? temporaryDirectory.file(named: file1.name))
        try file4.append { write in write(.mock(ofSize: oneMB + 1)) }

        _ = try orchestrator.getWritableFile(writeSize: oneMB)
        XCTAssertEqual(try temporaryDirectory.files().count, 3)
        XCTAssertNil(try? temporaryDirectory.file(named: file2.name))
    }

    // MARK: - Readable file tests

    func testGivenDefaultReadConditions_itReturnsReadableFile() throws {
        let ageExceedingMinFileAge = 1 + LogsPersistenceStrategy.defaultReadConditions.minFileAgeForRead
        let creationDateExceedingMinFileAge = dateProvider.currentDate().secondsAgo(ageExceedingMinFileAge)
        let file = try temporaryDirectory.createFile(named: creationDateExceedingMinFileAge.toFileName)

        let readableFile = orchestrator.getReadableFile()

        XCTAssertEqual(readableFile?.name, file.name)
    }

    func testGivenDefaultReadConditions_whenThereAreSeveralFiles_itReturnsTheOldestOne() throws {
        dateProvider.currentDates = [.mockDecember15th2019At10AMUTC()]

        let fileNames = [
            dateProvider.currentDate().addingTimeInterval(-10).toFileName,
            dateProvider.currentDate().addingTimeInterval(-9).toFileName,
            dateProvider.currentDate().addingTimeInterval(-8).toFileName,
            dateProvider.currentDate().addingTimeInterval(-7).toFileName,
        ]

        try fileNames.forEach { fileName in _ = try temporaryDirectory.createFile(named: fileName) }

        XCTAssertEqual(orchestrator.getReadableFile()?.name, fileNames[0])
        try temporaryDirectory.file(named: fileNames[0]).delete()
        XCTAssertEqual(orchestrator.getReadableFile()?.name, fileNames[1])
        try temporaryDirectory.file(named: fileNames[1]).delete()
        XCTAssertEqual(orchestrator.getReadableFile()?.name, fileNames[2])
        try temporaryDirectory.file(named: fileNames[2]).delete()
        XCTAssertEqual(orchestrator.getReadableFile()?.name, fileNames[3])
        try temporaryDirectory.file(named: fileNames[3]).delete()
        XCTAssertNil(orchestrator.getReadableFile())
    }

    func testGivenDefaultReadConditions_whenThereAreSeveralFiles_itExcludesGivenFileNames() throws {
        dateProvider.currentDates = [.mockDecember15th2019At10AMUTC()]

        let fileNames = [
            dateProvider.currentDate().addingTimeInterval(-10).toFileName,
            dateProvider.currentDate().addingTimeInterval(-9).toFileName,
            dateProvider.currentDate().addingTimeInterval(-8).toFileName,
            dateProvider.currentDate().addingTimeInterval(-7).toFileName,
        ]

        try fileNames.forEach { fileName in _ = try temporaryDirectory.createFile(named: fileName) }

        XCTAssertEqual(
            orchestrator.getReadableFile(excludingFilesNamed: Set(fileNames[0...2]))?.name,
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
        _ = try temporaryDirectory.createFile(named: notEnoughInThePast.toFileName)

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

        XCTAssertEqual(orchestrator.getReadableFile()?.name, fileNames[2])
        try temporaryDirectory.file(named: fileNames[2]).delete()
        XCTAssertEqual(orchestrator.getReadableFile()?.name, fileNames[3])
        try temporaryDirectory.file(named: fileNames[3]).delete()
        XCTAssertEqual(try temporaryDirectory.files().count, 0)
    }

    func testItDeletesReadableFile() throws {
        let ageExceedingMinFileAge = 1 + LogsPersistenceStrategy.defaultReadConditions.minFileAgeForRead
        let creationDateExceedingMinFileAge = dateProvider.currentDate().secondsAgo(ageExceedingMinFileAge)
        _ = try temporaryDirectory.createFile(named: creationDateExceedingMinFileAge.toFileName)

        let readableFile = orchestrator.getReadableFile()

        XCTAssertEqual(try temporaryDirectory.files().count, 1)

        orchestrator.delete(readableFile: readableFile!)

        XCTAssertEqual(try temporaryDirectory.files().count, 0)
    }

    // MARK: - File names tests

    // swiftlint:disable number_separator
    func testItTurnsFileNameIntoFileCreationDate() {
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 0)), "0")
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456)), "123456000")
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456.7)), "123456700")
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456.78)), "123456780")
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456.789)), "123456789")

        // microseconds rounding
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456.1111)), "123456111")
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456.1115)), "123456112")
        XCTAssertEqual(fileNameFrom(fileCreationDate: Date(timeIntervalSinceReferenceDate: 123456.1119)), "123456112")

        // overflows
        let maxDate = Date(timeIntervalSinceReferenceDate: TimeInterval.greatestFiniteMagnitude)
        let minDate = Date(timeIntervalSinceReferenceDate: -TimeInterval.greatestFiniteMagnitude)
        XCTAssertEqual(fileNameFrom(fileCreationDate: maxDate), "0")
        XCTAssertEqual(fileNameFrom(fileCreationDate: minDate), "0")
    }

    func testItTurnsFileCreationDateIntoFileName() {
        XCTAssertEqual(fileCreationDateFrom(fileName: "0"), Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertEqual(fileCreationDateFrom(fileName: "123456000"), Date(timeIntervalSinceReferenceDate: 123456))
        XCTAssertEqual(fileCreationDateFrom(fileName: "123456700"), Date(timeIntervalSinceReferenceDate: 123456.7))
        XCTAssertEqual(fileCreationDateFrom(fileName: "123456780"), Date(timeIntervalSinceReferenceDate: 123456.78))
        XCTAssertEqual(fileCreationDateFrom(fileName: "123456789"), Date(timeIntervalSinceReferenceDate: 123456.789))

        // ignores invalid names
        let invalidFileName = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        XCTAssertEqual(fileCreationDateFrom(fileName: invalidFileName), Date(timeIntervalSinceReferenceDate: 0))
    }
    // swiftlint:enable number_separator
}
