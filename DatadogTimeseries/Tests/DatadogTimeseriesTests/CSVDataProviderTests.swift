import XCTest
@testable import DatadogTimeseries

final class CSVDataProviderTests: XCTestCase {
    func testReadsFilteredSamplesFromCSV() throws {
        let csv = """
        timestamp,metric,value
        1000000000,memory_usage,30000000
        1000000000,cpu_usage,12.5
        2000000000,memory_usage,31000000
        2000000000,cpu_usage,15.0
        3000000000,memory_usage,32000000
        """

        let provider = CSVDataProvider(csvContent: csv, metric: .memoryUsage)

        let s1 = provider.read()
        XCTAssertEqual(s1?.timestamp, 1000000000)
        XCTAssertEqual(s1?.value, 30000000)

        let s2 = provider.read()
        XCTAssertEqual(s2?.timestamp, 2000000000)
        XCTAssertEqual(s2?.value, 31000000)

        let s3 = provider.read()
        XCTAssertEqual(s3?.timestamp, 3000000000)
        XCTAssertEqual(s3?.value, 32000000)

        let s4 = provider.read()
        XCTAssertNil(s4)
    }

    func testFiltersByCPUUsage() throws {
        let csv = """
        timestamp,metric,value
        1000000000,memory_usage,30000000
        1000000000,cpu_usage,12.5
        2000000000,cpu_usage,15.0
        """

        let provider = CSVDataProvider(csvContent: csv, metric: .cpuUsage)

        let s1 = provider.read()
        XCTAssertEqual(s1?.timestamp, 1000000000)
        XCTAssertEqual(s1?.value, 12.5)

        let s2 = provider.read()
        XCTAssertEqual(s2?.timestamp, 2000000000)
        XCTAssertEqual(s2?.value, 15.0)

        XCTAssertNil(provider.read())
    }

    func testReturnsNilForEmptyCSV() {
        let csv = "timestamp,metric,value\n"
        let provider = CSVDataProvider(csvContent: csv, metric: .memoryUsage)
        XCTAssertNil(provider.read())
    }

    func testSkipsMalformedRows() {
        let csv = """
        timestamp,metric,value
        1000000000,memory_usage,30000000
        bad_row
        2000000000,memory_usage,31000000
        """

        let provider = CSVDataProvider(csvContent: csv, metric: .memoryUsage)

        let s1 = provider.read()
        XCTAssertEqual(s1?.timestamp, 1000000000)

        let s2 = provider.read()
        XCTAssertEqual(s2?.timestamp, 2000000000)

        XCTAssertNil(provider.read())
    }
}
