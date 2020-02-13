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

    func testItEvaluatesLogEndpoints() {
        XCTAssertEqual(Datadog.LogsEndpoint.us.url, "https://mobile-http-intake.logs.datadoghq.com/v1/input/")
        XCTAssertEqual(Datadog.LogsEndpoint.eu.url, "https://mobile-http-intake.logs.datadoghq.eu/v1/input/")
        XCTAssertEqual(
            Datadog.LogsEndpoint.custom(url: "https://api.example.com/v1/logs/").url,
            "https://api.example.com/v1/logs/"
        )
    }

    func testItCanBeInitializedWithValidConfiguration() throws {
        Datadog.initialize(
            appContext: .mockAny(),
            endpoint: .custom(url: "https://api.example.com/v1/logs/"),
            clientToken: "abcdefghi"
        )
        XCTAssertNotNil(Datadog.instance)
        try Datadog.deinitializeOrThrow()
    }

    func testWhenInitializedWithInvalidConfiguration_itThrowsProgrammerError() {
        XCTAssertThrowsError(
            try Datadog.initializeOrThrow(appContext: .mockAny(), endpoint: .us, clientToken: "")
        ) { error in
            XCTAssertTrue(error is ProgrammerError)
        }
    }

    func testWhenInitializedMoreThanOnce_itThrowsProgrammerError() throws {
        let initialize = {
            try Datadog.initializeOrThrow(
                appContext: .mockAny(),
                endpoint: .custom(url: "https://api.example.com/v1/logs/"),
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
