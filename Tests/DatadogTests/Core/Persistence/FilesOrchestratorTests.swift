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
            writeConditions: .default,
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

        XCTAssertEqual(file1.fileURL, file2.fileURL)
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
        for _ in (0 ..< (WritableFileConditions.default.maxNumberOfUsesOfFile - 1)) { // skip first use
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
        let chunkedData: [Data] = .mockChunksOf(totalSize: WritableFileConditions.default.maxFileSize)

        let file1 = try orchestrator.getWritableFile(writeSize: WritableFileConditions.default.maxFileSize)
        try file1.append { write in chunkedData.forEach { chunk in write(chunk) } }
        let file2 = try orchestrator.getWritableFile(writeSize: 1)

        XCTAssertNotEqual(file1.fileURL, file2.fileURL)
    }

    func testGivenDefaultWriteConditions_fileIsNotRecentEnough_itCreatesNewFile() throws {
        let timeIntervalExceedingMaxFileAge = 1 + WritableFileConditions.default.maxFileAgeForWrite
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
        let orchestrator1 = FilesOrchestrator(directory: temporaryDirectory, writeConditions: .default, dateProvider: dateProvider)
        let orchestrator2 = FilesOrchestrator(directory: temporaryDirectory, writeConditions: .default, dateProvider: dateProvider)

        _ = try orchestrator1.getWritableFile(writeSize: 1)
        XCTAssertEqual(try temporaryDirectory.files().count, 1)

        _ = try orchestrator2.getWritableFile(writeSize: 1)
        XCTAssertEqual(try temporaryDirectory.files().count, 2)
    }
}
