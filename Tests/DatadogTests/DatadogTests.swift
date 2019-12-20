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

    func testItCanBeInitializedWithValidConfiguration() {
        Datadog.initialize(
            endpointURL: "https://api.example.com/v1/logs/",
            clientToken: "abcdefghi"
        )
        XCTAssertNotNil(Datadog.instance)
        Datadog.stop()
    }

    func testAfterInitialized_itCanBeStopped() {
        Datadog.initialize(
            endpointURL: "https://api.example.com/v1/logs/",
            clientToken: "abcdefghi"
        )
        Datadog.stop()
        XCTAssertNil(Datadog.instance)
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
            XCTAssertTrue((error as? ProgrammerError)?.description == "Datadog SDK is already initialized.")
        }
        Datadog.stop()
    }

    func testWhenStoppedBeforeBeingInitialized_itThrowsProgrammerError() throws {
        XCTAssertThrowsError(try Datadog.stopOrThrow()) { error in
            XCTAssertTrue((error as? ProgrammerError)?.description == "Attempted to stop SDK before it was initialized.")
        }
    }
}
