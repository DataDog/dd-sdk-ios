import XCTest
@testable import Datadog

class DatadogTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(Datadog.instance)
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        super.tearDown()
    }

    func testItCanBeInitializedWithValidConfiguration() throws {
        Datadog.initialize(
            endpointURL: "https://api.example.com/v1/logs/",
            clientToken: "abcdefghi"
        )
        XCTAssertNotNil(Datadog.instance)
        try Datadog.deinitializeOrThrow()
    }

    func testWhenInitializedWithInvalidConfiguration_itThrowsProgrammerError() {
        XCTAssertThrowsError(try Datadog.initializeOrThrow(endpointURL: "", clientToken: "")) { error in
            XCTAssertTrue(error is ProgrammerError)
        }
    }

    func testWhenInitializedMoreThanOnce_itThrowsProgrammerError() throws {
        let initialize = {
            try Datadog.initializeOrThrow(
                endpointURL: "https://api.example.com/v1/logs/",
                clientToken: "abcdefghi"
            )
        }
        try initialize()
        XCTAssertThrowsError(try initialize()) { error in
            XCTAssertEqual(
                (error as? ProgrammerError)?.description,
                "Datadog SDK usage error: SDK is already initialized."
            )
        }
        try Datadog.deinitializeOrThrow()
    }
}
